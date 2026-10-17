//+------------------------------------------------------------------+
//| ConfluenceCore.mqh                                               |
//| Confluence matching and "already alerted" memory.                |
//| No terminal calls (no Time[], no iCustom, no SendMail), so the   |
//| whole decision can be unit tested from a script with built bars. |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_CORE_MQH
#define CONFLUENCE_CORE_MQH

// While one bar stays inside a lookback window of L bars, at most 2L-1
// distinct bars can pass through that window. 256 slots therefore keep every
// bar remembered for as long as it can still be found, for L up to 100.
#define CC_MEMORY_SIZE  256
#define CC_MAX_LOOKBACK 100

enum ENUM_CC_DIVERGENCE
  {
   CC_DIV_NONE = 0,
   CC_DIV_REGULAR_BULL,
   CC_DIV_REGULAR_BEAR,
   CC_DIV_HIDDEN_BULL,
   CC_DIV_HIDDEN_BEAR
  };

// One closed bar of the lookback window, already reduced to flags.
struct CCBar
  {
   datetime          time;
   int               shift;
   bool              signalBuy;
   bool              signalSell;
   bool              regularBull;
   bool              regularBear;
   bool              hiddenBull;
   bool              hiddenBear;
  };

struct CCOptions
  {
   bool              matchDirection;   // bullish signal only with bullish divergence, bearish with bearish
   bool              useRegular;
   bool              useHidden;
  };

struct CCMatch
  {
   datetime          time;
   int               shift;
   int               signalDir;        // +1 buy, -1 sell
   ENUM_CC_DIVERGENCE divergence;
   bool              isNew;            // true only the first time this bar time is found
  };

//+------------------------------------------------------------------+
//| Some indicators clear a buffer with 0 instead of EMPTY_VALUE, so |
//| both mean "no arrow". Anything else is a signal.                 |
//+------------------------------------------------------------------+
bool CC_IsSignal(const double value)
  {
   return(value != EMPTY_VALUE && value != 0.0);
  }

//+------------------------------------------------------------------+
//| Fixed-size ring buffer of bar times that already alerted.        |
//| Keyed by bar open time, not by shift: the shift of a bar grows   |
//| by one on every new bar, its open time never changes.            |
//+------------------------------------------------------------------+
class CCMemory
  {
private:
   datetime          m_slots[CC_MEMORY_SIZE];
   int               m_next;
   int               m_count;

public:
   void              Reset(void) { m_next = 0; m_count = 0; }
                     CCMemory(void) { Reset(); }
   int               Capacity(void) const { return(CC_MEMORY_SIZE); }
   int               Count(void) const { return(m_count); }

   bool              Seen(const datetime barTime) const
     {
      for(int i = 0; i < m_count; i++)
         if(m_slots[i] == barTime)
            return(true);
      return(false);
     }

   // Remembering a time twice must not use a second slot, otherwise
   // repeated scans of the same window would push older entries out early.
   void              Remember(const datetime barTime)
     {
      if(Seen(barTime))
         return;
      m_slots[m_next] = barTime;
      m_next = (m_next + 1) % CC_MEMORY_SIZE;
      if(m_count < CC_MEMORY_SIZE)
         m_count++;
     }
  };

//+------------------------------------------------------------------+
//| Divergence kind that pairs with a signal direction on this bar.  |
//| The agreeing direction is tried first, so with matching off a    |
//| bar holding both kinds still reports the agreeing one.           |
//+------------------------------------------------------------------+
ENUM_CC_DIVERGENCE CC_PickDivergence(const CCBar &bar, const CCOptions &opt, const int signalDir)
  {
   bool bullishSignal = (signalDir > 0);

   if(bullishSignal)
     {
      if(opt.useRegular && bar.regularBull) return(CC_DIV_REGULAR_BULL);
      if(opt.useHidden && bar.hiddenBull)   return(CC_DIV_HIDDEN_BULL);
     }
   else
     {
      if(opt.useRegular && bar.regularBear) return(CC_DIV_REGULAR_BEAR);
      if(opt.useHidden && bar.hiddenBear)   return(CC_DIV_HIDDEN_BEAR);
     }

   if(opt.matchDirection)
      return(CC_DIV_NONE);

   if(bullishSignal)
     {
      if(opt.useRegular && bar.regularBear) return(CC_DIV_REGULAR_BEAR);
      if(opt.useHidden && bar.hiddenBear)   return(CC_DIV_HIDDEN_BEAR);
     }
   else
     {
      if(opt.useRegular && bar.regularBull) return(CC_DIV_REGULAR_BULL);
      if(opt.useHidden && bar.hiddenBull)   return(CC_DIV_HIDDEN_BULL);
     }
   return(CC_DIV_NONE);
  }

