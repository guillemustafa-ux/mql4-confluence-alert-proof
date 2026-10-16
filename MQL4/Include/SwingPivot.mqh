//+------------------------------------------------------------------+
//| SwingPivot.mqh                                                   |
//| Swing high/low test shared by the two demo indicators, so that   |
//| with equal strengths both find exactly the same pivot bars.      |
//| Arrays must be series-indexed: index 0 is the forming bar,       |
//| i + j is older than i.                                           |
//+------------------------------------------------------------------+
#ifndef SWING_PIVOT_MQH
#define SWING_PIVOT_MQH

// Strict against the older side and non-strict against the newer side, so a
// flat bottom made of equal lows yields one pivot (the oldest bar of it).
// The newest bar used, i - right, must be shift 1 or older: shift 0 is still
// forming, and a pivot confirmed on it could vanish before the bar closes.
bool SP_IsSwingLow(const double &low[], const int i, const int left, const int right, const int total)
  {
   if(i - right < 1 || i + left > total - 1)
      return(false);
   for(int j = 1; j <= left; j++)
      if(low[i + j] <= low[i])
         return(false);
   for(int j = 1; j <= right; j++)
      if(low[i - j] < low[i])
         return(false);
   return(true);
  }

bool SP_IsSwingHigh(const double &high[], const int i, const int left, const int right, const int total)
  {
   if(i - right < 1 || i + left > total - 1)
      return(false);
   for(int j = 1; j <= left; j++)
      if(high[i + j] >= high[i])
         return(false);
   for(int j = 1; j <= right; j++)
      if(high[i - j] > high[i])
         return(false);
   return(true);
  }

// First bar to recompute on this call. A pivot at bar i is only confirmed
// once bar i - right has closed, so each new bar can create a pivot at
// shift right + 1, and everything newer must be cleared every tick.
int SP_FirstBarToRecompute(const int rates_total, const int prev_calculated, const int right)
  {
   if(prev_calculated <= 0)
      return(rates_total - 1);
   int start = rates_total - prev_calculated + right + 1;
   return(start < rates_total - 1 ? start : rates_total - 1);
  }

#endif
