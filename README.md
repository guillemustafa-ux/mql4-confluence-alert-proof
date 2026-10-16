# MQL4 confluence alert proof

An MT4 indicator that sends one alert (email, push notification or popup) when two other indicators mark the same closed candle: indicator A gives a buy/sell signal and indicator B marks a regular or hidden divergence.

It exists to show how two common bugs in this kind of alert are avoided:

1. **Every-tick repeat.** The closed bar keeps the same values on every tick until the next bar opens, so a naive check alerts on every tick.
2. **Backdrawn arrows.** Divergence and pivot indicators often draw the arrow on the pivot candle several bars after it formed. Checking only the last closed bar misses it; scanning back without memory alerts again each time the arrow moves one bar older.

The mechanism of each, with quotes from the MQL4 reference, is in [docs/FAILURE-MODES.md](docs/FAILURE-MODES.md).

> **Status:** written without a MetaTrader 4 install. Nothing here has been compiled or run yet.
> TODO(compile): MetaEditor build number and compile result (0 errors, 0 warnings) go here.
> TODO(chart): test script output and a visual Strategy Tester screenshot go here.

## What is in the repo

The layout mirrors the MT4 data folder, so `MQL4/` can be copied over yours.

| File | Role |
|------|------|
| `MQL4/Include/ConfluenceCore.mqh` | Pure logic: which bars in the lookback window have a confluence, and which of those have not alerted yet (ring buffer of bar times). No terminal calls, so it has unit tests (not run yet). |
| `MQL4/Indicators/ConfluenceAlert.mq4` | The indicator you attach. Reads A and B with `iCustom`, evaluates once per new bar (again on the next tick if a read fails), alerts, draws gold circles on confluence bars. |
| `MQL4/Indicators/SwingArrows.mq4` | Demo indicator A: swing low (buffer 0, bullish) and swing high (buffer 1, bearish) arrows. Draws back `InpRight` bars on purpose. |
| `MQL4/Indicators/RsiDivergence.mq4` | Demo indicator B: RSI regular and hidden divergence on price pivots. Buffers 0 regular bull, 1 regular bear, 2 hidden bull, 3 hidden bear. Arrow on the pivot bar (backdraw). |
| `MQL4/Include/SwingPivot.mqh` | Pivot rule shared by both demo indicators, so with equal strengths they mark the same bars and the demo produces confluences. |
| `MQL4/Scripts/ConfluenceCoreTests.mq4` | Unit tests of the core. Prints `PASS name` / `FAIL name: detail` and `N passed, M failed`. |
| `MQL4/Experts/ConfluenceVisualTest.mq4` | Places no orders. Only calls the three indicators, so the Strategy Tester is expected to draw them (to be confirmed on a chart). |

## Verify it in about 5 minutes

1. Install MetaTrader 4 from <https://www.metatrader4.com/en/download> and open a demo account.
2. In MT4: **File > Open Data Folder**. Copy this repo's `MQL4` folder into it, merging with the existing `MQL4`.
3. Open MetaEditor and compile, in this order: `Indicators/SwingArrows.mq4`, `Indicators/RsiDivergence.mq4`, `Indicators/ConfluenceAlert.mq4`, `Scripts/ConfluenceCoreTests.mq4`, `Experts/ConfluenceVisualTest.mq4`. Each should report 0 errors.
4. **Unit tests.** In MT4's Navigator, drag `Scripts > ConfluenceCoreTests` onto any chart. Open the **Experts** tab of the Terminal window. Expect twelve `PASS` lines and `12 passed, 0 failed`.
5. **Live chart.** Drag `SwingArrows`, `RsiDivergence` and `ConfluenceAlert` onto a chart (M5 shows results fastest). Gold circles mark confluences found inside the lookback window. The first evaluation only records what is already on the chart; popups start with the next confluence that appears (see Limits).
6. **Strategy Tester.** Open the Strategy Tester, choose Expert Advisor `ConfluenceVisualTest`, a symbol and period, tick **Visualization**, press Start. The arrows of both demo indicators and the gold circles are expected to appear on the tester chart, because the MQL4 reference says indicators called directly from the tested EA can be drawn there (to be confirmed on a chart). Popup, email and push are not executed in the tester. The alert text is also written with `Print()`, which is expected to show in the tester's log (inferred from the reference, to be confirmed on a chart).
7. **Email.** On a live or demo chart, configure the terminal settings **Email** tab, set `InpEmail = true` on `ConfluenceAlert` and wait for a confluence. Push works the same way with the **Notifications** tab and `InpPush = true`.

## Using it with your own two indicators

Put both compiled indicators in `MQL4/Indicators/` and set these inputs on `ConfluenceAlert`:

