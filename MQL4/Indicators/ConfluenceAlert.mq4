//+------------------------------------------------------------------+
//| ConfluenceAlert.mq4                                              |
//| Alerts when indicator A (signal arrows) and indicator B          |
//| (divergence arrows) mark the same closed bar.                    |
//|                                                                  |
//| Two failure modes are handled (see docs/FAILURE-MODES.md):       |
//|  1. Every-tick repeat: OnCalculate runs on every tick, and the   |
//|     closed bar keeps the same values until the next bar opens.   |
//|     The window is evaluated only when a new bar opens, and bar   |
//|     times that already alerted are remembered.                   |
//|  2. Backdrawn arrows: B may draw its arrow on a pivot bar that   |
//|     is already several bars old. Shifts 1..InpLookback are       |
//|     scanned on each new bar; the memory stops the same bar from  |
//|     alerting again when it moves one bar older.                  |
//|                                                                  |
//| When the buffers are drawn from scratch (load, history reload),  |
//| confluences older than the window are also marked, up to         |
//| InpHistoryBars bars. Those marks never alert.                    |
//|                                                                  |
//| Signal rule: a buffer value counts as a signal when it is not    |
//| EMPTY_VALUE and not 0 (some indicators clear buffers with 0).    |
//+------------------------------------------------------------------+
#property strict
#property description "One alert per bar when indicator A and indicator B mark the same closed bar"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 clrGold
#property indicator_color2 clrGold
#property indicator_width1 3
#property indicator_width2 3

#include <ConfluenceCore.mqh>

input string InpAName        = "SwingArrows";   // A: signal indicator file name (MQL4/Indicators)
input int    InpAParamCount  = 0;               // A: inputs to pass (0-3, double; 0 = A defaults)
input double InpAParam1      = 0;               // A: input 1
input double InpAParam2      = 0;               // A: input 2
input double InpAParam3      = 0;               // A: input 3
input int    InpABuyBuffer   = 0;               // A: buy buffer (-1 = unused; not EMPTY_VALUE/0)
input int    InpASellBuffer  = 1;               // A: sell buffer (-1 = unused; not EMPTY_VALUE/0)

input string InpBName        = "RsiDivergence"; // B: divergence indicator file name
input int    InpBParamCount  = 0;               // B: inputs to pass (0-3, double; 0 = B defaults)
input double InpBParam1      = 0;               // B: input 1
input double InpBParam2      = 0;               // B: input 2
input double InpBParam3      = 0;               // B: input 3
input int    InpBRegBullBuffer = 0;             // B: regular bullish buffer (-1 = unused)
input int    InpBRegBearBuffer = 1;             // B: regular bearish buffer (-1 = unused)
input int    InpBHidBullBuffer = 2;             // B: hidden bullish buffer (-1 = unused)
input int    InpBHidBearBuffer = 3;             // B: hidden bearish buffer (-1 = unused)

input int    InpLookback     = 10;              // Closed bars scanned (1-100), > B's backdraw
input int    InpHistoryBars  = 1000;            // Older bars marked on load, never alerted (0 = off)
input bool   InpMatchDirection = true;          // Bullish A only with bullish B (bear with bear)
input bool   InpUseRegular   = true;            // Alert on regular divergence
input bool   InpUseHidden    = true;            // Alert on hidden divergence
input bool   InpEmail        = false;           // Send email (terminal settings, Email tab)
input bool   InpPush         = false;           // Send push notification (Notifications tab)
input bool   InpPopup        = true;            // Show popup Alert()

double    g_bullMarks[];
double    g_bearMarks[];
CCMemory  g_memory;
CCOptions g_options;
datetime  g_lastBarTime = 0;
datetime  g_errorBarTime = 0;
bool      g_primed = false;
bool      g_historyPending = false;

