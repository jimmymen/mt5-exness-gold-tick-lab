#property copyright "MT5 Gold Research"
#property version   "1.000"
#property strict

#include <Trade/Trade.mqh>

input bool InpEnableTrading = false;
input ulong InpMagic = 26071602;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_H1;
input int InpTrendFastPeriod = 50;
input int InpTrendSlowPeriod = 200;
input int InpPullbackEmaPeriod = 20;
input int InpAtrPeriod = 14;
input double InpStopAtrMultiple = 1.5;
input double InpRewardRisk = 2.0;
input double InpRiskPercent = 0.25;
input double InpMaxSpreadPrice = 0.50;
input int InpTradeStartHour = 7;
input int InpTradeEndHour = 20;
input int InpForceExitHour = 22;
input int InpMaxDeviationPoints = 100;

CTrade g_trade;
int g_trend_fast_handle = INVALID_HANDLE;
int g_trend_slow_handle = INVALID_HANDLE;
int g_pullback_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;
int g_day_key = -1;
bool g_traded_today = false;

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

double NormalizeVolumeDown(const double volume)
{
   const double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;
   double normalized = MathFloor(volume / step + 1e-9) * step;
   normalized = MathMin(normalized, maximum);
   if(normalized < minimum)
      return 0.0;
   return NormalizeDouble(normalized, 8);
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

void ClosePositions()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         g_trade.PositionClose(ticket);
   }
}

double RiskVolume(const ENUM_ORDER_TYPE order_type, const double entry, const double stop)
{
   double loss = 0.0;
   if(!OrderCalcProfit(order_type, _Symbol, 1.0, entry, stop, loss))
      return 0.0;
   loss = MathAbs(loss);
   if(loss <= 0.0)
      return 0.0;
   const double risk = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   return NormalizeVolumeDown(risk / loss);
}

