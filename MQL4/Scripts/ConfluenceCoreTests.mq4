//+------------------------------------------------------------------+
//| ConfluenceCoreTests.mq4                                          |
//| Unit tests of ConfluenceCore.mqh. Run it on any chart; results   |
//| go to the Experts tab: one "PASS name" or "FAIL name: detail"    |
//| line per test, then "N passed, M failed".                        |
//+------------------------------------------------------------------+
#property strict
#property description "Unit tests of ConfluenceCore.mqh (results in the Experts tab)"

#include <ConfluenceCore.mqh>

#define BAR_SECONDS 3600

int g_passed = 0;
int g_failed = 0;

// An empty detail means the test passed.
void Report(const string name, const string detail)
  {
   if(detail == "")
     {
      g_passed++;
      Print("PASS ", name);
     }
   else
     {
      g_failed++;
      Print("FAIL ", name, ": ", detail);
     }
  }

void DefaultOptions(CCOptions &opt)
  {
   opt.matchDirection = true;
   opt.useRegular     = true;
   opt.useHidden      = true;
  }

void ClearBar(CCBar &bar, const datetime barTime, const int shift)
  {
   bar.time        = barTime;
   bar.shift       = shift;
   bar.signalBuy   = false;
   bar.signalSell  = false;
   bar.regularBull = false;
   bar.regularBear = false;
   bar.hiddenBull  = false;
   bar.hiddenBear  = false;
  }

// Window of `count` closed bars, newest first, the way the indicator builds
// it: bars[k] is shift k+1 and is BAR_SECONDS older than bars[k-1].
void EmptyWindow(CCBar &bars[], const int count, const datetime lastClosedTime)
  {
   ArrayResize(bars, count);
   for(int k = 0; k < count; k++)
      ClearBar(bars[k], (datetime)((long)lastClosedTime - (long)k * BAR_SECONDS), k + 1);
  }

int FindShift(const CCBar &bars[], const datetime barTime)
  {
   for(int k = 0; k < ArraySize(bars); k++)
      if(bars[k].time == barTime)
         return(k);
   return(-1);
  }

int CountNew(const CCMatch &matches[], const int found)
  {
   int fresh = 0;
   for(int m = 0; m < found; m++)
      if(matches[m].isNew)
         fresh++;
   return(fresh);
  }

//--- (a) Many ticks of the same bar: the window does not change between
//--- ticks, so the scan sees the same confluence each time.
string TestSameBarAlertsOnceAcrossTicks()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   datetime t1 = D'2026.01.05 10:00';

   EmptyWindow(bars, 5, t1);
   bars[0].signalBuy = true;
   bars[0].regularBull = true;

   int found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 1 || CountNew(matches, found) != 1)
      return("first scan: found " + IntegerToString(found) + ", new " + IntegerToString(CountNew(matches, found)));

   for(int tick = 0; tick < 50; tick++)
     {
      found = CC_Scan(bars, 5, opt, memory, matches);
      if(CountNew(matches, found) != 0)
         return("tick " + IntegerToString(tick) + " reported a new match again");
     }
   return("");
  }

//--- (b) Only one of the two indicators marks the bar.
string TestSingleIndicatorDoesNotAlert()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 5, D'2026.01.05 10:00');
   bars[0].signalBuy = true;      // signal without divergence
   bars[2].regularBull = true;    // divergence without signal, on another bar

   int found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 0)
      return("found " + IntegerToString(found) + " matches, expected 0");
   return("");
  }

//--- (c) The divergence arrow is drawn back on the pivot bar, which is
//--- already at shift 3 when it appears. Next bar it is at shift 4.
string TestBackdrawnAlertsOnceThenNotAgain()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   datetime pivot = D'2026.01.05 08:00';
   datetime closed = D'2026.01.05 10:00';    // pivot is at shift 3

   // Bar 1: the pivot bar exists, no arrows yet.
   EmptyWindow(bars, 10, closed);
   int found = CC_Scan(bars, 10, opt, memory, matches);
   if(found != 0)
      return("before backdraw: found " + IntegerToString(found));

   // Same window, the arrows have just been drawn back onto shift 3.
   int k = FindShift(bars, pivot);
   if(k != 2)
      return("test setup: pivot at index " + IntegerToString(k));
   bars[k].signalSell = true;
   bars[k].hiddenBear = true;
   found = CC_Scan(bars, 10, opt, memory, matches);
   if(found != 1 || !matches[0].isNew || matches[0].shift != 3)
      return("backdrawn arrow at shift 3 not reported once as new");

   // Next bar: the same pivot is now at shift 4 and must not alert again.
   EmptyWindow(bars, 10, (datetime)(closed + BAR_SECONDS));
   k = FindShift(bars, pivot);
   if(k != 3)
      return("test setup: pivot at index " + IntegerToString(k) + " after new bar");
   bars[k].signalSell = true;
   bars[k].hiddenBear = true;
   found = CC_Scan(bars, 10, opt, memory, matches);
   if(found != 1)
      return("after new bar: found " + IntegerToString(found) + ", expected 1 (old match)");
   if(matches[0].isNew)
      return("after new bar: the shifted arrow (shift 4) was reported as new");
   return("");
  }

