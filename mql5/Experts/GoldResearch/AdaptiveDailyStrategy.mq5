#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input ulong InpMagic = 29000001;
input double InpVolume = 0.01;
input int InpSignalAType = 0;
input int InpSignalAPeriod = 5;
input bool InpSignalAInvert = false;
input int InpSignalAWeight = 2;
input int InpSignalBType = 1;
input int InpSignalBPeriod = 3;
input bool InpSignalBInvert = false;
input int InpSignalBWeight = 1;
input int InpSignalCType = 2;
input int InpSignalCPeriod = 20;
input bool InpSignalCInvert = false;
input int InpSignalCWeight = 1;
input int InpRegimeMode = 0;
input int InpHoldHours = 8;
input int InpAtrPeriod = 14;
input double InpStopAtrMultiple = 2.0;
input double InpTargetAtrMultiple = 0.0;
input double InpTrailAtrMultiple = 0.0;
input int InpMaxDeviationPoints = 100;
input string InpOutputName = "AdaptiveDailyStrategy";

CTrade g_trade;
int g_atr_handle = INVALID_HANDLE;
int g_signal_handles[3];
int g_signal_types[3];
int g_signal_periods[3];
bool g_signal_inverts[3];
int g_signal_weights[3];
int g_day_key = -1;
bool g_opened_today = false;
bool g_day_flushed = false;
int g_active_days = 0;
int g_covered_days = 0;
datetime g_entry_time = 0;
int g_coverage_file = INVALID_HANDLE;

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

int CreateSignalHandle(const int type, const int period)
{
   if(type == 2)
      return iMA(_Symbol, PERIOD_D1, period, 0, MODE_EMA, PRICE_CLOSE);
   if(type == 3)
      return iRSI(_Symbol, PERIOD_D1, period, PRICE_CLOSE);
   return INVALID_HANDLE;
}

bool SignalDirection(const int index, bool &buy)
{
   const int type = g_signal_types[index];
   const int period = g_signal_periods[index];
   double closes[];
   ArraySetAsSeries(closes, true);
   if(CopyClose(_Symbol, PERIOD_D1, 1, period + 1, closes) != period + 1)
      return false;

   if(type == 0)
      buy = closes[0] >= closes[period];
   else if(type == 1)
   {
      double opens[1];
      if(CopyOpen(_Symbol, PERIOD_D1, 1, 1, opens) != 1)
         return false;
      buy = closes[0] >= opens[0];
   }
   else if(type == 2 || type == 3)
   {
      double value[1];
      if(g_signal_handles[index] == INVALID_HANDLE ||
         CopyBuffer(g_signal_handles[index], 0, 1, 1, value) != 1)
         return false;
      buy = type == 2 ? closes[0] >= value[0] : value[0] >= 50.0;
   }
   else if(type == 4)
   {
      double highs[];
      double lows[];
      ArraySetAsSeries(highs, true);
      ArraySetAsSeries(lows, true);
      if(CopyHigh(_Symbol, PERIOD_D1, 1, period, highs) != period ||
         CopyLow(_Symbol, PERIOD_D1, 1, period, lows) != period)
         return false;
      double highest = highs[0];
      double lowest = lows[0];
      for(int bar = 1; bar < period; bar++)
      {
         highest = MathMax(highest, highs[bar]);
         lowest = MathMin(lowest, lows[bar]);
      }
      buy = closes[0] >= (highest + lowest) * 0.5;
   }
   else
   {
      double sum = 0.0;
      for(int bar = 0; bar < period; bar++)
         sum += closes[bar] - closes[bar + 1];
      buy = sum >= 0.0;
   }
   if(g_signal_inverts[index])
      buy = !buy;
   return true;
}