//+------------------------------------------------------------------+
//| True when signal and divergence agree on this bar.               |
//+------------------------------------------------------------------+
bool CC_MatchBar(const CCBar &bar, const CCOptions &opt, int &signalDir, ENUM_CC_DIVERGENCE &divergence)
  {
   signalDir = 0;
   divergence = CC_DIV_NONE;

   if(bar.signalBuy)
     {
      divergence = CC_PickDivergence(bar, opt, 1);
      if(divergence != CC_DIV_NONE)
        {
         signalDir = 1;
         return(true);
        }
     }
   if(bar.signalSell)
     {
      divergence = CC_PickDivergence(bar, opt, -1);
      if(divergence != CC_DIV_NONE)
        {
         signalDir = -1;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Scans the window and returns every confluence bar in it.         |
//| bars[] is newest first: bars[0] is shift 1, the last closed bar. |
//| Every match is returned so the caller can redraw its markers;    |
//| only matches with isNew == true should alert. New matches are    |
//| remembered here, so scanning the same window again (another tick |
//| of the same bar) or the shifted window (next bar) returns them   |
//| with isNew == false.                                             |
//+------------------------------------------------------------------+
int CC_Scan(const CCBar &bars[], const int count, const CCOptions &opt, CCMemory &memory, CCMatch &matches[])
  {
   ArrayResize(matches, 0);
   int total = (count < ArraySize(bars)) ? count : ArraySize(bars);
   int found = 0;

   // Oldest first, so several new matches are reported in chart order.
   for(int k = total - 1; k >= 0; k--)
     {
      int dir = 0;
      ENUM_CC_DIVERGENCE div = CC_DIV_NONE;
      if(!CC_MatchBar(bars[k], opt, dir, div))
         continue;

      ArrayResize(matches, found + 1);
      matches[found].time       = bars[k].time;
      matches[found].shift      = bars[k].shift;
      matches[found].signalDir  = dir;
      matches[found].divergence = div;
      matches[found].isNew      = !memory.Seen(bars[k].time);
      if(matches[found].isNew)
         memory.Remember(bars[k].time);
      found++;
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| History pass for bars older than the live window, run when the   |
//| indicator's buffers are drawn from scratch. Same matching as     |
//| CC_Scan, but there is no CCMemory parameter: nothing is recorded,|
//| so the live "already alerted" memory and its priming cannot be   |
//| changed, and every match has isNew == false (history never       |
//| alerts). Only bars with                                          |
//|   liveLookback < shift <= liveLookback + historyBars             |
//| are returned. Bars inside the live window are left to CC_Scan,   |
//| so no bar is marked by both passes.                              |
//| bars[] is newest first, as for CC_Scan; matches are oldest first.|
//+------------------------------------------------------------------+
int CC_ScanHistory(const CCBar &bars[], const int count, const CCOptions &opt,
                   const int liveLookback, const int historyBars, CCMatch &matches[])
  {
   ArrayResize(matches, 0);
   int total = (count < ArraySize(bars)) ? count : ArraySize(bars);
   int found = 0;

   for(int k = total - 1; k >= 0; k--)
     {
      // Subtraction, not liveLookback + historyBars, so a huge cap cannot overflow.
      if(bars[k].shift <= liveLookback || bars[k].shift - liveLookback > historyBars)
         continue;
      int dir = 0;
      ENUM_CC_DIVERGENCE div = CC_DIV_NONE;
      if(!CC_MatchBar(bars[k], opt, dir, div))
         continue;

      ArrayResize(matches, found + 1);
      matches[found].time       = bars[k].time;
      matches[found].shift      = bars[k].shift;
      matches[found].signalDir  = dir;
      matches[found].divergence = div;
      matches[found].isNew      = false;
      found++;
     }
   return(found);
  }

string CC_SignalName(const int signalDir)
  {
   return(signalDir > 0 ? "BUY" : "SELL");
  }

string CC_DivergenceName(const ENUM_CC_DIVERGENCE divergence)
  {
   switch(divergence)
     {
      case CC_DIV_REGULAR_BULL: return("regular bullish");
      case CC_DIV_REGULAR_BEAR: return("regular bearish");
      case CC_DIV_HIDDEN_BULL:  return("hidden bullish");
      case CC_DIV_HIDDEN_BEAR:  return("hidden bearish");
      default:                  return("none");
     }
   return("none");
  }

#endif