//--- (d) Bullish signal with bearish divergence.
string TestDirectionMatching()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 5, D'2026.01.05 10:00');
   bars[1].signalBuy = true;
   bars[1].regularBear = true;

   CCMemory memoryOn;
   opt.matchDirection = true;
   int found = CC_Scan(bars, 5, opt, memoryOn, matches);
   if(found != 0)
      return("matching on: found " + IntegerToString(found) + ", expected 0");

   CCMemory memoryOff;
   opt.matchDirection = false;
   found = CC_Scan(bars, 5, opt, memoryOff, matches);
   if(found != 1 || !matches[0].isNew)
      return("matching off: found " + IntegerToString(found) + ", expected 1 new");
   if(matches[0].signalDir != 1 || matches[0].divergence != CC_DIV_REGULAR_BEAR)
      return("matching off: wrong kind " + CC_SignalName(matches[0].signalDir) + " + " + CC_DivergenceName(matches[0].divergence));
   return("");
  }

//--- (e) After more than Capacity() entries, the most recent Capacity()
//--- are still known and only the oldest ones are forgotten.
string TestMemoryRingKeepsMostRecent()
  {
   CCMemory memory;
   int cap = memory.Capacity();
   int extra = 44;
   // A bar can only be forgotten while it is in the window if fewer than
   // 2L-1 slots exist (see TestWorstCaseKeepsBarWhileInWindow).
   if(cap < 2 * CC_MAX_LOOKBACK - 1)
      return("capacity " + IntegerToString(cap) + " is below 2 * CC_MAX_LOOKBACK - 1 = " +
             IntegerToString(2 * CC_MAX_LOOKBACK - 1));
   datetime t0 = D'2026.01.01 00:00';

   for(int i = 0; i < cap + extra; i++)
      memory.Remember((datetime)(t0 + i * BAR_SECONDS));

   if(memory.Count() != cap)
      return("count " + IntegerToString(memory.Count()) + ", expected " + IntegerToString(cap));
   for(int i = extra; i < cap + extra; i++)
      if(!memory.Seen((datetime)(t0 + i * BAR_SECONDS)))
         return("forgot recent entry " + IntegerToString(i));
   for(int i = 0; i < extra; i++)
      if(memory.Seen((datetime)(t0 + i * BAR_SECONDS)))
         return("still holds overwritten entry " + IntegerToString(i));
   return("");
  }

//--- Remembering the same time again must not consume a slot.
string TestMemoryIgnoresDuplicates()
  {
   CCMemory memory;
   datetime t = D'2026.01.05 10:00';
   for(int i = 0; i < 1000; i++)
      memory.Remember(t);
   if(memory.Count() != 1)
      return("count " + IntegerToString(memory.Count()) + ", expected 1");
   return("");
  }

//--- (f) Both EMPTY_VALUE and 0 mean "no signal".
string TestEmptyValueAndZeroAreNoSignal()
  {
   if(CC_IsSignal(EMPTY_VALUE))
      return("EMPTY_VALUE counted as a signal");
   if(CC_IsSignal(0.0))
      return("0 counted as a signal");
   if(!CC_IsSignal(1.08765))
      return("a price value was not counted as a signal");
   return("");
  }

//--- Regular/hidden switches filter the divergence kinds.
string TestRegularHiddenSwitches()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 5, D'2026.01.05 10:00');
   bars[0].signalBuy = true;
   bars[0].hiddenBull = true;

   CCMemory memoryA;
   opt.useHidden = false;
   int found = CC_Scan(bars, 5, opt, memoryA, matches);
   if(found != 0)
      return("hidden off: found " + IntegerToString(found) + ", expected 0");

   CCMemory memoryB;
   opt.useHidden = true;
   opt.useRegular = false;
   found = CC_Scan(bars, 5, opt, memoryB, matches);
   if(found != 1 || matches[0].divergence != CC_DIV_HIDDEN_BULL)
      return("regular off, hidden on: expected 1 hidden bullish match");
   return("");
  }

