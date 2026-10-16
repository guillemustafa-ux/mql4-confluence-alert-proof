//+------------------------------------------------------------------+
//| RsiDivergence.mq4                                                |
//| Demo divergence indicator. Pivots are price swings found with    |
//| the same rule and strengths as SwingArrows (SwingPivot.mqh); RSI |
//| is read on the two pivot bars and compared:                      |
//|   regular bullish: price lower low,   RSI higher low             |
//|   hidden bullish:  price higher low,  RSI lower low              |
//|   regular bearish: price higher high, RSI lower high             |
//|   hidden bearish:  price lower high,  RSI higher high            |
//| The arrow goes on the newer pivot bar, InpRight bars after it    |
//| formed (backdraw), which is the case ConfluenceAlert must catch. |
//| Buffers: 0 regular bull, 1 regular bear, 2 hidden bull,          |
//| 3 hidden bear.                                                   |
//+------------------------------------------------------------------+
#property strict
#property description "Demo divergence: RSI regular/hidden divergence on price pivots"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrDeepSkyBlue
#property indicator_color2 clrMagenta
#property indicator_color3 clrDeepSkyBlue
#property indicator_color4 clrMagenta
#property indicator_width1 1
#property indicator_width2 1
#property indicator_width3 1
#property indicator_width4 1

#include <SwingPivot.mqh>

input int InpRsiPeriod = 14;  // RSI period (close price)
input int InpLeft      = 3;   // Left strength (same as SwingArrows)
input int InpRight     = 3;   // Right strength: arrow appears this many bars late
input int InpMaxGap    = 60;  // Max bars back to the previous pivot

double g_regularBull[];
double g_regularBear[];
double g_hiddenBull[];
double g_hiddenBear[];

int OnInit()
  {
   if(InpRsiPeriod < 2 || InpLeft < 1 || InpRight < 1 || InpMaxGap < 1)
     {
      Print("RsiDivergence: invalid inputs");
      return(INIT_FAILED);
     }

   SetIndexBuffer(0, g_regularBull);
   SetIndexBuffer(1, g_regularBear);
   SetIndexBuffer(2, g_hiddenBull);
   SetIndexBuffer(3, g_hiddenBear);
   ArraySetAsSeries(g_regularBull, true);
   ArraySetAsSeries(g_regularBear, true);
   ArraySetAsSeries(g_hiddenBull, true);
   ArraySetAsSeries(g_hiddenBear, true);
   for(int b = 0; b < 4; b++)
     {
      SetIndexStyle(b, DRAW_ARROW);
      SetIndexEmptyValue(b, EMPTY_VALUE);
     }
   // Filled arrows for regular, outlined for hidden.
   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);
   SetIndexArrow(2, 241);
   SetIndexArrow(3, 242);
   return(INIT_SUCCEEDED);
  }

int PreviousSwingLow(const double &low[], const int from, const int total)
  {
   for(int j = from + 1; j <= from + InpMaxGap && j < total; j++)
      if(SP_IsSwingLow(low, j, InpLeft, InpRight, total))
         return(j);
   return(-1);
  }

int PreviousSwingHigh(const double &high[], const int from, const int total)
  {
   for(int j = from + 1; j <= from + InpMaxGap && j < total; j++)
      if(SP_IsSwingHigh(high, j, InpLeft, InpRight, total))
         return(j);
   return(-1);
  }

double Rsi(const int shift)
  {
   return(iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, shift));
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int start = SP_FirstBarToRecompute(rates_total, prev_calculated, InpRight);
   for(int i = start; i >= 0; i--)
     {
      g_regularBull[i] = EMPTY_VALUE;
      g_regularBear[i] = EMPTY_VALUE;
      g_hiddenBull[i]  = EMPTY_VALUE;
      g_hiddenBear[i]  = EMPTY_VALUE;
      // Further from the wick than SwingArrows so both arrows stay visible.
      double gap = 0.8 * (high[i] - low[i]);

      if(SP_IsSwingLow(low, i, InpLeft, InpRight, rates_total))
        {
         int j = PreviousSwingLow(low, i, rates_total);
         if(j > 0)
           {
            double rsiNow = Rsi(i);
            double rsiPrev = Rsi(j);
            if(low[i] < low[j] && rsiNow > rsiPrev)
               g_regularBull[i] = low[i] - gap;
            else if(low[i] > low[j] && rsiNow < rsiPrev)
               g_hiddenBull[i] = low[i] - gap;
           }
        }

      if(SP_IsSwingHigh(high, i, InpLeft, InpRight, rates_total))
        {
         int j = PreviousSwingHigh(high, i, rates_total);
         if(j > 0)
           {
            double rsiNow = Rsi(i);
            double rsiPrev = Rsi(j);
            if(high[i] > high[j] && rsiNow < rsiPrev)
               g_regularBear[i] = high[i] + gap;
            else if(high[i] < high[j] && rsiNow > rsiPrev)
               g_hiddenBear[i] = high[i] + gap;
           }
        }
     }
   return(rates_total);
  }