bool BuyDirection(bool &buy)
{
   bool directions[3];
   for(int index = 0; index < 3; index++)
   {
      if(!SignalDirection(index, directions[index]))
         return false;
   }

   int first = 0;
   int last = 2;
   if(InpRegimeMode != 0)
   {
      double atr_values[21];
      if(CopyBuffer(g_atr_handle, 0, 1, 21, atr_values) == 21)
      {
         double average = 0.0;
         for(int index = 1; index < 21; index++)
            average += atr_values[index];
         average /= 20.0;
         const bool high_volatility = atr_values[0] >= average;
         if((InpRegimeMode == 1 && high_volatility) ||
            (InpRegimeMode == 2 && !high_volatility))
            last = 1;
         else
            first = 1;
      }
   }

   int score = 0;
   for(int index = first; index <= last; index++)
      score += directions[index] ? g_signal_weights[index] : -g_signal_weights[index];
   buy = score >= 0;
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
   const double stop_distance = atr[0] * InpStopAtrMultiple;
   const double target_distance = atr[0] * InpTargetAtrMultiple;
   const double stop = NormalizePrice(buy ? entry - stop_distance : entry + stop_distance);
   const double target = InpTargetAtrMultiple <= 0.0 ? 0.0 :
      NormalizePrice(buy ? entry + target_distance : entry - target_distance);
   const bool sent = buy
      ? g_trade.Buy(InpVolume, _Symbol, 0.0, stop, target, "ADS")
      : g_trade.Sell(InpVolume, _Symbol, 0.0, stop, target, "ADS");
   const uint retcode = g_trade.ResultRetcode();
   const bool executed = sent &&
      (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL) &&
      PositionTicket() != 0;
   if(executed)
   {
      g_opened_today = true;
      g_entry_time = tick.time;
   }
   return executed;
}

void TrailPosition(const ulong ticket, const MqlTick &tick)
{
   if(InpTrailAtrMultiple <= 0.0)
      return;
   double atr[1];
   if(CopyBuffer(g_atr_handle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
      return;
   const long type = PositionGetInteger(POSITION_TYPE);
   const double current = PositionGetDouble(POSITION_SL);
   const double candidate = NormalizePrice(type == POSITION_TYPE_BUY
      ? tick.bid - atr[0] * InpTrailAtrMultiple
      : tick.ask + atr[0] * InpTrailAtrMultiple);
   const bool improve = type == POSITION_TYPE_BUY
      ? candidate > current && candidate < tick.bid
      : candidate < current && candidate > tick.ask;
   if(improve)
      g_trade.PositionModify(ticket, candidate, PositionGetDouble(POSITION_TP));
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) || InpVolume <= 0.0 ||
      InpHoldHours < 1 || InpHoldHours > 23 || InpAtrPeriod < 2 ||
      InpStopAtrMultiple <= 0.0 || InpTargetAtrMultiple < 0.0 ||
      InpTrailAtrMultiple < 0.0 || InpRegimeMode < 0 || InpRegimeMode > 2)
      return INIT_PARAMETERS_INCORRECT;
   g_signal_types[0] = InpSignalAType;
   g_signal_types[1] = InpSignalBType;
   g_signal_types[2] = InpSignalCType;
   g_signal_periods[0] = InpSignalAPeriod;
   g_signal_periods[1] = InpSignalBPeriod;
   g_signal_periods[2] = InpSignalCPeriod;
   g_signal_inverts[0] = InpSignalAInvert;
   g_signal_inverts[1] = InpSignalBInvert;
   g_signal_inverts[2] = InpSignalCInvert;
   g_signal_weights[0] = InpSignalAWeight;
   g_signal_weights[1] = InpSignalBWeight;
   g_signal_weights[2] = InpSignalCWeight;
   for(int index = 0; index < 3; index++)
   {
      g_signal_handles[index] = INVALID_HANDLE;
      if(g_signal_types[index] < 0 || g_signal_types[index] > 5 ||
         g_signal_periods[index] < 1 || g_signal_periods[index] > 60 ||
         g_signal_weights[index] < 1 || g_signal_weights[index] > 4)
         return INIT_PARAMETERS_INCORRECT;
      g_signal_handles[index] = CreateSignalHandle(g_signal_types[index], g_signal_periods[index]);
   }
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
   if(ticket != 0)
   {
      TrailPosition(ticket, tick);
      if(g_entry_time > 0 && tick.time >= g_entry_time + InpHoldHours * 3600)
         g_trade.PositionClose(ticket);
   }
}

void OnDeinit(const int reason)
{
   FlushDay();
   if(g_coverage_file != INVALID_HANDLE)
      FileClose(g_coverage_file);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   for(int index = 0; index < 3; index++)
      if(g_signal_handles[index] != INVALID_HANDLE)
         IndicatorRelease(g_signal_handles[index]);
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
   PrintFormat("ADS|tester_summary|initial=%.2f|balance=%.2f|profit=%.2f|profit_factor=%.6f|balance_dd_pct=%.6f|equity_dd_pct=%.6f|trades=%I64d|deals=%I64d|active_days=%d|covered_days=%d|missing_days=%d",
               initial, initial + profit, profit, profit_factor, balance_dd,
               equity_dd, trades, deals, g_active_days, g_covered_days, missing_days);
   return missing_days == 0 ? profit : -1000000000.0 - missing_days;
}