//--- A confluence older than the lookback is not seen at all, which is why
//--- the lookback must cover the divergence indicator's backdraw.
string TestOutsideLookbackIsIgnored()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 8, D'2026.01.05 10:00');
   bars[6].signalBuy = true;     // shift 7
   bars[6].regularBull = true;

   int found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 0)
      return("lookback 5 found a match at shift 7");
   found = CC_Scan(bars, 8, opt, memory, matches);
   if(found != 1 || matches[0].shift != 7)
      return("lookback 8 did not find the match at shift 7");
   return("");
  }

//--- A marks the bar first; B draws its arrow back onto the same bar one
//--- evaluation later. The confluence exists only from evaluation 2 on.
string TestSignalThenDivergenceOnSameBar()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   datetime barTime = D'2026.01.05 10:00';

   // Evaluation 1: the bar has just closed (shift 1), only A marks it.
   EmptyWindow(bars, 5, barTime);
   bars[0].signalBuy = true;
   int found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 0)
      return("evaluation 1: found " + IntegerToString(found) + ", expected 0");

   // Evaluation 2: next bar, B's arrow now sits on the same bar (shift 2).
   EmptyWindow(bars, 5, (datetime)(barTime + BAR_SECONDS));
   bars[1].signalBuy = true;
   bars[1].regularBull = true;
   found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 1 || CountNew(matches, found) != 1 || matches[0].time != barTime)
      return("evaluation 2: expected exactly 1 new match on the same bar time");

   // Evaluation 3: one bar later, both arrows still there (shift 3).
   EmptyWindow(bars, 5, (datetime)(barTime + 2 * BAR_SECONDS));
   bars[2].signalBuy = true;
   bars[2].regularBull = true;
   found = CC_Scan(bars, 5, opt, memory, matches);
   if(found != 1 || CountNew(matches, found) != 0)
      return("evaluation 3: expected the match again, not as new");
   return("");
  }

//--- 600 consecutive bars, every bar a confluence, lookback 100, one bar per
//--- step. Each bar time must be reported as new exactly once while it moves
//--- through all 100 shifts. Only one new bar time enters per step, so this is
//--- a long-run check, not the worst case for the memory size.
string TestStreamOneNewPerBarTime()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   int lookback = 100;
   int steps = 600;
   datetime t0 = D'2026.01.05 00:00';

   // Bar times seen run from lookback-1 bars before t0 to steps-1 bars after it.
   int slots = steps + lookback - 1;
   int newCount[];
   ArrayResize(newCount, slots);
   for(int i = 0; i < slots; i++)
      newCount[i] = 0;

   for(int step = 0; step < steps; step++)
     {
      EmptyWindow(bars, lookback, (datetime)(t0 + step * BAR_SECONDS));
      for(int k = 0; k < lookback; k++)
        {
         bars[k].signalBuy = true;
         bars[k].regularBull = true;
        }
      int found = CC_Scan(bars, lookback, opt, memory, matches);
      if(found != lookback)
         return("step " + IntegerToString(step) + ": found " + IntegerToString(found));
      for(int m = 0; m < found; m++)
        {
         if(!matches[m].isNew)
            continue;
         int slot = (int)(((long)matches[m].time - (long)t0) / BAR_SECONDS) + lookback - 1;
         if(slot < 0 || slot >= slots)
            return("bar time outside the simulated range");
         newCount[slot]++;
        }
     }

   for(int i = 0; i < slots; i++)
      if(newCount[i] != 1)
         return("bar " + IntegerToString(i) + " reported as new " + IntegerToString(newCount[i]) + " times");
   return("");
  }

