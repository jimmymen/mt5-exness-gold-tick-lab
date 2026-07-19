#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input string InpRunLabel = "auto";
input ulong InpMagic = 26071701;
input double InpVolume = 0.01;
input int InpOpenHourUtc = 8;
input int InpCloseHourUtc = 12;
input int InpMaxDeviationPoints = 0;

CTrade g_trade;
int g_day_key = -1;
bool g_open_attempted = false;
bool g_close_attempted = false;
long g_total_ticks = 0;
long g_first_msc = 0;
long g_last_msc = 0;
long g_day_ticks = 0;
long g_day_first_msc = 0;
long g_day_last_msc = 0;
long g_day_time_sum_mod = 0;
long g_day_bid_points_sum = 0;
long g_day_ask_points_sum = 0;
int g_daily_file = INVALID_HANDLE;
bool g_day_flushed = false;

string OutputPath(const string suffix)
{
   return "GoldResearch\\Parity\\" + InpRunLabel + "-" + suffix + ".csv";
}

int DayKey(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.year * 10000 + parts.mon * 100 + parts.day;
}

void FlushDay()
{
   if(g_daily_file == INVALID_HANDLE || g_day_key < 0 || g_day_ticks == 0 ||
      g_day_flushed)
      return;
   FileWrite(g_daily_file,
             g_day_key,
             g_day_ticks,
             g_day_first_msc,
             g_day_last_msc,
             g_day_time_sum_mod,
             g_day_bid_points_sum,
             g_day_ask_points_sum);
   FileFlush(g_daily_file);
   g_day_flushed = true;
}

void ResetDay(const int day_key)
{
   FlushDay();
   g_day_key = day_key;
   g_open_attempted = false;
   g_close_attempted = false;
   g_day_ticks = 0;
   g_day_first_msc = 0;
   g_day_last_msc = 0;
   g_day_time_sum_mod = 0;
   g_day_bid_points_sum = 0;
   g_day_ask_points_sum = 0;
   g_day_flushed = false;
}

bool HasPosition()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

void OpenScheduledPosition()
{
   const bool buy = (g_day_key % 2) == 0;
   const bool sent = buy
      ? g_trade.Buy(InpVolume, _Symbol, 0.0, 0.0, 0.0, "PARITY")
      : g_trade.Sell(InpVolume, _Symbol, 0.0, 0.0, 0.0, "PARITY");
   PrintFormat("PARITY|order|action=open|day=%d|side=%s|sent=%d|retcode=%u|price=%.5f",
               g_day_key, buy ? "buy" : "sell", (int)sent,
               g_trade.ResultRetcode(), g_trade.ResultPrice());
}

void CloseScheduledPosition()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
      {
         const bool sent = g_trade.PositionClose(ticket);
         PrintFormat("PARITY|order|action=close|day=%d|sent=%d|retcode=%u|price=%.5f",
                     g_day_key, (int)sent, g_trade.ResultRetcode(), g_trade.ResultPrice());
      }
   }
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) || InpRunLabel == "" || InpVolume <= 0.0 ||
      InpOpenHourUtc < 0 || InpOpenHourUtc > 22 ||
      InpCloseHourUtc <= InpOpenHourUtc || InpCloseHourUtc > 23)
      return INIT_PARAMETERS_INCORRECT;

   FolderCreate("GoldResearch\\Parity", FILE_COMMON);
   g_daily_file = FileOpen(OutputPath("daily"),
                           FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
                           ',');
   if(g_daily_file == INVALID_HANDLE)
   {
      PrintFormat("PARITY|fatal|open_daily|error=%d", GetLastError());
      return INIT_FAILED;
   }
   FileWrite(g_daily_file,
             "day_utc", "ticks", "first_msc", "last_msc", "time_sum_mod",
             "bid_points_sum", "ask_points_sum");
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   PrintFormat("PARITY|init|run=%s|symbol=%s|build=%d|server=%s",
               InpRunLabel, _Symbol, (int)TerminalInfoInteger(TERMINAL_BUILD),
               AccountInfoString(ACCOUNT_SERVER));
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   const int day_key = DayKey(tick.time);
   if(day_key != g_day_key)
      ResetDay(day_key);

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const long bid_points = (long)MathRound(tick.bid / point);
   const long ask_points = (long)MathRound(tick.ask / point);
   if(g_first_msc == 0)
      g_first_msc = tick.time_msc;
   if(g_day_first_msc == 0)
      g_day_first_msc = tick.time_msc;
   g_last_msc = tick.time_msc;
   g_day_last_msc = tick.time_msc;
   g_total_ticks++;
   g_day_ticks++;
   g_day_time_sum_mod = (g_day_time_sum_mod + tick.time_msc) % 1000000000000000000;
   g_day_bid_points_sum += bid_points;
   g_day_ask_points_sum += ask_points;

   MqlDateTime now;
   TimeToStruct(tick.time, now);
   if(!g_open_attempted && now.hour >= InpOpenHourUtc)
   {
      g_open_attempted = true;
      if(!HasPosition())
         OpenScheduledPosition();
   }
   if(!g_close_attempted && now.hour >= InpCloseHourUtc)
   {
      g_close_attempted = true;
      if(HasPosition())
         CloseScheduledPosition();
   }
}

