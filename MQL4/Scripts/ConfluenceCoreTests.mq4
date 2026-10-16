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
      ClearBar(bars[k], (datetime)(lastClosedTime - k * BAR_SECONDS), k + 1);
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
   datetime base = D'2026.01.01 00:00';

   for(int i = 0; i < cap + extra; i++)
      memory.Remember((datetime)(base + i * BAR_SECONDS));

   if(memory.Count() != cap)
      return("count " + IntegerToString(memory.Count()) + ", expected " + IntegerToString(cap));
   for(int i = extra; i < cap + extra; i++)
      if(!memory.Seen((datetime)(base + i * BAR_SECONDS)))
         return("forgot recent entry " + IntegerToString(i));
   for(int i = 0; i < extra; i++)
      if(memory.Seen((datetime)(base + i * BAR_SECONDS)))
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
   Print(IntegerToString(g_passed), " passed, ", IntegerToString(g_failed), " failed");
  }