//--- Worst case for the memory size: X alerts at shift 1, then on every step
//--- until X sits at the last shift of the window, both the newest bar and the
//--- oldest bar of the window get a confluence. That pushes 2L-3 other bar
//--- times (197 for L = 100) into the memory while X can still be found, so
//--- this fails with 197 slots or fewer and passes with 256.
string TestWorstCaseKeepsBarWhileInWindow()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   int lookback = CC_MAX_LOOKBACK;
   datetime x = D'2026.01.05 00:00';

   // Step 0: X has just closed (shift 1) and is the only confluence.
   EmptyWindow(bars, lookback, x);
   bars[0].signalBuy = true;
   bars[0].regularBull = true;
   int found = CC_Scan(bars, lookback, opt, memory, matches);
   if(found != 1 || CountNew(matches, found) != 1)
      return("step 0: X not reported once as new");

   for(int step = 1; step < lookback; step++)
     {
      EmptyWindow(bars, lookback, (datetime)((long)x + (long)step * BAR_SECONDS));
      int k = FindShift(bars, x);
      if(k != step)
         return("test setup: X at index " + IntegerToString(k) + " on step " + IntegerToString(step));
      bars[k].signalBuy = true;                // X keeps its arrows
      bars[k].regularBull = true;
      bars[0].signalBuy = true;                // a new bar
      bars[0].regularBull = true;
      bars[lookback - 1].signalBuy = true;     // the oldest bar still in the window
      bars[lookback - 1].regularBull = true;

      found = CC_Scan(bars, lookback, opt, memory, matches);
      for(int m = 0; m < found; m++)
         if(matches[m].time == x && matches[m].isNew)
            return("X reported as new again at shift " + IntegerToString(step + 1));
      if(!memory.Seen(x))
         return("X forgotten at shift " + IntegerToString(step + 1) + " with " +
                IntegerToString(memory.Capacity()) + " slots");
     }
   return("");
  }

void SetConfluence(CCBar &bar, const bool buy)
  {
   if(buy)
     {
      bar.signalBuy = true;
      bar.regularBull = true;
     }
   else
     {
      bar.signalSell = true;
      bar.hiddenBear = true;
     }
  }

//--- History pass: live window of 10 bars, 20 older bars marked. Confluences
//--- at shifts 15 and 25 are returned oldest first, with their kinds.
string TestHistoryMarksPastConfluence()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 30, D'2026.01.05 10:00');
   SetConfluence(bars[14], true);     // shift 15
   SetConfluence(bars[24], false);    // shift 25

   int found = CC_ScanHistory(bars, 30, opt, 10, 20, matches);
   if(found != 2)
      return("found " + IntegerToString(found) + ", expected 2");
   if(matches[0].shift != 25 || matches[0].signalDir != -1 || matches[0].divergence != CC_DIV_HIDDEN_BEAR)
      return("first match: expected SELL + hidden bearish at shift 25");
   if(matches[1].shift != 15 || matches[1].signalDir != 1 || matches[1].divergence != CC_DIV_REGULAR_BULL)
      return("second match: expected BUY + regular bullish at shift 15");
   if(matches[0].time != bars[24].time || matches[1].time != bars[14].time)
      return("match times do not follow the bars");
   return("");
  }

//--- Every history bar is a confluence never seen by any memory. The history
//--- pass must still report none of them as new, so the indicator has nothing
//--- to alert from it. An implementation that reused CC_Scan with a memory of
//--- its own would report all 20 as new and fail here. (That it cannot change
//--- the live memory follows from its signature, which takes none.)
string TestHistoryReportsNothingAsNew()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 30, D'2026.01.05 10:00');
   for(int k = 10; k < 30; k++)       // shifts 11..30
      SetConfluence(bars[k], (k % 2) == 0);

   int found = CC_ScanHistory(bars, 30, opt, 10, 20, matches);
   if(found != 20)
      return("found " + IntegerToString(found) + ", expected 20");
   if(CountNew(matches, found) != 0)
      return(IntegerToString(CountNew(matches, found)) + " history matches reported as new");
   return("");
  }

//--- X alerts at the last shift of the live window (10). On the same chart the
//--- history pass does not return it, so it is marked by one pass only, and a
//--- redraw on the same bar (live scan, then history again) finds X in the
//--- window as already alerted. One bar later X is at shift 11, the first
//--- history shift; if the buffers are redrawn then, the history pass marks it
//--- without reporting it as new.
string TestHistoryAndLiveDoNotRepeat()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCMemory memory;
   CCBar bars[];
   CCMatch matches[];
   datetime closed = D'2026.01.05 10:00';

   EmptyWindow(bars, 30, closed);
   SetConfluence(bars[9], true);      // shift 10
   datetime x = bars[9].time;
   int found = CC_Scan(bars, 10, opt, memory, matches);
   if(found != 1 || !matches[0].isNew)
      return("live scan: X not reported once as new");
   found = CC_ScanHistory(bars, 30, opt, 10, 20, matches);
   if(found != 0)
      return("same chart: history pass returned a bar of the live window");

   // Redraw on the same bar: the live scan sees X again, already alerted.
   found = CC_Scan(bars, 10, opt, memory, matches);
   if(found != 1 || matches[0].time != x || matches[0].isNew)
      return("redraw on the same bar: X not found once as already alerted");

   EmptyWindow(bars, 30, (datetime)(closed + BAR_SECONDS));
   int k = FindShift(bars, x);
   if(k != 10)
      return("test setup: X at index " + IntegerToString(k) + " after new bar");
   SetConfluence(bars[k], true);      // shift 11
   found = CC_ScanHistory(bars, 30, opt, 10, 20, matches);
   if(found != 1 || matches[0].time != x || matches[0].shift != 11 || matches[0].isNew)
      return("next bar: history pass did not mark X once at shift 11 as not new");
   return("");
  }