int OnInit()
  {
   if(InpLookback < 1 || InpLookback > CC_MAX_LOOKBACK)
     {
      Print("ConfluenceAlert: InpLookback must be between 1 and ", IntegerToString(CC_MAX_LOOKBACK));
      return(INIT_FAILED);
     }
   if(InpHistoryBars < 0)
     {
      Print("ConfluenceAlert: InpHistoryBars must be 0 or more");
      return(INIT_FAILED);
     }
   if(InpAParamCount < 0 || InpAParamCount > 3 || InpBParamCount < 0 || InpBParamCount > 3)
     {
      Print("ConfluenceAlert: parameter counts must be between 0 and 3");
      return(INIT_FAILED);
     }

   g_options.matchDirection = InpMatchDirection;
   g_options.useRegular     = InpUseRegular;
   g_options.useHidden      = InpUseHidden;

   // The terminal reloads the indicator on input, symbol or timeframe change;
   // starting unprimed means bars already in the window are recorded without
   // alerting, so a reload does not resend old confluences.
   g_memory.Reset();
   g_lastBarTime = 0;
   g_errorBarTime = 0;
   g_primed = false;
   g_historyPending = false;

   SetIndexBuffer(0, g_bullMarks);
   SetIndexBuffer(1, g_bearMarks);
   ArraySetAsSeries(g_bullMarks, true);
   ArraySetAsSeries(g_bearMarks, true);
   SetIndexStyle(0, DRAW_ARROW);
   SetIndexStyle(1, DRAW_ARROW);
   SetIndexArrow(0, 108);
   SetIndexArrow(1, 108);
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| iCustom needs the inputs written out in the call, so the count   |
//| selects one of four fixed call shapes.                           |
//+------------------------------------------------------------------+
double ReadIndicator(const string name, const int paramCount,
                     const double p1, const double p2, const double p3,
                     const int buffer, const int shift)
  {
   switch(paramCount)
     {
      case 1: return(iCustom(NULL, 0, name, p1, buffer, shift));
      case 2: return(iCustom(NULL, 0, name, p1, p2, buffer, shift));
      case 3: return(iCustom(NULL, 0, name, p1, p2, p3, buffer, shift));
     }
   return(iCustom(NULL, 0, name, buffer, shift));
  }

bool ReadA(const int buffer, const int shift)
  {
   if(buffer < 0)
      return(false);
   return(CC_IsSignal(ReadIndicator(InpAName, InpAParamCount, InpAParam1, InpAParam2, InpAParam3, buffer, shift)));
  }

bool ReadB(const int buffer, const int shift)
  {
   if(buffer < 0)
      return(false);
   return(CC_IsSignal(ReadIndicator(InpBName, InpBParamCount, InpBParam1, InpBParam2, InpBParam3, buffer, shift)));
  }

void ReadBar(CCBar &bar, const datetime &time[], const int shift)
  {
   bar.time        = time[shift];
   bar.shift       = shift;
   bar.signalBuy   = ReadA(InpABuyBuffer, shift);
   bar.signalSell  = ReadA(InpASellBuffer, shift);
   bar.regularBull = ReadB(InpBRegBullBuffer, shift);
   bar.regularBear = ReadB(InpBRegBearBuffer, shift);
   bar.hiddenBull  = ReadB(InpBHidBullBuffer, shift);
   bar.hiddenBear  = ReadB(InpBHidBearBuffer, shift);
  }

void PlaceMark(const CCMatch &match, const double &high[], const double &low[])
  {
   int s = match.shift;
   double gap = 1.3 * (high[s] - low[s]);
   if(match.signalDir > 0)
      g_bullMarks[s] = low[s] - gap;
   else
      g_bearMarks[s] = high[s] + gap;
  }

string TimeframeName()
  {
   switch(Period())
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("M" + IntegerToString(Period()));
  }

string DescribeMatch(const CCMatch &match)
  {
   return(Symbol() + " " + TimeframeName() + " bar " +
          TimeToString(match.time, TIME_DATE | TIME_MINUTES) + ": " +
          CC_SignalName(match.signalDir) + " signal + " +
          CC_DivergenceName(match.divergence) + " divergence (found at shift " +
          IntegerToString(match.shift) + ")");
  }

//+------------------------------------------------------------------+
//| One message per channel per evaluation, even with several new    |
//| matches: SendNotification is documented as limited to 2 calls    |
//| per second and 10 per minute.                                    |
//+------------------------------------------------------------------+
void SendAlerts(const string body, const string latest, const int freshCount)
  {
   string subject = "ConfluenceAlert " + Symbol() + " " + TimeframeName();
   // The reference lists Alert/SendMail/SendNotification as not executed in the
   // Strategy Tester and Print as skipped only during optimization, so Print is
   // expected to leave the alert text in the tester log (to be confirmed on a chart).
   Print(subject, ": ", body);

   if(InpPopup)
      Alert(body);
   if(InpEmail && !SendMail(subject, body))
      Print("ConfluenceAlert: SendMail failed, error ", IntegerToString(GetLastError()));
   if(InpPush)
     {
      string push = (freshCount == 1) ? latest
                    : IntegerToString(freshCount) + " new confluences, latest: " + latest;
      if(!SendNotification(push))
         Print("ConfluenceAlert: SendNotification failed, error ", IntegerToString(GetLastError()));
     }
  }

bool Evaluate(const datetime &time[], const double &high[], const double &low[])
  {
   CCBar bars[];
   ArrayResize(bars, InpLookback);
   ResetLastError();
   for(int k = 0; k < InpLookback; k++)
      ReadBar(bars[k], time, k + 1);     // shift 0 is still forming and is never evaluated

   // A failed read may return a value that looks like "no arrow". Scanning it
   // would record an empty window (and, on the first evaluation, prime on it,
   // so old confluences would alert on the next bar). Nothing is recorded
   // and the caller retries on the next tick.
   int readError = GetLastError();
   if(readError != 0)
     {
      if(time[0] != g_errorBarTime)
         Print("ConfluenceAlert: reading A or B failed, error ", IntegerToString(readError), "; retrying on the next tick");
      g_errorBarTime = time[0];
      return(false);
     }

   CCMatch matches[];
   int found = CC_Scan(bars, InpLookback, g_options, g_memory, matches);

   // Markers inside the window follow what A and B show now; older markers stay.
   for(int clearShift = 1; clearShift <= InpLookback; clearShift++)
     {
      g_bullMarks[clearShift] = EMPTY_VALUE;
      g_bearMarks[clearShift] = EMPTY_VALUE;
     }

   string body = "";
   string latest = "";
   int freshCount = 0;
   for(int m = 0; m < found; m++)
     {
      PlaceMark(matches[m], high, low);

      // The first evaluation only records what is already on the chart.
      if(!matches[m].isNew || !g_primed)
         continue;
      latest = DescribeMatch(matches[m]);
      body = (body == "") ? latest : body + "\r\n" + latest;
      freshCount++;
     }

   g_primed = true;
   if(freshCount > 0)
      SendAlerts(body, latest, freshCount);
   return(true);
  }

//+------------------------------------------------------------------+
//| Marks confluences on shifts InpLookback+1 .. InpLookback+        |
//| InpHistoryBars, after a successful evaluation on fresh buffers.  |
//| It only draws: no alert, and g_memory, g_primed, g_lastBarTime   |
//| and g_errorBarTime are not used (CC_ScanHistory has no memory    |
//| parameter). The marks show A and B as they are drawn now, not    |
//| what alerted in real time.                                       |
//+------------------------------------------------------------------+
void MarkHistory(const int rates_total, const datetime &time[], const double &high[], const double &low[])
  {
   // Capped by the bars on the chart before adding, so a huge input cannot overflow.
   int count = rates_total - 1 - InpLookback;
   if(InpHistoryBars < count)
      count = InpHistoryBars;
   if(count <= 0)
      return;
   int last = InpLookback + count;

   CCBar bars[];
   ArrayResize(bars, count);
   ResetLastError();
   for(int k = 0; k < count; k++)
      ReadBar(bars[k], time, InpLookback + 1 + k);

   // A failed read may look like "no arrow", so history marks are skipped
   // until the buffers are next drawn from scratch; nothing is retried. Live
   // alerts are not affected: Evaluate() calls ResetLastError(), which "Sets
   // the value of the predefined variable _LastError into zero"
   // (docs.mql4.com/common/resetlasterror), before its own reads.
   int readError = GetLastError();
   if(readError != 0)
     {
      Print("ConfluenceAlert: reading A or B for past bars failed, error ", IntegerToString(readError), "; past bars not marked");
      return;
     }

   CCMatch matches[];
   int found = CC_ScanHistory(bars, count, g_options, InpLookback, count, matches);
   for(int m = 0; m < found; m++)
      PlaceMark(matches[m], high, low);
   Print("ConfluenceAlert: marked ", IntegerToString(found), " past confluences on shifts ",
         IntegerToString(InpLookback + 1), "-", IntegerToString(last), " (no alerts)");
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
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int fresh = (prev_calculated <= 0) ? rates_total : rates_total - prev_calculated;
   for(int i = 0; i < fresh && i < rates_total; i++)
     {
      g_bullMarks[i] = EMPTY_VALUE;
      g_bearMarks[i] = EMPTY_VALUE;
     }
   // Every buffer value was just cleared, so past marks are drawn again.
   if(prev_calculated <= 0 && InpHistoryBars > 0)
      g_historyPending = true;

   if(rates_total <= InpLookback + 1)
      return(0);

   // OnCalculate runs on every tick; the closed bars only change when a new
   // bar opens. A history reload (prev_calculated == 0) also redraws the
   // window; the memory keeps that redraw from alerting again.
   if(time[0] == g_lastBarTime && prev_calculated > 0)
      return(rates_total);

   // Only a successful evaluation consumes the bar; after a failed read the
   // next tick evaluates again, and the memory still blocks repeats.
   g_lastBarTime = Evaluate(time, high, low) ? time[0] : (datetime)0;

   // After the live evaluation, so A and B have just been read without error
   // and the live state is already settled for this bar.
   if(g_historyPending && g_lastBarTime != 0)
     {
      g_historyPending = false;
      MarkHistory(rates_total, time, high, low);
     }
   return(rates_total);
  }
