# Two failure modes of "two indicators on the same candle" alerts

An MT4 alert that fires when indicator A (a signal) and indicator B (a divergence) mark the same candle usually breaks in one of two ways. Both come from how MetaTrader 4 runs indicators, so each mechanism below is backed by a quote from the MQL4 reference.

## 1. Every-tick repeat

### Mechanism: OnCalculate runs per tick

`OnCalculate()` is not called once per bar. It is called on ticks:

> "This usually happens when a new tick is received for the symbol, for which the indicator is calculated."
> — <https://docs.mql4.com/basis/function/events>

Bars are addressed by shift, counted back from the forming bar:

> "The current bar which is the last in the array is indexed as 0."
> — <https://docs.mql4.com/predefined/time>

The closed bar is shift 1, and for non-repainting indicators its values do not change until the next bar opens. A naive check runs on every tick:

```mql4
// Broken: true on every tick of the bar after the confluence.
if(CC_IsSignal(iCustom(NULL, 0, "A", 0, 1)) && CC_IsSignal(iCustom(NULL, 0, "B", 0, 1)))
   SendMail("Confluence", "...");
```

That sends one email per tick until the next bar opens.

### Fix: new-bar gate plus memory

Two independent guards, so a mistake in one does not reopen the bug:

1. `ConfluenceAlert.mq4` evaluates only when the open time of bar 0 changes (a new bar), when the terminal resets `prev_calculated` to zero after a history reload, or on the next tick after a read of A or B set an error:
   > "the value of the input parameter prev_calculated will be set to zero by the terminal."
   > — <https://docs.mql4.com/basis/function/events>
2. `ConfluenceCore.mqh` remembers the open time of every bar that already alerted (`CCMemory`). Scanning the same window again returns the match with `isNew == false`. The unit tests cover this guard: test `SameBarAlertsOnceAcrossTicks` scans the same window 50 more times and expects no new match. The new-bar gate in guard 1 lives in the indicator and is not unit tested; it is to be checked on a chart.

## 2. Backdrawn arrows

### Mechanism: the arrow appears late

Pivot and divergence indicators cannot know that a bar is a pivot until some bars after it have closed. Many of them then draw the arrow on the pivot bar itself, which is already several bars old. `RsiDivergence.mq4` in this repo does this on purpose: with `InpRight = 3`, the arrow appears when its bar is at shift 4.

`iCustom()` reads one buffer value at one shift:

> "Index of the value taken from the indicator buffer (shift relative to the current bar the given amount of periods ago)."
> — <https://docs.mql4.com/indicators/icustom>

Two naive fixes both fail:

- **Check only shift 1.** The arrow never exists at shift 1, so the alert never fires.
- **Scan shifts 1..N without memory.** The arrow is found at shift 4, alerts, and on the next bar it is found again at shift 5, and alerts again, once per bar until it leaves the scanned range.

### Fix: lookback scan plus memory keyed by bar time

On each new bar, `ConfluenceAlert.mq4` reads shifts `1..InpLookback` and passes them to `CC_Scan()`. The memory is keyed by bar open time, not by shift: the shift of a bar grows by one on every new bar, its open time does not. So the pivot found at shift 4 is remembered, and when it is at shift 5 on the next bar `CC_Scan()` returns it with `isNew == false`. Test `BackdrawnAlertsOnceThenNotAgain` checks exactly this: no arrow, then an arrow drawn back at shift 3 (one new match), then the same arrow at shift 4 on the next bar (no new match).

Limits that follow from the mechanism:

