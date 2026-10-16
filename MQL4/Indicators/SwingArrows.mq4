//+------------------------------------------------------------------+
//| SwingArrows.mq4                                                  |
//| Demo "signal" indicator: arrows on swing lows (bullish) and      |
//| swing highs (bearish), like fractals with configurable strength. |
//| The arrow is drawn on the pivot bar, which is already InpRight   |
//| bars old when the pivot is confirmed: it backdraws on purpose,   |
//| because many real signal indicators do the same.                 |
//| Buffer 0 = swing low (bullish), buffer 1 = swing high (bearish). |
//+------------------------------------------------------------------+
#property strict
#property description "Demo signal: swing low/high arrows, drawn back InpRight bars"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 clrLimeGreen
#property indicator_color2 clrTomato
#property indicator_width1 1
#property indicator_width2 1

#include <SwingPivot.mqh>

input int InpLeft  = 3;   // Left strength: older bars beyond the pivot
input int InpRight = 3;   // Right strength: arrow appears this many bars late

double g_swingLow[];
double g_swingHigh[];

int OnInit()
  {
   if(InpLeft < 1 || InpRight < 1)
     {
      Print("SwingArrows: InpLeft and InpRight must be at least 1");
      return(INIT_FAILED);
     }

   SetIndexBuffer(0, g_swingLow);
   SetIndexBuffer(1, g_swingHigh);
   // Series order so index 0 is the forming bar, matching the shift used by iCustom.
   ArraySetAsSeries(g_swingLow, true);
   ArraySetAsSeries(g_swingHigh, true);
   SetIndexStyle(0, DRAW_ARROW);
   SetIndexStyle(1, DRAW_ARROW);
   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   return(INIT_SUCCEEDED);
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
      g_swingLow[i]  = EMPTY_VALUE;
      g_swingHigh[i] = EMPTY_VALUE;
      // Offset from the wick so the arrow does not cover the candle.
      double gap = 0.3 * (high[i] - low[i]);
      if(SP_IsSwingLow(low, i, InpLeft, InpRight, rates_total))
         g_swingLow[i] = low[i] - gap;
      if(SP_IsSwingHigh(high, i, InpLeft, InpRight, rates_total))
         g_swingHigh[i] = high[i] + gap;
     }
   return(rates_total);
  }
