#property copyright "MT5 Gold Research"
#property version   "1.000"
#property strict

#include <Trade/Trade.mqh>

input bool InpEnableTrading = false;
input ulong InpMagic = 26071601;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M15;
input int InpAsiaStartHour = 0;
input int InpAsiaEndHour = 8;
input int InpTradeStartHour = 8;
input int InpTradeEndHour = 16;
input int InpForceExitHour = 20;
input int InpAtrPeriod = 14;
input bool InpUseTrendFilter = true;
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_H1;
input int InpTrendEmaPeriod = 200;
input bool InpRequireRetest = true;
input double InpRetestTolerance = 0.50;
input double InpStopAtrMultiple = 1.0;
input double InpRewardRisk = 2.0;
input double InpBreakoutBuffer = 0.10;
input double InpRiskPercent = 0.25;
input double InpMaxSpreadPrice = 0.50;
input int InpMaxDeviationPoints = 100;

CTrade g_trade;
int g_atr_handle = INVALID_HANDLE;
int g_trend_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;
int g_trading_day_key = -1;
bool g_traded_today = false;
double g_asia_high = 0.0;
double g_asia_low = 0.0;
bool g_range_ready = false;
int g_armed_direction = 0;
datetime g_armed_bar_time = 0;

int DayKey(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   return parts.year * 10000 + parts.mon * 100 + parts.day;
}

datetime DayStart(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min = 0;
   parts.sec = 0;
   return StructToTime(parts);
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

bool HasStrategyPosition()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
   }
   return false;
}

bool CloseStrategyPositions()
{
   bool success = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(!g_trade.PositionClose(ticket))
      {
         PrintFormat("ALB|close_failed|ticket=%I64u|retcode=%u|description=%s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         success = false;
      }
   }
   return success;
}

bool CalculateAsiaRange(const datetime current_time)
{
   const datetime start = DayStart(current_time) + InpAsiaStartHour * 3600;
   const datetime end = DayStart(current_time) + InpAsiaEndHour * 3600;
   if(end <= start || current_time < end)
      return false;

   MqlRates rates[];
   const int copied = CopyRates(_Symbol, InpSignalTimeframe, start, end - 1, rates);
   if(copied <= 0)
   {
      PrintFormat("ALB|range_failed|error=%d", GetLastError());
      return false;
   }

   double high = rates[0].high;
   double low = rates[0].low;
   for(int index = 1; index < copied; index++)
   {
      high = MathMax(high, rates[index].high);
      low = MathMin(low, rates[index].low);
   }

   g_asia_high = high;
   g_asia_low = low;
   g_range_ready = high > low;
   PrintFormat("ALB|range|day=%d|bars=%d|high=%.3f|low=%.3f|width=%.3f",
               DayKey(current_time), copied, high, low, high - low);
   return g_range_ready;
}

double CalculateRiskVolume(const ENUM_ORDER_TYPE order_type,
                           const double entry,
                           const double stop)
{
   const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double loss_for_one_lot = 0.0;
   if(!OrderCalcProfit(order_type, _Symbol, 1.0, entry, stop, loss_for_one_lot))
   {
      PrintFormat("ALB|risk_failed|error=%d", GetLastError());
      return 0.0;
   }
   loss_for_one_lot = MathAbs(loss_for_one_lot);
   if(loss_for_one_lot <= 0.0)
      return 0.0;
   return NormalizeVolumeDown(risk_money / loss_for_one_lot);
}

