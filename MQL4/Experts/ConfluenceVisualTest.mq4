//+------------------------------------------------------------------+
//| ConfluenceVisualTest.mq4                                         |
//| Places no orders. It exists only to run the indicators in the    |
//| Strategy Tester. The MQL4 reference (HideTestIndicators page)    |
//| says "only those indicators can be drawn in the testing chart    |
//| that are directly called from the expert under test". Indicators |
//| called through ConfluenceAlert are not called directly, so A and |
//| B are called here as well. That all three appear on the tester   |
//| chart is expected from that sentence, to be confirmed in T4.     |
//+------------------------------------------------------------------+
#property strict
#property description "Runs SwingArrows, RsiDivergence and ConfluenceAlert in the visual tester. No trading."

void OnTick()
  {
   // Return values are not needed: the calls are what let the tester draw them.
   iCustom(NULL, 0, "SwingArrows", 0, 1);
   iCustom(NULL, 0, "RsiDivergence", 0, 1);
   iCustom(NULL, 0, "ConfluenceAlert", 0, 1);
  }