| Input | Meaning |
|-------|---------|
| `InpAName`, `InpBName` | File name of the indicator without `.ex4`, relative to `MQL4/Indicators/`. For a subfolder the reference shows `"Examples\\indicator_name"`, a string literal in source code where `\\` stands for one backslash, so in this input field type a single backslash: `Examples\indicator_name` (to be checked on a chart). |
| `InpABuyBuffer`, `InpASellBuffer` | Buffer index of A's buy and sell arrows (0-7, from the Data Window or the source). `-1` = not used. |
| `InpBRegBullBuffer`, `InpBRegBearBuffer`, `InpBHidBullBuffer`, `InpBHidBearBuffer` | Buffer index of each divergence kind in B. `-1` = B does not have it. |
| `InpAParamCount`, `InpAParam1..3` (same for B) | `0` runs the indicator with its own default inputs. `1..3` passes that many inputs, in declaration order, as `double`. |
| `InpLookback` | Closed bars scanned on each new bar (1-100). Must reach the shift at which B's arrow first appears on a new bar: for the demo (`InpRight = 3`) that is shift 4, so at least 4. If B draws its arrow while the bar is still forming, it is read at the next new bar one shift older, so add one. |
| `InpMatchDirection` | `true`: bullish A only with bullish B, bearish with bearish. `false`: any A with any B on the same bar. |
| `InpUseRegular`, `InpUseHidden` | Which divergence kinds count. |
| `InpEmail`, `InpPush`, `InpPopup` | Alert channels. |

A and B are read with their own default inputs unless `InpAParamCount` / `InpBParamCount` and the values are set. Changing `InpLeft` or `InpRight` on the demo indicators attached to the chart does not change what `ConfluenceAlert` reads.

**Signal rule:** a buffer value counts as a signal when it is not `EMPTY_VALUE` and not `0`. `EMPTY_VALUE` is MT4's default "nothing here" value; some indicators use `0` instead, so both are treated as no signal.

## Behavior, walked case by case

- **Next tick of the same bar:** no evaluation, because bar 0's open time has not changed. If an evaluation happens again on the same bar after a history reload, the memory returns the bar as already alerted. After a failed read nothing was recorded, so the retry on the next tick is the first real evaluation of that bar and can alert.
- **Next bar:** shifts 1..`InpLookback` are read again. A bar that already alerted is one bar older but has the same open time, so it is not alerted again.
- **Arrow drawn back onto an older bar:** found as long as it is within `InpLookback`, alerted once.
- **Several new confluences in one evaluation:** popup and email list all of them in one message per channel. Push sends one notification with the count and the latest one, because a notification is limited to 255 characters. Messages are only sent from an evaluation, and evaluations happen on a new bar, after a history reload, or on a retry after a failed read, so on M1 a chart normally sends at most one push per minute. The documented push limit is 2 calls per second and 10 per minute, and the function can be disabled if it is exceeded; keep that in mind when the indicator runs on many charts.
- **Reload** (input change, symbol or timeframe change, recompile, terminal restart): the memory starts empty, and the first evaluation records the window without alerting, so old confluences are not resent (see Limits).

## Troubleshooting

- No alerts and a repeating "reading A or B failed" line in the Experts tab: check the indicator names and buffer indexes.

## Limits

- MQL4 / MetaTrader 4 only. Not compiled in CI: compiling needs MetaEditor, which is not part of this repo's automation.
- `SendMail`, `SendNotification` and `Alert` do not run in the Strategy Tester (MQL4 reference). Email and push are to be verified on a live or demo chart.
- Only closed bars are evaluated. A signal on the forming bar is seen after that bar closes.
- A and B must mark the exact same bar. There is no plus-or-minus one bar tolerance.
- A read of A or B that sets an error code makes the indicator retry on the next tick instead of recording the window. An indicator that is not ready yet and returns `0` or `EMPTY_VALUE` without setting an error cannot be told apart from "no arrow": if that happens on the first evaluation, the window is recorded as empty and confluences already on the chart can alert at the next bar.
- A confluence that appears while the terminal is off, and is still in the window at start-up, is recorded without an alert.
- If A or B removes an arrow after the alert (repainting), the alert has already gone out. The gold circle disappears at the next new bar if the bar is still inside the window.
- Inputs passed with `InpAParamCount > 0` are sent as `double`. The MQL4 reference says the passed parameters must match the indicator's input types, so for indicators with `int`, `bool`, `string` or enum inputs use count `0` and set the indicator's own defaults.
- An indicator that marks "no signal" with a value other than `EMPTY_VALUE` or `0` needs `CC_IsSignal()` changed.
- One bar can carry several kinds (for example regular and hidden). It alerts once, with the first kind matched: same direction first, regular before hidden.
- The demo indicators exist to exercise the alert logic. They are not trading advice and say nothing about profitability.