void WriteDeals()
{
   const int file = FileOpen(OutputPath("deals"),
                             FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
                             ',');
   if(file == INVALID_HANDLE)
      return;
   FileWrite(file,
             "index", "time_msc", "type", "entry", "volume", "price",
             "commission", "swap", "profit");
   HistorySelect(0, TimeCurrent());
   int output_index = 0;
   for(int index = 0; index < HistoryDealsTotal(); index++)
   {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0 || HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
         continue;
      FileWrite(file,
                output_index++,
                HistoryDealGetInteger(ticket, DEAL_TIME_MSC),
                HistoryDealGetInteger(ticket, DEAL_TYPE),
                HistoryDealGetInteger(ticket, DEAL_ENTRY),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_VOLUME), 2),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PRICE),
                               (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_COMMISSION), 8),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_SWAP), 8),
                DoubleToString(HistoryDealGetDouble(ticket, DEAL_PROFIT), 8));
   }
   FileClose(file);
}

double OnTester()
{
   FlushDay();
   FileFlush(g_daily_file);
   WriteDeals();
   const double initial = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double profit = TesterStatistics(STAT_PROFIT);
   const double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   const double balance_dd = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   const double equity_dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   const long trades = (long)TesterStatistics(STAT_TRADES);
   const long deals = (long)TesterStatistics(STAT_DEALS);
   const int file = FileOpen(OutputPath("summary"),
                             FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON,
                             ',');
   if(file != INVALID_HANDLE)
   {
      FileWrite(file, "key", "value");
      FileWrite(file, "run_label", InpRunLabel);
      FileWrite(file, "symbol", _Symbol);
      FileWrite(file, "terminal_build", TerminalInfoInteger(TERMINAL_BUILD));
      FileWrite(file, "ticks", g_total_ticks);
      FileWrite(file, "first_msc", g_first_msc);
      FileWrite(file, "last_msc", g_last_msc);
      FileWrite(file, "initial", DoubleToString(initial, 2));
      FileWrite(file, "balance", DoubleToString(initial + profit, 2));
      FileWrite(file, "profit", DoubleToString(profit, 8));
      FileWrite(file, "profit_factor", DoubleToString(profit_factor, 8));
      FileWrite(file, "balance_dd_pct", DoubleToString(balance_dd, 8));
      FileWrite(file, "equity_dd_pct", DoubleToString(equity_dd, 8));
      FileWrite(file, "trades", trades);
      FileWrite(file, "deals", deals);
      FileClose(file);
   }
   PrintFormat("PARITY|summary|run=%s|ticks=%I64d|first_msc=%I64d|last_msc=%I64d|profit=%.8f|pf=%.8f|balance_dd=%.8f|equity_dd=%.8f|trades=%I64d|deals=%I64d",
               InpRunLabel, g_total_ticks, g_first_msc, g_last_msc, profit,
               profit_factor, balance_dd, equity_dd, trades, deals);
   return profit;
}

void OnDeinit(const int reason)
{
   FlushDay();
   if(g_daily_file != INVALID_HANDLE)
      FileClose(g_daily_file);
   PrintFormat("PARITY|deinit|run=%s|reason=%d", InpRunLabel, reason);
}
