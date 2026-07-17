#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

input string InpSourceSymbol = "XAUUSDm";
input string InpCustomSymbol = "XAUUSDm_EXNESS_V2";
input string InpCustomPath = "GoldResearch";
input string InpCsvFile = "GoldResearch\\Exness_XAUUSDm_sample_MT5_UTC.csv";
input int InpBatchSize = 200000;
input bool InpCloseTerminal = true;

bool ParseDateTime(const string date_value,
                   const string time_value,
                   datetime &seconds,
                   long &milliseconds)
{
   string parts[];
   if(StringSplit(time_value, '.', parts) != 2)
      return false;
   seconds = StringToTime(date_value + " " + parts[0]);
   if(seconds <= 0)
      return false;
   milliseconds = (long)StringToInteger(parts[1]);
   return milliseconds >= 0 && milliseconds <= 999;
}

bool FlushTicks(MqlTick &ticks[],
                const int count,
                long &written,
                long &first_msc,
                long &last_msc,
                double &first_bid,
                double &first_ask,
                double &last_bid,
                double &last_ask)
{
   if(count == 0)
      return true;
   ArrayResize(ticks, count);
   ResetLastError();
   const int replaced = CustomTicksReplace(InpCustomSymbol,
                                           (ulong)ticks[0].time_msc,
                                           (ulong)ticks[count - 1].time_msc,
                                           ticks);
   if(replaced != count)
   {
      PrintFormat("IMPORT|fatal|replace|expected=%d|actual=%d|error=%d",
                  count, replaced, GetLastError());
      return false;
   }
   MqlTick verify[];
   ResetLastError();
   const int copied = CopyTicksRange(InpCustomSymbol,
                                     verify,
                                     COPY_TICKS_ALL,
                                     (ulong)ticks[0].time_msc,
                                     (ulong)ticks[count - 1].time_msc);
   if(copied != count ||
      verify[0].time_msc != ticks[0].time_msc ||
      verify[copied - 1].time_msc != ticks[count - 1].time_msc ||
      verify[0].bid != ticks[0].bid || verify[0].ask != ticks[0].ask ||
      verify[copied - 1].bid != ticks[count - 1].bid ||
      verify[copied - 1].ask != ticks[count - 1].ask)
   {
      PrintFormat("IMPORT|fatal|verify_batch|expected=%d|actual=%d|error=%d",
                  count, copied, GetLastError());
      return false;
   }
   if(written == 0)
   {
      first_msc = ticks[0].time_msc;
      first_bid = ticks[0].bid;
      first_ask = ticks[0].ask;
   }
   last_msc = ticks[count - 1].time_msc;
   last_bid = ticks[count - 1].bid;
   last_ask = ticks[count - 1].ask;
   written += count;
   PrintFormat("IMPORT|batch|count=%d|total=%I64d|first_msc=%I64d|last_msc=%I64d",
               count, written, ticks[0].time_msc, ticks[count - 1].time_msc);
   ArrayResize(ticks, InpBatchSize + 1024);
   return true;
}

int OnInit()
{
   if(InpBatchSize < 1)
      return INIT_PARAMETERS_INCORRECT;

   bool is_custom = false;
   if(!SymbolExist(InpCustomSymbol, is_custom))
   {
      ResetLastError();
      if(!CustomSymbolCreate(InpCustomSymbol, InpCustomPath, InpSourceSymbol))
      {
         const int create_error = GetLastError();
         ResetLastError();
         if(!SymbolSelect(InpCustomSymbol, true))
         {
            PrintFormat("IMPORT|fatal|create_symbol|create_error=%d|select_error=%d",
                        create_error, GetLastError());
            return INIT_FAILED;
         }
      }
   }
   if(!SymbolSelect(InpCustomSymbol, true))
   {
      PrintFormat("IMPORT|fatal|select_symbol|error=%d", GetLastError());
      return INIT_FAILED;
   }

   ResetLastError();
   const int handle = FileOpen(InpCsvFile,
                               FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON,
                               ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("IMPORT|fatal|open|file=%s|error=%d", InpCsvFile, GetLastError());
      return INIT_FAILED;
   }

   for(int column = 0; column < 6 && !FileIsEnding(handle); column++)
      FileReadString(handle);

   MqlTick ticks[];
   ArrayResize(ticks, InpBatchSize + 1024);
   int count = 0;
   long source_rows = 0;
   long written = 0;
   long first_msc = 0;
   long last_msc = 0;
   double first_bid = 0.0;
   double first_ask = 0.0;
   double last_bid = 0.0;
   double last_ask = 0.0;

   while(!FileIsEnding(handle))
   {
      const string date_value = FileReadString(handle);
      if(date_value == "" && FileIsEnding(handle))
         break;
      const string time_value = FileReadString(handle);
      const double bid = FileReadNumber(handle);
      const double ask = FileReadNumber(handle);
      FileReadString(handle);
      FileReadString(handle);

      datetime seconds = 0;
      long milliseconds = 0;
      if(!ParseDateTime(date_value, time_value, seconds, milliseconds) ||
         bid <= 0.0 || ask < bid)
      {
         PrintFormat("IMPORT|fatal|row|row=%I64d|date=%s|time=%s|bid=%.5f|ask=%.5f",
                     source_rows + 1, date_value, time_value, bid, ask);
         FileClose(handle);
         return INIT_FAILED;
      }

      const long time_msc = (long)seconds * 1000 + milliseconds;
      if(count >= InpBatchSize && time_msc != ticks[count - 1].time_msc)
      {
         if(!FlushTicks(ticks, count, written, first_msc, last_msc,
                        first_bid, first_ask, last_bid, last_ask))
         {
            FileClose(handle);
            return INIT_FAILED;
         }
         count = 0;
      }
      if(count == ArraySize(ticks))
         ArrayResize(ticks, count + 1024);

      ZeroMemory(ticks[count]);
      ticks[count].time = seconds;
      ticks[count].time_msc = time_msc;
      ticks[count].bid = bid;
      ticks[count].ask = ask;
      ticks[count].flags = TICK_FLAG_BID | TICK_FLAG_ASK;
      count++;
      source_rows++;

   }
   FileClose(handle);

   if(!FlushTicks(ticks, count, written, first_msc, last_msc,
                  first_bid, first_ask, last_bid, last_ask))
      return INIT_FAILED;
   if(source_rows == 0 || source_rows != written)
   {
      PrintFormat("IMPORT|fatal|count|source=%I64d|written=%I64d", source_rows, written);
      return INIT_FAILED;
   }

   PrintFormat("IMPORT|summary|symbol=%s|source_rows=%I64d|written=%I64d|verified=%d|first_msc=%I64d|last_msc=%I64d|first_bid=%.5f|first_ask=%.5f|last_bid=%.5f|last_ask=%.5f",
               InpCustomSymbol, source_rows, written, 1, first_msc, last_msc,
               first_bid, first_ask, last_bid, last_ask);
   if(InpCloseTerminal)
      EventSetTimer(2);
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   EventKillTimer();
   Print("IMPORT|terminal_close|requested");
   TerminalClose(0);
}

void OnTick()
{
}