bool OpenPosition(const ENUM_ORDER_TYPE order_type, const MqlTick &tick, const double atr)
{
   const bool buy = order_type == ORDER_TYPE_BUY;
   const double entry = buy ? tick.ask : tick.bid;
   const double distance = atr * InpStopAtrMultiple;
   const double stop = NormalizePrice(buy ? entry - distance : entry + distance);
   const double target = NormalizePrice(buy ? entry + distance * InpRewardRisk
                                            : entry - distance * InpRewardRisk);
   const double volume = RiskVolume(order_type, entry, stop);
   if(volume <= 0.0)
      return false;

   const bool sent = buy
      ? g_trade.Buy(volume, _Symbol, 0.0, stop, target, "TPB")
      : g_trade.Sell(volume, _Symbol, 0.0, stop, target, "TPB");
   PrintFormat("TPB|entry|side=%s|volume=%.2f|request=%.3f|sl=%.3f|tp=%.3f|atr=%.3f|spread=%.3f|retcode=%u|description=%s",
               buy ? "buy" : "sell", volume, entry, stop, target, atr,
               tick.ask - tick.bid, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return sent;
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) && !InpEnableTrading)
      return INIT_PARAMETERS_INCORRECT;
   if(InpTrendFastPeriod < 2 || InpTrendSlowPeriod <= InpTrendFastPeriod ||
      InpPullbackEmaPeriod < 2 || InpAtrPeriod < 2 || InpStopAtrMultiple <= 0.0 ||
      InpRewardRisk <= 0.0 || InpRiskPercent <= 0.0 || InpMaxSpreadPrice <= 0.0 ||
      InpTradeStartHour < 0 || InpTradeEndHour <= InpTradeStartHour ||
      InpForceExitHour < InpTradeEndHour || InpForceExitHour > 23)
      return INIT_PARAMETERS_INCORRECT;

   g_trend_fast_handle = iMA(_Symbol, InpTrendTimeframe, InpTrendFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_trend_slow_handle = iMA(_Symbol, InpTrendTimeframe, InpTrendSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_pullback_handle = iMA(_Symbol, InpSignalTimeframe, InpPullbackEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, InpSignalTimeframe, InpAtrPeriod);
   if(g_trend_fast_handle == INVALID_HANDLE || g_trend_slow_handle == INVALID_HANDLE ||
      g_pullback_handle == INVALID_HANDLE || g_atr_handle == INVALID_HANDLE)
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   PrintFormat("TPB|init|symbol=%s|server=%s|tester=%d", _Symbol,
               AccountInfoString(ACCOUNT_SERVER), (int)MQLInfoInteger(MQL_TESTER));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_trend_fast_handle != INVALID_HANDLE) IndicatorRelease(g_trend_fast_handle);
   if(g_trend_slow_handle != INVALID_HANDLE) IndicatorRelease(g_trend_slow_handle);
   if(g_pullback_handle != INVALID_HANDLE) IndicatorRelease(g_pullback_handle);
   if(g_atr_handle != INVALID_HANDLE) IndicatorRelease(g_atr_handle);
   PrintFormat("TPB|deinit|reason=%d", reason);
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   MqlDateTime now;
   TimeToStruct(tick.time, now);
   const int day_key = DayKey(tick.time);
   if(day_key != g_day_key)
   {
      g_day_key = day_key;
      g_traded_today = false;
   }

   if(now.hour >= InpForceExitHour)
   {
      if(HasPosition()) ClosePositions();
      return;
   }

   const datetime current_bar = iTime(_Symbol, InpSignalTimeframe, 0);
   if(current_bar <= 0 || current_bar == g_last_bar_time)
      return;
   g_last_bar_time = current_bar;

   if(g_traded_today || HasPosition() || now.hour < InpTradeStartHour || now.hour >= InpTradeEndHour ||
      tick.ask - tick.bid > InpMaxSpreadPrice)
      return;

   MqlRates bars[2];
   double pullback_ema[2];
   double trend_fast[1];
   double trend_slow[1];
   double trend_close[1];
   double atr[1];
   if(CopyRates(_Symbol, InpSignalTimeframe, 1, 2, bars) != 2 ||
      CopyBuffer(g_pullback_handle, 0, 1, 2, pullback_ema) != 2 ||
      CopyBuffer(g_trend_fast_handle, 0, 1, 1, trend_fast) != 1 ||
      CopyBuffer(g_trend_slow_handle, 0, 1, 1, trend_slow) != 1 ||
      CopyClose(_Symbol, InpTrendTimeframe, 1, 1, trend_close) != 1 ||
      CopyBuffer(g_atr_handle, 0, 1, 1, atr) != 1)
      return;

   const bool uptrend = trend_close[0] > trend_fast[0] && trend_fast[0] > trend_slow[0];
   const bool downtrend = trend_close[0] < trend_fast[0] && trend_fast[0] < trend_slow[0];
   const bool buy_signal = uptrend && bars[0].close <= pullback_ema[0] &&
      bars[1].close > pullback_ema[1] && bars[1].close > bars[1].open;
   const bool sell_signal = downtrend && bars[0].close >= pullback_ema[0] &&
      bars[1].close < pullback_ema[1] && bars[1].close < bars[1].open;

   bool opened = false;
   if(buy_signal)
      opened = OpenPosition(ORDER_TYPE_BUY, tick, atr[0]);
   else if(sell_signal)
      opened = OpenPosition(ORDER_TYPE_SELL, tick, atr[0]);
   if(opened)
      g_traded_today = true;
}

double OnTester()
{
   const double initial = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double profit = TesterStatistics(STAT_PROFIT);
   const double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   const double payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   const double balance_dd = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   const double equity_dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   const long trades = (long)TesterStatistics(STAT_TRADES);
   const long deals = (long)TesterStatistics(STAT_DEALS);
   PrintFormat("TPB|tester_summary|initial=%.2f|balance=%.2f|profit=%.2f|profit_factor=%.6f|expected_payoff=%.6f|balance_dd_pct=%.6f|equity_dd_pct=%.6f|trades=%I64d|deals=%I64d",
               initial, initial + profit, profit, profit_factor, payoff, balance_dd, equity_dd, trades, deals);
   return profit;
}