- An arrow drawn back further than `InpLookback` bars is never seen. Test `OutsideLookbackIsIgnored` shows a match at shift 7 is missed with lookback 5 and found with lookback 8. Set `InpLookback` larger than B's backdraw.
- The memory holds 256 bar times. While one bar stays in a window of L bars, at most 2L-1 distinct bars pass through that window, so for the allowed `InpLookback` of 1..100 a bar cannot be forgotten while it can still be found. Test `MemoryRingKeepsMostRecent` checks that the newest 256 entries survive a wrap. Test `StreamOneNewPerBarTime` runs 600 bars with a confluence on every bar and lookback 100, one bar per step, and expects each bar time to be reported as new exactly once. In that stream only the newest bar is added on each step, so it exercises the wrap over many bars but not the 2L-1 worst case. Test `WorstCaseKeepsBarWhileInWindow` covers that case: while one bar moves from shift 1 to shift 100, the newest bar and the oldest bar of the window get a confluence on every step, 197 other bar times enter the memory, and the bar must still be remembered at shift 100. It would fail with 197 slots or fewer. Test `MemoryRingKeepsMostRecent` also fails if the capacity drops below 2 * 100 - 1.

## Past confluences on load

The live scan only covers shifts `1..InpLookback`, so a freshly loaded instance would show gold circles only inside that window. When the buffers are drawn from scratch (first evaluation of a load, or `prev_calculated` reset to zero), `ConfluenceAlert.mq4` also reads shifts `InpLookback + 1` to `InpLookback + InpHistoryBars` (default 1000, `0` = off) and passes them to `CC_ScanHistory()`. It uses the same matching as `CC_Scan()` but takes no memory, so it cannot record a bar, prime the indicator or report a match as new: history never alerts. It skips bars inside the live window, so no bar is marked by both passes. Tests `HistoryMarksPastConfluence`, `HistoryLeavesLiveMemoryUntouched`, `HistoryAndLiveDoNotRepeat`, `HistorySingleIndicatorNotMarked` and `HistoryRespectsBarCap` cover this.

What a past circle means: A's and B's arrows as they are drawn now, not what alerted in real time. A backdrawn divergence is marked on the pivot bar where it ended up, an arrow that was removed later is not marked, and a past circle does not prove an alert went out.

If a read of A or B sets an error during this pass, the past circles are skipped for that load and one line is printed; the live state is not touched, and the live evaluation calls `ResetLastError()` before its own reads:

> "Sets the value of the predefined variable _LastError into zero."
> — <https://docs.mql4.com/common/resetlasterror>

## The "no signal" rule

A buffer value counts as a signal when it is not `EMPTY_VALUE` and not 0. `EMPTY_VALUE` is the documented default:

> "Empty value in an indicator buffer. Default custom indicator empty value" (2147483647, 0x7FFFFFFF)
> — <https://docs.mql4.com/constants/namedconstants/otherconstants>

The same rule shows in how buffers are drawn:

> "Empty values are not drawn or shown in the DataWindow. By default, empty value is EMPTY_VALUE."
> — <https://docs.mql4.com/customind/setindexemptyvalue>

Some indicators clear their arrow buffers with 0 instead, so 0 is treated as "no signal" too (test `EmptyValueAndZeroAreNoSignal`). An indicator that sets a different empty value with `SetIndexEmptyValue()` would need `CC_IsSignal()` changed.

## Where alerts can and cannot be checked

The alert channels do not run in the Strategy Tester:

> "The Alert(), MessageBox(), PlaySound(), SendFTP, SendMail(), SendNotification() and WebRequest() functions" ... "are not executed in the Strategy Tester."
> — <https://docs.mql4.com/runtime/testing>

`Print()` is not on that list. The same page says it is skipped during optimization, and on build 1492 it did run in a normal test: each alert's text is in the tester's log. The same log also had an `Alert:` line per alert, with no popup.

> "To increase performance, Print() and PrintFormat() functions are not executed when optimizing the trading robot's parameters."
> — <https://docs.mql4.com/runtime/testing>

Indicators on the visual testing chart: on MT4 build 1492 we observed that the indicators called by `ConfluenceVisualTest` are not drawn while the test runs; they are attached to the tester chart after the test ends, as fresh instances. This is an observation, not documented behaviour: <https://docs.mql4.com/runtime/testing> does not describe it. A fresh `ConfluenceAlert` would only mark its lookback window, which is why the past-confluence pass above exists; with it, the gold circles appear on the tester chart once the test ends (screenshot in the README).

So the tester shows the printed alert text and, after the test ends, the markers. Email, push and popup are to be checked on a live or demo chart.