bool OpenPosition(const ENUM_ORDER_TYPE order_type,
                  const MqlTick &tick,
                  const double atr)
{
   const bool buy = order_type == ORDER_TYPE_BUY;
   const double entry = buy ? tick.ask : tick.bid;
   const double stop_distance = atr * InpStopAtrMultiple;
   if(stop_distance <= 0.0)
      return false;

   const double stop = NormalizePrice(buy ? entry - stop_distance : entry + stop_distance);
   const double target = NormalizePrice(buy ? entry + stop_distance * InpRewardRisk
                                            : entry - stop_distance * InpRewardRisk);
   const double volume = CalculateRiskVolume(order_type, entry, stop);
   if(volume <= 0.0)
   {
      Print("ALB|skip|invalid_volume");
      return false;
   }

   const bool sent = buy
      ? g_trade.Buy(volume, _Symbol, 0.0, stop, target, "ALB")
      : g_trade.Sell(volume, _Symbol, 0.0, stop, target, "ALB");

   PrintFormat("ALB|entry|side=%s|volume=%.2f|request=%.3f|sl=%.3f|tp=%.3f|atr=%.3f|spread=%.3f|retcode=%u|description=%s",
               buy ? "buy" : "sell", volume, entry, stop, target, atr,
               tick.ask - tick.bid, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return sent;
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) && !InpEnableTrading)
   {
      Print("ALB|disabled|live trading requires explicit approval");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpAsiaStartHour < 0 || InpAsiaStartHour > 23 ||
      InpAsiaEndHour <= InpAsiaStartHour || InpAsiaEndHour > 23 ||
      InpTradeStartHour < InpAsiaEndHour || InpTradeEndHour <= InpTradeStartHour ||
      InpForceExitHour < InpTradeEndHour || InpForceExitHour > 23 ||
      InpAtrPeriod < 2 || InpTrendEmaPeriod < 2 ||
      InpStopAtrMultiple <= 0.0 || InpRewardRisk <= 0.0 ||
      InpRiskPercent <= 0.0 || InpMaxSpreadPrice <= 0.0 || InpRetestTolerance < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   g_atr_handle = iATR(_Symbol, InpSignalTimeframe, InpAtrPeriod);
   if(g_atr_handle == INVALID_HANDLE)
      return INIT_FAILED;
   g_trend_handle = iMA(_Symbol, InpTrendTimeframe, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(g_trend_handle == INVALID_HANDLE)
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   PrintFormat("ALB|init|symbol=%s|timeframe=%s|server=%s|tester=%d",
               _Symbol, EnumToString(InpSignalTimeframe), AccountInfoString(ACCOUNT_SERVER),
               (int)MQLInfoInteger(MQL_TESTER));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   if(g_trend_handle != INVALID_HANDLE)
      IndicatorRelease(g_trend_handle);
   PrintFormat("ALB|deinit|reason=%d", reason);
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   MqlDateTime now;
   TimeToStruct(tick.time, now);
   const int day_key = DayKey(tick.time);
   if(day_key != g_trading_day_key)
   {
      g_trading_day_key = day_key;
      g_traded_today = false;
      g_range_ready = false;
      g_armed_direction = 0;
      g_armed_bar_time = 0;
   }

   if(now.hour >= InpForceExitHour)
   {
      if(HasStrategyPosition())
         CloseStrategyPositions();
      return;
   }

   const datetime current_bar = iTime(_Symbol, InpSignalTimeframe, 0);
   if(current_bar <= 0 || current_bar == g_last_bar_time)
      return;
   g_last_bar_time = current_bar;

   if(!g_range_ready && now.hour >= InpAsiaEndHour)
      CalculateAsiaRange(tick.time);
   if(!g_range_ready || g_traded_today || HasStrategyPosition() ||
      now.hour < InpTradeStartHour || now.hour >= InpTradeEndHour)
      return;

   if(tick.ask - tick.bid > InpMaxSpreadPrice)
   {
      PrintFormat("ALB|skip|spread=%.3f|max=%.3f", tick.ask - tick.bid, InpMaxSpreadPrice);
      return;
   }

   MqlRates signal_bars[2];
   double atr_values[1];
   if(CopyRates(_Symbol, InpSignalTimeframe, 1, 2, signal_bars) != 2 ||
      CopyBuffer(g_atr_handle, 0, 1, 1, atr_values) != 1)
      return;

   bool allow_buy = true;
   bool allow_sell = true;
   if(InpUseTrendFilter)
   {
      double trend_close[1];
      double trend_ema[1];
      if(CopyClose(_Symbol, InpTrendTimeframe, 1, 1, trend_close) != 1 ||
         CopyBuffer(g_trend_handle, 0, 1, 1, trend_ema) != 1)
         return;
      allow_buy = trend_close[0] > trend_ema[0];
      allow_sell = trend_close[0] < trend_ema[0];
   }

   const double previous_close = signal_bars[0].close;
   const MqlRates signal_bar = signal_bars[1];
   const double signal_close = signal_bar.close;
   bool attempted = false;
   const bool buy_breakout = allow_buy &&
      signal_close > g_asia_high + InpBreakoutBuffer &&
      previous_close <= g_asia_high + InpBreakoutBuffer;
   const bool sell_breakout = allow_sell &&
      signal_close < g_asia_low - InpBreakoutBuffer &&
      previous_close >= g_asia_low - InpBreakoutBuffer;

   if(!InpRequireRetest)
   {
      if(buy_breakout)
         attempted = OpenPosition(ORDER_TYPE_BUY, tick, atr_values[0]);
      else if(sell_breakout)
         attempted = OpenPosition(ORDER_TYPE_SELL, tick, atr_values[0]);
   }
   else
   {
      if(g_armed_direction == 0)
      {
         if(buy_breakout)
         {
            g_armed_direction = 1;
            g_armed_bar_time = signal_bar.time;
            PrintFormat("ALB|armed|side=buy|bar=%s|level=%.3f",
                        TimeToString(signal_bar.time), g_asia_high);
         }
         else if(sell_breakout)
         {
            g_armed_direction = -1;
            g_armed_bar_time = signal_bar.time;
            PrintFormat("ALB|armed|side=sell|bar=%s|level=%.3f",
                        TimeToString(signal_bar.time), g_asia_low);
         }
      }
      else if(signal_bar.time > g_armed_bar_time)
      {
         const bool buy_retest = g_armed_direction == 1 && allow_buy &&
            signal_bar.low <= g_asia_high + InpRetestTolerance &&
            signal_close > g_asia_high;
         const bool sell_retest = g_armed_direction == -1 && allow_sell &&
            signal_bar.high >= g_asia_low - InpRetestTolerance &&
            signal_close < g_asia_low;

         if(buy_retest)
            attempted = OpenPosition(ORDER_TYPE_BUY, tick, atr_values[0]);
         else if(sell_retest)
            attempted = OpenPosition(ORDER_TYPE_SELL, tick, atr_values[0]);
      }
   }

   if(attempted)
   {
      g_traded_today = true;
      g_armed_direction = 0;
   }
}

double OnTester()
{
   const double initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double net_profit = TesterStatistics(STAT_PROFIT);
   const double final_balance = initial_deposit + net_profit;
   const double profit_factor = TesterStatistics(STAT_PROFIT_FACTOR);
   const double expected_payoff = TesterStatistics(STAT_EXPECTED_PAYOFF);
   const double balance_drawdown_percent = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   const double equity_drawdown_percent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   const long trades = (long)TesterStatistics(STAT_TRADES);
   const long deals = (long)TesterStatistics(STAT_DEALS);

   PrintFormat("ALB|tester_summary|initial=%.2f|balance=%.2f|profit=%.2f|profit_factor=%.6f|expected_payoff=%.6f|balance_dd_pct=%.6f|equity_dd_pct=%.6f|trades=%I64d|deals=%I64d",
               initial_deposit, final_balance, net_profit, profit_factor, expected_payoff,
               balance_drawdown_percent, equity_drawdown_percent, trades, deals);
   return net_profit;
}