//--- History bars where only one indicator marks, or the directions disagree
//--- with matching on, are not marked.
string TestHistorySingleIndicatorNotMarked()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 30, D'2026.01.05 10:00');
   bars[14].signalBuy = true;         // shift 15: signal only
   bars[17].regularBull = true;       // shift 18: divergence only
   bars[19].signalBuy = true;         // shift 20: bullish signal, bearish divergence
   bars[19].regularBear = true;

   int found = CC_ScanHistory(bars, 30, opt, 10, 20, matches);
   if(found != 0)
      return("found " + IntegerToString(found) + " matches, expected 0");
   return("");
  }

//--- With 5 history bars after a live window of 10, shift 15 is the oldest
//--- marked bar and shift 16 is not; with 0 history bars nothing is marked;
//--- with the largest int as cap both are marked (no overflow of the range).
string TestHistoryRespectsBarCap()
  {
   CCOptions opt;
   DefaultOptions(opt);
   CCBar bars[];
   CCMatch matches[];

   EmptyWindow(bars, 30, D'2026.01.05 10:00');
   SetConfluence(bars[14], true);     // shift 15
   SetConfluence(bars[15], true);     // shift 16

   int found = CC_ScanHistory(bars, 30, opt, 10, 5, matches);
   if(found != 1 || matches[0].shift != 15)
      return("cap 5: expected only shift 15, found " + IntegerToString(found));
   found = CC_ScanHistory(bars, 30, opt, 10, 0, matches);
   if(found != 0)
      return("cap 0: found " + IntegerToString(found));
   found = CC_ScanHistory(bars, 30, opt, 10, INT_MAX, matches);
   if(found != 2)
      return("cap INT_MAX: found " + IntegerToString(found) + ", expected 2");
   return("");
  }

void OnStart()
  {
   Report("SameBarAlertsOnceAcrossTicks", TestSameBarAlertsOnceAcrossTicks());
   Report("SingleIndicatorDoesNotAlert", TestSingleIndicatorDoesNotAlert());
   Report("BackdrawnAlertsOnceThenNotAgain", TestBackdrawnAlertsOnceThenNotAgain());
   Report("DirectionMatching", TestDirectionMatching());
   Report("MemoryRingKeepsMostRecent", TestMemoryRingKeepsMostRecent());
   Report("MemoryIgnoresDuplicates", TestMemoryIgnoresDuplicates());
   Report("EmptyValueAndZeroAreNoSignal", TestEmptyValueAndZeroAreNoSignal());
   Report("RegularHiddenSwitches", TestRegularHiddenSwitches());
   Report("OutsideLookbackIsIgnored", TestOutsideLookbackIsIgnored());
   Report("SignalThenDivergenceOnSameBar", TestSignalThenDivergenceOnSameBar());
   Report("StreamOneNewPerBarTime", TestStreamOneNewPerBarTime());
   Report("WorstCaseKeepsBarWhileInWindow", TestWorstCaseKeepsBarWhileInWindow());
   Report("HistoryMarksPastConfluence", TestHistoryMarksPastConfluence());
   Report("HistoryReportsNothingAsNew", TestHistoryReportsNothingAsNew());
   Report("HistoryAndLiveDoNotRepeat", TestHistoryAndLiveDoNotRepeat());
   Report("HistorySingleIndicatorNotMarked", TestHistorySingleIndicatorNotMarked());
   Report("HistoryRespectsBarCap", TestHistoryRespectsBarCap());
   Print(IntegerToString(g_passed), " passed, ", IntegerToString(g_failed), " failed");
  }
