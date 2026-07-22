#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input ulong InpMagic = 26071901;
input double InpVolume = 0.01;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_D1;
input int InpTrendEmaPeriod = 200;
input int InpEntryLookback = 100;
input int InpExitLookback = 50;
input int InpAtrPeriod = 14;
input double InpStopAtrMultiple = 3.0;
input double InpMaxSpreadPrice = 1.00;
input int InpMaxDeviationPoints = 100;
input string InpOutputName = "LongTrendBreakout";

CTrade g_trade;
int g_ema_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;

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

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) || InpVolume <= 0.0 || InpTrendEmaPeriod < 2 ||
      InpEntryLookback < 2 || InpExitLookback < 2 || InpAtrPeriod < 2 ||
      InpStopAtrMultiple <= 0.0 || InpMaxSpreadPrice <= 0.0)
      return INIT_PARAMETERS_INCORRECT;

   g_ema_handle = iMA(_Symbol, InpSignalTimeframe, InpTrendEmaPeriod, 0,
                      MODE_EMA, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, InpSignalTimeframe, InpAtrPeriod);
   if(g_ema_handle == INVALID_HANDLE || g_atr_handle == INVALID_HANDLE)
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   PrintFormat("LTB|init|symbol=%s|build=%d|server=%s", _Symbol,
               (int)TerminalInfoInteger(TERMINAL_BUILD),
               AccountInfoString(ACCOUNT_SERVER));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   PrintFormat("LTB|deinit|reason=%d", reason);
}

void OnTick()
{
   const datetime current_bar = iTime(_Symbol, InpSignalTimeframe, 0);
   if(current_bar <= 0 || current_bar == g_last_bar_time)
      return;
   g_last_bar_time = current_bar;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   const int required = MathMax(InpEntryLookback, InpExitLookback) + 1;
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, InpSignalTimeframe, 1, required, bars) != required)
      return;

   double ema[1];
   double atr[1];
   if(CopyBuffer(g_ema_handle, 0, 1, 1, ema) != 1 ||
      CopyBuffer(g_atr_handle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
      return;

   double entry_high = bars[1].high;
   for(int index = 2; index <= InpEntryLookback; index++)
      entry_high = MathMax(entry_high, bars[index].high);

   double exit_low = bars[1].low;
   for(int index = 2; index <= InpExitLookback; index++)
      exit_low = MathMin(exit_low, bars[index].low);

   const ulong ticket = PositionTicket();
   if(ticket != 0)
   {
      if(bars[0].close < ema[0] || bars[0].close < exit_low)
      {
         const bool closed = g_trade.PositionClose(ticket);
         PrintFormat("LTB|exit|close=%.3f|ema=%.3f|exit_low=%.3f|sent=%d|retcode=%u",
                     bars[0].close, ema[0], exit_low, (int)closed,
                     g_trade.ResultRetcode());
         return;
      }

      const double current_stop = PositionGetDouble(POSITION_SL);
      const double candidate = NormalizePrice(bars[0].close - atr[0] * InpStopAtrMultiple);
      if(candidate > current_stop && candidate < tick.bid)
      {
         const bool modified = g_trade.PositionModify(ticket, candidate, 0.0);
         PrintFormat("LTB|trail|sl=%.3f|sent=%d|retcode=%u", candidate,
                     (int)modified, g_trade.ResultRetcode());
      }
      return;
   }

   if(bars[0].close <= ema[0] || bars[0].close <= entry_high ||
      tick.ask - tick.bid > InpMaxSpreadPrice)
      return;

   const double stop = NormalizePrice(tick.ask - atr[0] * InpStopAtrMultiple);
   const bool opened = g_trade.Buy(InpVolume, _Symbol, 0.0, stop, 0.0, "LTB");
   PrintFormat("LTB|entry|volume=%.2f|close=%.3f|ema=%.3f|entry_high=%.3f|sl=%.3f|spread=%.3f|sent=%d|retcode=%u",
               InpVolume, bars[0].close, ema[0], entry_high, stop,
               tick.ask - tick.bid, (int)opened, g_trade.ResultRetcode());
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
   FolderCreate("GoldResearch\\Published", FILE_COMMON);
   const int curve_file = FileOpen("GoldResearch\\Published\\" + InpOutputName + "-equity.csv",
                                   FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(curve_file != INVALID_HANDLE)
   {
      FileWrite(curve_file, "time_msc", "balance");
      double running_balance = initial;
      FileWrite(curve_file, 0, DoubleToString(running_balance, 2));
      HistorySelect(0, TimeCurrent());
      for(int index = 0; index < HistoryDealsTotal(); index++)
      {
         const ulong ticket = HistoryDealGetTicket(index);
         if(ticket == 0 || HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
            (ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic)
            continue;
         const long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
            continue;
         running_balance += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP);
         FileWrite(curve_file,
                   HistoryDealGetInteger(ticket, DEAL_TIME_MSC),
                   DoubleToString(running_balance, 2));
      }
      FileClose(curve_file);
   }
   PrintFormat("LTB|tester_summary|initial=%.2f|balance=%.2f|profit=%.2f|profit_factor=%.6f|expected_payoff=%.6f|balance_dd_pct=%.6f|equity_dd_pct=%.6f|trades=%I64d|deals=%I64d",
               initial, initial + profit, profit, profit_factor, payoff,
               balance_dd, equity_dd, trades, deals);
   return profit;
}
