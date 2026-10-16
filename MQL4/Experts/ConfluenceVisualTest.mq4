//+------------------------------------------------------------------+
//| ConfluenceVisualTest.mq4                                         |
//| Places no orders. It exists only to run the indicators in the    |
//| Strategy Tester: the MQL4 reference says that only indicators    |
//| called directly from the tested expert are drawn on the testing  |
//| chart (HideTestIndicators page). Indicators called through       |
//| ConfluenceAlert are not called directly, so A and B are called   |
//| here as well to make their arrows visible next to the markers.   |
//+------------------------------------------------------------------+
#property strict
#property description "Draws SwingArrows, RsiDivergence and ConfluenceAlert in the visual tester. No trading."

void OnTick()
  {
   // Return values are not needed: the calls are what make the tester draw them.
   iCustom(NULL, 0, "SwingArrows", 0, 1);
   iCustom(NULL, 0, "RsiDivergence", 0, 1);
   iCustom(NULL, 0, "ConfluenceAlert", 0, 1);
  }
