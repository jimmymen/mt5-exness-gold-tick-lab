#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input ulong InpMagic = 28000001;
input double InpVolume = 0.01;
input int InpDirectionMode = 0;
input int InpDirectionLookback = 5;
input int InpHoldHours = 8;
input int InpAtrPeriod = 14;
input double InpStopAtrMultiple = 2.0;
input int InpMaxDeviationPoints = 100;
input string InpOutputName = "DailyTradeStrategy";

CTrade g_trade;
int g_atr_handle = INVALID_HANDLE;
int g_day_key = -1;
bool g_opened_today = false;
int g_active_days = 0;
int g_covered_days = 0;
datetime g_entry_time = 0;
int g_coverage_file = INVALID_HANDLE;
bool g_day_flushed = false;

int DayKey(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.year * 10000 + parts.mon * 100 + parts.day;
}

double NormalizePrice(const double price)
{
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   return NormalizeDouble(MathRound(price / tick_size) * tick_size,
                          (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

ulong PositionTicket()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return ticket;
   }
   return 0;
}

void FlushDay()
{
   if(g_day_key < 0 || g_day_flushed)
      return;
   if(g_opened_today)
      g_covered_days++;
   if(g_coverage_file != INVALID_HANDLE)
      FileWrite(g_coverage_file, g_day_key, g_opened_today ? 1 : 0);
   g_day_flushed = true;
}

void StartDay(const int day_key)
{
   FlushDay();
   g_day_key = day_key;
   g_opened_today = false;
   g_day_flushed = false;
   g_active_days++;
}

bool BuyDirection(bool &buy)
{
   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(_Symbol, PERIOD_D1, 1, InpDirectionLookback + 1, closes) !=
      InpDirectionLookback + 1)
      return false;
   const bool trend_up = closes[0] >= closes[InpDirectionLookback];
   buy = InpDirectionMode == 0 ? trend_up : !trend_up;
   return true;
}

bool OpenDailyPosition(const MqlTick &tick)
{
   double atr[1];
   if(CopyBuffer(g_atr_handle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
      return false;
   bool buy;
   if(!BuyDirection(buy))
      return false;
   const double entry = buy ? tick.ask : tick.bid;
   const double distance = atr[0] * InpStopAtrMultiple;
   const double stop = NormalizePrice(buy ? entry - distance : entry + distance);
   const bool sent = buy
      ? g_trade.Buy(InpVolume, _Symbol, 0.0, stop, 0.0, "DTD")
      : g_trade.Sell(InpVolume, _Symbol, 0.0, stop, 0.0, "DTD");
   const uint retcode = g_trade.ResultRetcode();
   const bool executed = sent &&
      (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL) &&
      PositionTicket() != 0;
   if(executed)
   {
      g_opened_today = true;
      g_entry_time = tick.time;
      PrintFormat("DTD|entry|day=%d|side=%s|price=%.3f|sl=%.3f|retcode=%u",
                  g_day_key, buy ? "buy" : "sell", entry, stop,
                   retcode);
   }
   return executed;
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) || InpVolume <= 0.0 ||
      InpDirectionMode < 0 || InpDirectionMode > 1 ||
      InpDirectionLookback < 1 || InpHoldHours < 1 || InpHoldHours > 23 ||
      InpAtrPeriod < 2 || InpStopAtrMultiple <= 0.0)
      return INIT_PARAMETERS_INCORRECT;
   g_atr_handle = iATR(_Symbol, PERIOD_D1, InpAtrPeriod);
   if(g_atr_handle == INVALID_HANDLE)
      return INIT_FAILED;
   FolderCreate("GoldResearch\\Published", FILE_COMMON);
   g_coverage_file = FileOpen("GoldResearch\\Published\\" + InpOutputName + "-coverage.csv",
                              FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(g_coverage_file == INVALID_HANDLE)
      return INIT_FAILED;
   FileWrite(g_coverage_file, "day_utc", "entries");
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   const int day_key = DayKey(tick.time);
   if(day_key != g_day_key)
   {
      const ulong old_ticket = PositionTicket();
      if(old_ticket != 0)
         g_trade.PositionClose(old_ticket);
      StartDay(day_key);
   }

   const ulong ticket = PositionTicket();
   if(ticket == 0 && !g_opened_today)
   {
      OpenDailyPosition(tick);
      return;
   }
   if(ticket != 0 && g_entry_time > 0 &&
      tick.time >= g_entry_time + InpHoldHours * 3600)
      g_trade.PositionClose(ticket);
}

void OnDeinit(const int reason)
{
   FlushDay();
   if(g_coverage_file != INVALID_HANDLE)
      FileClose(g_coverage_file);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
}

double OnTester()
{
   FlushDay();
   if(g_coverage_file != INVALID_HANDLE)
      FileFlush(g_coverage_file);
   const double initial = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double profit = TesterStatistics(STAT_PROFIT);
   const double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   const double balance_dd = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   const double equity_dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   const long trades = (long)TesterStatistics(STAT_TRADES);
   const long deals = (long)TesterStatistics(STAT_DEALS);
   const int missing_days = g_active_days - g_covered_days;

   const int curve_file = FileOpen("GoldResearch\\Published\\" + InpOutputName + "-equity.csv",
                                   FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(curve_file != INVALID_HANDLE)
   {
      FileWrite(curve_file, "time_msc", "balance");
      double balance = initial;
      FileWrite(curve_file, 0, DoubleToString(balance, 2));
      HistorySelect(0, TimeCurrent());
      for(int index = 0; index < HistoryDealsTotal(); index++)
      {
         const ulong deal = HistoryDealGetTicket(index);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
            (ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic)
            continue;
         const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
            continue;
         balance += HistoryDealGetDouble(deal, DEAL_PROFIT) +
                    HistoryDealGetDouble(deal, DEAL_COMMISSION) +
                    HistoryDealGetDouble(deal, DEAL_SWAP);
         FileWrite(curve_file, HistoryDealGetInteger(deal, DEAL_TIME_MSC),
                   DoubleToString(balance, 2));
      }
      FileClose(curve_file);
   }
   PrintFormat("DTD|tester_summary|initial=%.2f|balance=%.2f|profit=%.2f|profit_factor=%.6f|balance_dd_pct=%.6f|equity_dd_pct=%.6f|trades=%I64d|deals=%I64d|active_days=%d|covered_days=%d|missing_days=%d",
               initial, initial + profit, profit, profit_factor, balance_dd,
               equity_dd, trades, deals, g_active_days, g_covered_days, missing_days);
   return missing_days == 0 ? profit : -1000000000.0 - missing_days;
}
