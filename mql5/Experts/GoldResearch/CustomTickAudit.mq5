#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

input string InpSymbol = "XAUUSDm_EXNESS_V2";
input string InpStart = "2021.01.01";
input string InpEndExclusive = "2026.07.17";
input long InpExpectedTicks = 249744134;

int OnInit()
{
   const datetime start = StringToTime(InpStart);
   const datetime end_exclusive = StringToTime(InpEndExclusive);
   if(start <= 0 || end_exclusive <= start || !SymbolSelect(InpSymbol, true))
      return INIT_PARAMETERS_INCORRECT;

   long total = 0;
   long first_msc = 0;
   long last_msc = 0;
   double first_bid = 0.0;
   double first_ask = 0.0;
   double last_bid = 0.0;
   double last_ask = 0.0;
   int days = 0;

   for(datetime day = start; day < end_exclusive; day += 86400)
   {
      MqlTick ticks[];
      ResetLastError();
      const ulong from_msc = (ulong)((long)day * 1000);
      const ulong to_msc = (ulong)(((long)day + 86400) * 1000 - 1);
      const int copied = CopyTicksRange(InpSymbol, ticks, COPY_TICKS_ALL, from_msc, to_msc);
      if(copied < 0)
      {
         PrintFormat("AUDIT|fatal|copy|day=%s|error=%d",
                     TimeToString(day, TIME_DATE), GetLastError());
         return INIT_FAILED;
      }
      if(copied == 0)
         continue;
      for(int index = 1; index < copied; index++)
      {
         if(ticks[index].time_msc < ticks[index - 1].time_msc)
         {
            PrintFormat("AUDIT|fatal|reverse|day=%s|index=%d",
                        TimeToString(day, TIME_DATE), index);
            return INIT_FAILED;
         }
      }
      if(last_msc > 0 && ticks[0].time_msc < last_msc)
      {
         PrintFormat("AUDIT|fatal|cross_day_reverse|day=%s",
                     TimeToString(day, TIME_DATE));
         return INIT_FAILED;
      }
      if(total == 0)
      {
         first_msc = ticks[0].time_msc;
         first_bid = ticks[0].bid;
         first_ask = ticks[0].ask;
      }
      last_msc = ticks[copied - 1].time_msc;
      last_bid = ticks[copied - 1].bid;
      last_ask = ticks[copied - 1].ask;
      total += copied;
      days++;
      if(days % 100 == 0)
         PrintFormat("AUDIT|progress|days=%d|ticks=%I64d|last_msc=%I64d",
                     days, total, last_msc);
   }

   if(total != InpExpectedTicks)
   {
      PrintFormat("AUDIT|fatal|count|expected=%I64d|actual=%I64d",
                  InpExpectedTicks, total);
      return INIT_FAILED;
   }
   PrintFormat("AUDIT|summary|symbol=%s|ticks=%I64d|days=%d|first_msc=%I64d|last_msc=%I64d|first_bid=%.5f|first_ask=%.5f|last_bid=%.5f|last_ask=%.5f",
               InpSymbol, total, days, first_msc, last_msc,
               first_bid, first_ask, last_bid, last_ask);
   EventSetTimer(2);
   return INIT_SUCCEEDED;
}

void OnTimer()
{
   EventKillTimer();
   TerminalClose(0);
}

void OnTick()
{
}
