#property copyright "MT5 Gold Research"
#property version   "1.00"
#property strict

input string InpExpectedSymbol = "XAUUSDm";

long g_tick_count = 0;
long g_spread_samples = 0;
double g_spread_sum = 0.0;
double g_spread_max = 0.0;
long g_first_tick_msc = 0;
long g_last_tick_msc = 0;

void PrintSymbolProperty(const string name, const ENUM_SYMBOL_INFO_INTEGER property)
{
   long value = 0;
   if(SymbolInfoInteger(_Symbol, property, value))
      PrintFormat("PROBE|symbol_int|%s|%I64d", name, value);
   else
      PrintFormat("PROBE|error|symbol_int|%s|%d", name, GetLastError());
}

void PrintSymbolProperty(const string name, const ENUM_SYMBOL_INFO_DOUBLE property)
{
   double value = 0.0;
   if(SymbolInfoDouble(_Symbol, property, value))
      PrintFormat("PROBE|symbol_double|%s|%.10f", name, value);
   else
      PrintFormat("PROBE|error|symbol_double|%s|%d", name, GetLastError());
}

int OnInit()
{
   PrintFormat("PROBE|environment|program=%s|tester=%d|optimization=%d|visual=%d",
               MQLInfoString(MQL_PROGRAM_NAME),
               (int)MQLInfoInteger(MQL_TESTER),
               (int)MQLInfoInteger(MQL_OPTIMIZATION),
               (int)MQLInfoInteger(MQL_VISUAL_MODE));
   PrintFormat("PROBE|account|login=%I64d|server=%s|company=%s|mode=%d|currency=%s|leverage=%d",
               AccountInfoInteger(ACCOUNT_LOGIN),
               AccountInfoString(ACCOUNT_SERVER),
               AccountInfoString(ACCOUNT_COMPANY),
               (int)AccountInfoInteger(ACCOUNT_MARGIN_MODE),
               AccountInfoString(ACCOUNT_CURRENCY),
               (int)AccountInfoInteger(ACCOUNT_LEVERAGE));
   PrintFormat("PROBE|symbol|actual=%s|expected=%s|match=%d",
               _Symbol, InpExpectedSymbol, (int)(_Symbol == InpExpectedSymbol));

   PrintSymbolProperty("digits", SYMBOL_DIGITS);
   PrintSymbolProperty("trade_mode", SYMBOL_TRADE_MODE);
   PrintSymbolProperty("calc_mode", SYMBOL_TRADE_CALC_MODE);
   PrintSymbolProperty("filling_mode", SYMBOL_FILLING_MODE);
   PrintSymbolProperty("stops_level", SYMBOL_TRADE_STOPS_LEVEL);
   PrintSymbolProperty("freeze_level", SYMBOL_TRADE_FREEZE_LEVEL);
   PrintSymbolProperty("point", SYMBOL_POINT);
   PrintSymbolProperty("tick_size", SYMBOL_TRADE_TICK_SIZE);
   PrintSymbolProperty("tick_value", SYMBOL_TRADE_TICK_VALUE);
   PrintSymbolProperty("tick_value_profit", SYMBOL_TRADE_TICK_VALUE_PROFIT);
   PrintSymbolProperty("tick_value_loss", SYMBOL_TRADE_TICK_VALUE_LOSS);
   PrintSymbolProperty("contract_size", SYMBOL_TRADE_CONTRACT_SIZE);
   PrintSymbolProperty("volume_min", SYMBOL_VOLUME_MIN);
   PrintSymbolProperty("volume_max", SYMBOL_VOLUME_MAX);
   PrintSymbolProperty("volume_step", SYMBOL_VOLUME_STEP);
   PrintSymbolProperty("swap_long", SYMBOL_SWAP_LONG);
   PrintSymbolProperty("swap_short", SYMBOL_SWAP_SHORT);

   if(_Symbol != InpExpectedSymbol)
   {
      Print("PROBE|fatal|unexpected_symbol");
      return INIT_PARAMETERS_INCORRECT;
   }

   return INIT_SUCCEEDED;
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   if(g_first_tick_msc == 0)
      g_first_tick_msc = tick.time_msc;
   g_last_tick_msc = tick.time_msc;
   g_tick_count++;

   const double spread = tick.ask - tick.bid;
   if(spread >= 0.0)
   {
      g_spread_samples++;
      g_spread_sum += spread;
      if(spread > g_spread_max)
         g_spread_max = spread;
   }
}

void OnDeinit(const int reason)
{
   const double average_spread =
      g_spread_samples > 0 ? g_spread_sum / (double)g_spread_samples : 0.0;
   PrintFormat("PROBE|summary|reason=%d|ticks=%I64d|first_msc=%I64d|last_msc=%I64d|spread_avg=%.10f|spread_max=%.10f",
               reason, g_tick_count, g_first_tick_msc, g_last_tick_msc,
               average_spread, g_spread_max);
}

double OnTester()
{
   return (double)g_tick_count;
}
