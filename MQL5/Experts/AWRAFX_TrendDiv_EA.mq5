//+------------------------------------------------------------------+
//|  AWRAFX_TrendDiv_EA.mq5                                          |
//|  Version : 1.0.0                                                 |
//|  Author  : AWRAFX                                                |
//|  Description: H1 Trendline Divergence Breakout Expert Advisor    |
//|               Stages: H1 Divergence → CHoCH → M5 Retest/Reclaim |
//|               → M5 Micro-BOS → Entry/Score → KPI                |
//+------------------------------------------------------------------+
#property copyright "AWRAFX"
#property link      ""
#property version   "1.00"
#property strict

//--- Input Parameters
input string   InpSymbols        = "XAUUSD";   // Comma-separated symbols
input int      InpRSI_Period     = 14;          // RSI Period
input int      InpEMA_Period     = 200;         // EMA Period
input int      InpATR_Period     = 14;          // ATR Period
input int      InpPivotBars      = 5;           // Bars each side for pivot
input double   InpMinRSIDelta    = 3.0;         // Min RSI delta for divergence
input int      InpMinDivSpan     = 5;           // Min bars between pivots
input int      InpMaxDivSpan     = 50;          // Max bars between pivots
input double   InpTrendATRMult   = 2.0;         // ATR multiplier for trend strength
input int      InpMinScore       = 60;          // Minimum score for signal
input double   InpMaxSpread      = 50;          // Max spread in points
input bool     InpWriteCSV       = true;        // Write audit CSV

//--- CHoCH Stage Input Parameters
input int      InpCHoCHTimeout   = 20;          // Max H1 bars to wait for CHoCH
input double   InpCHoCHTolATR    = 0.05;        // CHoCH tolerance as fraction of ATR (small buffer)

//--- M5 Retest Stage Input Parameters
input int      InpRetestTimeout  = 120;         // Max M5 bars to wait for retest (120 = ~10 hours)
input double   InpRetestTolATR   = 0.10;        // Retest touch zone tolerance as fraction of M5 ATR

//--- M5 Micro-BOS Stage Input Parameters
input int      InpMicroBOSTimeout = 60;         // Max M5 bars to wait for micro-BOS
input int      InpMicroPivotBars  = 3;          // Bars each side for M5 micro pivot detection

//--- Entry Engine & Risk Management Input Parameters
input double   InpRiskPercent      = 1.0;       // Risk per trade in %
input double   InpSL_Buffer_ATR_M5 = 0.5;      // SL buffer as fraction of M5 ATR
input double   InpMaxSL_ATR_H1     = 3.0;      // Reject entry if SL > this multiple of H1 ATR
input double   InpMinRR            = 1.5;       // Minimum room-to-move ratio vs SL
input double   InpTP1_ATR_H1       = 1.5;      // TP1 multiple of H1 ATR
input double   InpTP2_ATR_H1       = 2.5;      // TP2 multiple of H1 ATR
input double   InpTP3_ATR_H1       = 4.0;      // TP3 multiple of H1 ATR
input bool     InpUsePartialTP     = true;      // Enable partial closes
input double   InpTP1_ClosePct     = 0.40;     // Fraction to close at TP1
input double   InpTP2_ClosePct     = 0.30;     // Fraction to close at TP2
input double   InpTP3_ClosePct     = 0.30;     // Fraction to close at TP3
input int      InpMagicNumber      = 20250301; // EA magic number
input int      InpSlippage         = 10;       // Max price slippage in points

//--- Session & Environment Filters
input bool     InpUseSessionFilter   = true;   // Enable session filter
input int      InpSessionStartHour   = 7;      // Session start hour (broker/server time)
input int      InpSessionStartMin    = 0;      // Session start minute
input int      InpSessionEndHour     = 20;     // Session end hour (broker/server time)
input int      InpSessionEndMin      = 0;      // Session end minute
input bool     InpUseFridayCutoff    = true;   // No new entries after Friday cutoff
input int      InpFridayCutoffHour   = 18;     // Friday cutoff hour (broker/server time)
input double   InpEntryMaxSpread     = 40;     // Max spread at entry (points) — re-checked before OrderSend
input bool     InpUseVolatilityGate  = true;   // Enable ATR floor/ceiling gate
input double   InpATR_H1_FloorMult  = 0.3;    // Min ATR_H1 as fraction of 20-bar ATR average (reject if too quiet)
input double   InpATR_H1_CeilMult   = 3.0;    // Max ATR_H1 as fraction of 20-bar ATR average (reject if too volatile)

//--- Signal State Machine
enum ESignalState
{
   STATE_SCAN_DIV,      // Scanning for H1 divergence
   STATE_WAIT_CHOCH,    // Waiting for CHoCH confirmation
   STATE_WAIT_RETEST,   // Waiting for M5 retest/reclaim
   STATE_WAIT_MICROBOS, // Waiting for M5 micro-BOS
   STATE_READY_ENTRY,   // Entry criteria met
   STATE_MANAGE_TRADE,  // Trade is open, managing position
   STATE_IDLE           // Idle / paused
};

//--- Divergence type
enum EDivType
{
   DIV_NONE,
   DIV_REG_BULL,   // Regular Bullish: price LL, RSI HL
   DIV_REG_BEAR,   // Regular Bearish: price HH, RSI LH
   DIV_HID_BULL,   // Hidden Bullish:  price HL, RSI LL
   DIV_HID_BEAR    // Hidden Bearish:  price LH, RSI HH
};

//--- Per-symbol signal context (all traceability fields)
struct SSignalContext
{
   // Identity
   string         Symbol;
   string         Bias;           // BULL or BEAR
   int            Digits;
   double         Point;
   int            SignalID;

   // H1 Divergence
   EDivType       DivType;
   datetime       H1_Pivot1_Time;
   double         H1_Pivot1_Price;
   double         H1_Pivot1_RSI;
   datetime       H1_Pivot2_Time;
   double         H1_Pivot2_Price;
   double         H1_Pivot2_RSI;
   double         H1_Div_RSIDelta;
   int            H1_Div_SpanBars;

   // CHoCH
   datetime       H1_CHoCH_Time;
   double         H1_CHoCH_Close;
   double         TriggerLevel;
   double         InvalidationLevel;

   // Regime
   double         EMA200_H1;
   double         ATR_H1;
   bool           TrendStrongFlag;
   bool           RegimeReject;

   // M5
   datetime       M5_Touch_Time;
   datetime       M5_Reclaim_Time;
   double         M5_MicroLevel;
   datetime       M5_MicroBOS_Time;

   // Entry
   datetime       Entry_Time;
   double         Entry_Price;

   // Score
   double         Score_Total;
   int            MinScore;
   double         Score_DivStrength;
   double         Score_PivotSignificance;
   double         Score_RegimeQuality;
   double         Score_RoomToMove;

   // KPI
   int            KPI_LookaheadBarsM5;
   string         Result;
   double         MAE_R;
   double         MFE_R;

   // Meta
   double         Spread_Points;
   double         Tol_Price;
   string         Notes;
   string         ReasonCode;
   string         ReasonText;
};

//--- Per-symbol runtime data
struct SSymbolData
{
   string         Symbol;
   ESignalState   State;
   datetime       LastBarTimeH1;
   datetime       LastBarTimeM5;

   // Indicator handles — H1
   int            hRSI_H1;
   int            hEMA_H1;
   int            hATR_H1;

   // Indicator handles — M5
   int            hRSI_M5;
   int            hEMA_M5;
   int            hATR_M5;

   // Current signal context
   SSignalContext Ctx;

   // CHoCH wait tracking
   datetime CHoCH_WaitStartBarTime; // H1 bar time when STATE_WAIT_CHOCH was entered
   int      CHoCH_BarsWaited;       // Counter of H1 bars waited so far

   // M5 Retest tracking
   bool     M5_TouchDetected;       // Whether M5 wick touch of TriggerLevel zone has been detected
   int      Retest_BarsWaited;      // Counter of M5 bars waited in STATE_WAIT_RETEST

   // M5 Micro-BOS tracking
   int      MicroBOS_BarsWaited;    // Counter of M5 bars waited in STATE_WAIT_MICROBOS
   datetime MicroBOS_StartTime;     // M5 bar time when STATE_WAIT_MICROBOS was entered

   // Position tracking
   ulong  PositionTicket;       // Ticket of the open trade
   double PositionEntryPrice;   // Entry price
   double PositionOrigVolume;   // Original volume at entry (for partial TP sizing)
   double PositionSL;           // Current stop-loss
   double PositionTP1;          // First partial TP level
   double PositionTP2;          // Second partial TP level
   double PositionTP3;          // Final TP level
   bool   TP1_Done;             // Has TP1 partial close been executed?
   bool   TP2_Done;             // Has TP2 partial close been executed?
   bool   TP3_Done;             // Has TP3 partial close been executed?

   // MAE/MFE tracking
   double TradeMAE;             // Maximum adverse excursion in price (worst drawdown from entry)
   double TradeMFE;             // Maximum favorable excursion in price (best unrealized profit from entry)
};

//--- Globals
SSymbolData  g_Symbols[];          // Array of symbol data
int          g_SymbolCount  = 0;   // Number of active symbols
string       g_RunID        = "";  // EA start timestamp as string
int          g_CSVHandle    = INVALID_HANDLE; // CSV file handle

//--- Global KPI counters
int    g_TotalSignals = 0;
int    g_Wins         = 0;
int    g_Losses       = 0;
int    g_Breakeven    = 0;
double g_SumMAE_R     = 0.0;
double g_SumMFE_R     = 0.0;
double g_SumProfit    = 0.0;
double g_SumLoss      = 0.0;

//--- CSV header (locked per TRACEABILITY_RULES.md)
const string CSV_HEADER =
   "RowType,RunID,SignalID,Symbol,Bias,Digits,Point,"
   "DivType,"
   "H1_Pivot1_Time,H1_Pivot1_Price,H1_Pivot1_RSI,"
   "H1_Pivot2_Time,H1_Pivot2_Price,H1_Pivot2_RSI,"
   "H1_Div_RSIDelta,H1_Div_SpanBars,"
   "H1_CHoCH_Time,H1_CHoCH_Close,TriggerLevel,InvalidationLevel,"
   "EMA200_H1,ATR_H1,TrendStrongFlag,RegimeReject,"
   "M5_Touch_Time,M5_Reclaim_Time,M5_MicroLevel,M5_MicroBOS_Time,"
   "Entry_Time,Entry_Price,"
   "Score_Total,MinScore,Score_DivStrength,Score_PivotSignificance,"
   "Score_RegimeQuality,Score_RoomToMove,"
   "KPI_LookaheadBarsM5,Result,MAE_R,MFE_R,"
   "Spread_Points,Tol_Price,Notes,ReasonCode,ReasonText";

//+------------------------------------------------------------------+
//|  Helper: convert bool to "1"/"0"                                 |
//+------------------------------------------------------------------+
string BoolToStr(bool v) { return v ? "1" : "0"; }

//+------------------------------------------------------------------+
//|  Helper: convert EDivType to string                              |
//+------------------------------------------------------------------+
string DivTypeToStr(EDivType dt)
{
   switch(dt)
   {
      case DIV_REG_BULL: return "REG_BULL";
      case DIV_REG_BEAR: return "REG_BEAR";
      case DIV_HID_BULL: return "HID_BULL";
      case DIV_HID_BEAR: return "HID_BEAR";
      default:           return "NONE";
   }
}

//+------------------------------------------------------------------+
//|  Parse comma-separated symbol string                             |
//+------------------------------------------------------------------+
int ParseSymbols(const string raw, string &out[])
{
   string tmp = raw;
   StringTrimRight(tmp);
   StringTrimLeft(tmp);
   int cnt = StringSplit(tmp, ',', out);
   for(int i = 0; i < cnt; i++)
   {
      StringTrimLeft(out[i]);
      StringTrimRight(out[i]);
   }
   return cnt;
}

//+------------------------------------------------------------------+
//|  Initialize indicator handles for one symbol                     |
//+------------------------------------------------------------------+
bool InitHandles(SSymbolData &sd)
{
   sd.hRSI_H1 = iRSI(sd.Symbol, PERIOD_H1, InpRSI_Period, PRICE_CLOSE);
   sd.hEMA_H1 = iMA(sd.Symbol,  PERIOD_H1, InpEMA_Period,  0, MODE_EMA, PRICE_CLOSE);
   sd.hATR_H1 = iATR(sd.Symbol, PERIOD_H1, InpATR_Period);
   sd.hRSI_M5 = iRSI(sd.Symbol, PERIOD_M5, InpRSI_Period, PRICE_CLOSE);
   sd.hEMA_M5 = iMA(sd.Symbol,  PERIOD_M5, InpEMA_Period,  0, MODE_EMA, PRICE_CLOSE);
   sd.hATR_M5 = iATR(sd.Symbol, PERIOD_M5, InpATR_Period);

   if(sd.hRSI_H1 == INVALID_HANDLE || sd.hEMA_H1 == INVALID_HANDLE ||
      sd.hATR_H1 == INVALID_HANDLE || sd.hRSI_M5 == INVALID_HANDLE ||
      sd.hEMA_M5 == INVALID_HANDLE || sd.hATR_M5 == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles for ", sd.Symbol);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//|  Release indicator handles for one symbol                        |
//+------------------------------------------------------------------+
void ReleaseHandles(SSymbolData &sd)
{
   if(sd.hRSI_H1 != INVALID_HANDLE) { IndicatorRelease(sd.hRSI_H1); sd.hRSI_H1 = INVALID_HANDLE; }
   if(sd.hEMA_H1 != INVALID_HANDLE) { IndicatorRelease(sd.hEMA_H1); sd.hEMA_H1 = INVALID_HANDLE; }
   if(sd.hATR_H1 != INVALID_HANDLE) { IndicatorRelease(sd.hATR_H1); sd.hATR_H1 = INVALID_HANDLE; }
   if(sd.hRSI_M5 != INVALID_HANDLE) { IndicatorRelease(sd.hRSI_M5); sd.hRSI_M5 = INVALID_HANDLE; }
   if(sd.hEMA_M5 != INVALID_HANDLE) { IndicatorRelease(sd.hEMA_M5); sd.hEMA_M5 = INVALID_HANDLE; }
   if(sd.hATR_M5 != INVALID_HANDLE) { IndicatorRelease(sd.hATR_M5); sd.hATR_M5 = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//|  Initialize the CSV file (write header if new file)             |
//+------------------------------------------------------------------+
bool InitCSV()
{
   if(!InpWriteCSV) return true;

   // Try to open existing file for append
   g_CSVHandle = FileOpen("FinalSpec_Audit.csv",
                          FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ);
   if(g_CSVHandle == INVALID_HANDLE)
   {
      // Create new file
      g_CSVHandle = FileOpen("FinalSpec_Audit.csv",
                             FILE_WRITE | FILE_CSV | FILE_SHARE_READ);
      if(g_CSVHandle == INVALID_HANDLE)
      {
         Print("ERROR: Cannot create FinalSpec_Audit.csv, error ", GetLastError());
         return false;
      }
      // Write header to brand new file
      FileWrite(g_CSVHandle, CSV_HEADER);
   }
   else
   {
      // File exists — seek to end for appending
      FileSeek(g_CSVHandle, 0, SEEK_END);
   }
   return true;
}

//+------------------------------------------------------------------+
//|  Write a CSV row (SIGNAL or REJECT)                              |
//+------------------------------------------------------------------+
void WriteCSVRow(const string rowType, const SSignalContext &ctx)
{
   if(!InpWriteCSV || g_CSVHandle == INVALID_HANDLE) return;

   string line =
      rowType                                              + "," +
      g_RunID                                             + "," +
      IntegerToString(ctx.SignalID)                       + "," +
      ctx.Symbol                                          + "," +
      ctx.Bias                                            + "," +
      IntegerToString(ctx.Digits)                         + "," +
      DoubleToString(ctx.Point, 10)                       + "," +
      DivTypeToStr(ctx.DivType)                           + "," +
      TimeToString(ctx.H1_Pivot1_Time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(ctx.H1_Pivot1_Price, ctx.Digits)     + "," +
      DoubleToString(ctx.H1_Pivot1_RSI,  2)               + "," +
      TimeToString(ctx.H1_Pivot2_Time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(ctx.H1_Pivot2_Price, ctx.Digits)     + "," +
      DoubleToString(ctx.H1_Pivot2_RSI,  2)               + "," +
      DoubleToString(ctx.H1_Div_RSIDelta, 2)              + "," +
      IntegerToString(ctx.H1_Div_SpanBars)                + "," +
      TimeToString(ctx.H1_CHoCH_Time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(ctx.H1_CHoCH_Close, ctx.Digits)      + "," +
      DoubleToString(ctx.TriggerLevel,   ctx.Digits)      + "," +
      DoubleToString(ctx.InvalidationLevel, ctx.Digits)   + "," +
      DoubleToString(ctx.EMA200_H1, ctx.Digits)           + "," +
      DoubleToString(ctx.ATR_H1, ctx.Digits)              + "," +
      BoolToStr(ctx.TrendStrongFlag)                      + "," +
      BoolToStr(ctx.RegimeReject)                         + "," +
      TimeToString(ctx.M5_Touch_Time, TIME_DATE|TIME_MINUTES) + "," +
      TimeToString(ctx.M5_Reclaim_Time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(ctx.M5_MicroLevel, ctx.Digits)       + "," +
      TimeToString(ctx.M5_MicroBOS_Time, TIME_DATE|TIME_MINUTES) + "," +
      TimeToString(ctx.Entry_Time, TIME_DATE|TIME_MINUTES) + "," +
      DoubleToString(ctx.Entry_Price, ctx.Digits)          + "," +
      DoubleToString(ctx.Score_Total, 2)                   + "," +
      IntegerToString(ctx.MinScore)                        + "," +
      DoubleToString(ctx.Score_DivStrength,      2)        + "," +
      DoubleToString(ctx.Score_PivotSignificance,2)        + "," +
      DoubleToString(ctx.Score_RegimeQuality,    2)        + "," +
      DoubleToString(ctx.Score_RoomToMove,       2)        + "," +
      IntegerToString(ctx.KPI_LookaheadBarsM5)             + "," +
      ctx.Result                                           + "," +
      DoubleToString(ctx.MAE_R, 4)                         + "," +
      DoubleToString(ctx.MFE_R, 4)                         + "," +
      DoubleToString(ctx.Spread_Points, 1)                 + "," +
      DoubleToString(ctx.Tol_Price, ctx.Digits)            + "," +
      ctx.Notes                                            + "," +
      ctx.ReasonCode                                       + "," +
      ctx.ReasonText;

   FileWrite(g_CSVHandle, line);
   FileFlush(g_CSVHandle);
}

//+------------------------------------------------------------------+
//|  Reset a signal context to empty/default values                  |
//+------------------------------------------------------------------+
void ResetContext(SSignalContext &ctx, const string symbol)
{
   ctx.Symbol           = symbol;
   ctx.Bias             = "";
   ctx.Digits           = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   ctx.Point            = SymbolInfoDouble(symbol, SYMBOL_POINT);
   ctx.DivType          = DIV_NONE;
   ctx.H1_Pivot1_Time   = 0;
   ctx.H1_Pivot1_Price  = 0;
   ctx.H1_Pivot1_RSI    = 0;
   ctx.H1_Pivot2_Time   = 0;
   ctx.H1_Pivot2_Price  = 0;
   ctx.H1_Pivot2_RSI    = 0;
   ctx.H1_Div_RSIDelta  = 0;
   ctx.H1_Div_SpanBars  = 0;
   ctx.H1_CHoCH_Time    = 0;
   ctx.H1_CHoCH_Close   = 0;
   ctx.TriggerLevel     = 0;
   ctx.InvalidationLevel= 0;
   ctx.EMA200_H1        = 0;
   ctx.ATR_H1           = 0;
   ctx.TrendStrongFlag  = false;
   ctx.RegimeReject     = false;
   ctx.M5_Touch_Time    = 0;
   ctx.M5_Reclaim_Time  = 0;
   ctx.M5_MicroLevel    = 0;
   ctx.M5_MicroBOS_Time = 0;
   ctx.Entry_Time       = 0;
   ctx.Entry_Price      = 0;
   ctx.Score_Total      = 0;
   ctx.MinScore         = InpMinScore;
   ctx.Score_DivStrength      = 0;
   ctx.Score_PivotSignificance= 0;
   ctx.Score_RegimeQuality    = 0;
   ctx.Score_RoomToMove       = 0;
   ctx.KPI_LookaheadBarsM5    = 0;
   ctx.Result           = "";
   ctx.MAE_R            = 0;
   ctx.MFE_R            = 0;
   ctx.Spread_Points    = 0;
   ctx.Tol_Price        = 0;
   ctx.Notes            = "";
   ctx.ReasonCode       = "";
   ctx.ReasonText       = "";
}

//+------------------------------------------------------------------+
//|  Get a single indicator buffer value (index from current bar)    |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int shift)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) return EMPTY_VALUE;
   return buf[0];
}

//+------------------------------------------------------------------+
//|  Detect swing pivots on H1 using ZigZag-style logic              |
//|  Returns up to maxPivots pivot bars (index 0 = most recent)      |
//|  pivotType: 1 = swing high, -1 = swing low                      |
//+------------------------------------------------------------------+
int FindPivots(const string symbol,
               ENUM_TIMEFRAMES tf,
               int pivotType,
               int barsEachSide,
               int lookback,
               int maxPivots,
               int &pivotBarIdx[],
               double &pivotPrice[])
{
   int found = 0;
   ArrayResize(pivotBarIdx, maxPivots);
   ArrayResize(pivotPrice,  maxPivots);

   // We need barsEachSide on both sides, start from barsEachSide
   int startBar = barsEachSide;
   int endBar   = lookback - barsEachSide - 1;
   if(endBar < startBar) return 0;

   for(int b = startBar; b <= endBar && found < maxPivots; b++)
   {
      double centerHigh = iHigh(symbol, tf, b);
      double centerLow  = iLow(symbol,  tf, b);
      bool   isPivot    = true;

      if(pivotType == 1) // Swing High: all bars on each side must be lower
      {
         for(int k = 1; k <= barsEachSide && isPivot; k++)
         {
            if(iHigh(symbol, tf, b - k) >= centerHigh) isPivot = false;
            if(iHigh(symbol, tf, b + k) >= centerHigh) isPivot = false;
         }
         if(isPivot)
         {
            pivotBarIdx[found] = b;
            pivotPrice[found]  = centerHigh;
            found++;
         }
      }
      else // Swing Low: all bars on each side must be higher
      {
         for(int k = 1; k <= barsEachSide && isPivot; k++)
         {
            if(iLow(symbol, tf, b - k) <= centerLow) isPivot = false;
            if(iLow(symbol, tf, b + k) <= centerLow) isPivot = false;
         }
         if(isPivot)
         {
            pivotBarIdx[found] = b;
            pivotPrice[found]  = centerLow;
            found++;
         }
      }
   }
   return found;
}

//+------------------------------------------------------------------+
//|  Score: DivStrength based on RSI delta (max 25)                  |
//+------------------------------------------------------------------+
double ScoreDivStrength(double rsiDelta)
{
   // Map 0..30 RSI delta to 0..25 score (linear, capped)
   double score = (rsiDelta / 30.0) * 25.0;
   if(score > 25.0) score = 25.0;
   if(score <  0.0) score =  0.0;
   return score;
}

//+------------------------------------------------------------------+
//|  Score: PivotSignificance based on swing depth vs ATR (max 25)   |
//+------------------------------------------------------------------+
double ScorePivotSignificance(double swingDepth, double atr)
{
   if(atr <= 0.0) return 0.0;
   double ratio = swingDepth / atr;
   // >= 3 ATRs = full score
   double score = (ratio / 3.0) * 25.0;
   if(score > 25.0) score = 25.0;
   if(score <  0.0) score =  0.0;
   return score;
}

//+------------------------------------------------------------------+
//|  Score: RegimeQuality — price near EMA = good (max 25)           |
//+------------------------------------------------------------------+
double ScoreRegimeQuality(double price, double ema200, double atr)
{
   if(atr <= 0.0) return 12.5; // neutral if ATR unavailable
   double dist = MathAbs(price - ema200) / atr;
   // Close to EMA (within 1 ATR) = max score; far away = lower score
   double score = 25.0 - (dist / 5.0) * 25.0;
   if(score > 25.0) score = 25.0;
   if(score <  0.0) score =  0.0;
   return score;
}

//+------------------------------------------------------------------+
//|  Score: RoomToMove — stub returning neutral 12.5 (max 25)        |
//|  Full implementation requires next structure level detection      |
//|  which is part of later pipeline stages.                         |
//+------------------------------------------------------------------+
double ScoreRoomToMove()
{
   return 12.5; // placeholder neutral value
}

//+------------------------------------------------------------------+
//|  Core: Stage 1 — Detect H1 Divergence for one symbol             |
//|  Returns true if a valid divergence was found and passes filters  |
//+------------------------------------------------------------------+
bool DetectH1Divergence(SSymbolData &sd)
{
   SSignalContext &ctx = sd.Ctx;

   // --- Retrieve regime data (EMA200 and ATR on H1) ---
   double ema200 = GetIndicatorValue(sd.hEMA_H1, 1);
   double atr    = GetIndicatorValue(sd.hATR_H1, 1);

   if(ema200 == EMPTY_VALUE || atr == EMPTY_VALUE)
   {
      Print(ctx.Symbol, ": Regime indicators not ready");
      return false;
   }

   ctx.EMA200_H1 = ema200;
   ctx.ATR_H1    = atr;

   // Current close price on H1
   double closeNow = iClose(ctx.Symbol, PERIOD_H1, 1);

   // Determine TrendStrongFlag
   double distFromEMA = MathAbs(closeNow - ema200);
   ctx.TrendStrongFlag = (distFromEMA > InpTrendATRMult * atr);

   // --- Need enough bars for pivot detection ---
   int lookback = InpMaxDivSpan + InpPivotBars * 2 + 5;
   int barsAvail = Bars(ctx.Symbol, PERIOD_H1);
   if(barsAvail < lookback)
   {
      Print(ctx.Symbol, ": Not enough H1 bars (", barsAvail, " < ", lookback, ")");
      return false;
   }

   // --- Read RSI buffer ---
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   int rsiCopied = CopyBuffer(sd.hRSI_H1, 0, 0, lookback, rsiBuffer);
   if(rsiCopied < lookback)
   {
      Print(ctx.Symbol, ": RSI buffer not ready");
      return false;
   }

   // --- Find two most recent swing lows (for bullish divergence types) ---
   int   swLowIdx[];
   double swLowPrc[];
   int swLowCount = FindPivots(ctx.Symbol, PERIOD_H1, -1,
                                InpPivotBars, lookback,
                                2, swLowIdx, swLowPrc);

   // --- Find two most recent swing highs (for bearish divergence types) ---
   int   swHighIdx[];
   double swHighPrc[];
   int swHighCount = FindPivots(ctx.Symbol, PERIOD_H1, 1,
                                 InpPivotBars, lookback,
                                 2, swHighIdx, swHighPrc);

   // --- Check all four divergence types ---
   EDivType divFound   = DIV_NONE;
   int      p1BarIdx   = 0, p2BarIdx = 0;
   double   p1Price    = 0, p2Price  = 0;

   // ---- Regular Bullish: Price LL, RSI HL ----
   if(swLowCount >= 2)
   {
      int   i1 = swLowIdx[0], i2 = swLowIdx[1]; // i1 = more recent
      double prc1 = swLowPrc[0], prc2 = swLowPrc[1];
      double rsi1 = rsiBuffer[i1], rsi2 = rsiBuffer[i2];
      int    span = i2 - i1; // bars between pivots (i2 is older, larger index)

      if(span >= InpMinDivSpan && span <= InpMaxDivSpan)
      {
         if(prc1 < prc2 &&               // Price: lower low
            rsi1 > rsi2 &&               // RSI: higher low
            (rsi1 - rsi2) >= InpMinRSIDelta)
         {
            divFound = DIV_REG_BULL;
            p1BarIdx = i2; p2BarIdx = i1; // p1 = older pivot
            p1Price  = prc2; p2Price = prc1;
         }
      }
   }

   // ---- Regular Bearish: Price HH, RSI LH ----
   if(divFound == DIV_NONE && swHighCount >= 2)
   {
      int   i1 = swHighIdx[0], i2 = swHighIdx[1];
      double prc1 = swHighPrc[0], prc2 = swHighPrc[1];
      double rsi1 = rsiBuffer[i1], rsi2 = rsiBuffer[i2];
      int    span = i2 - i1;

      if(span >= InpMinDivSpan && span <= InpMaxDivSpan)
      {
         if(prc1 > prc2 &&               // Price: higher high
            rsi1 < rsi2 &&               // RSI: lower high
            (rsi2 - rsi1) >= InpMinRSIDelta)
         {
            divFound = DIV_REG_BEAR;
            p1BarIdx = i2; p2BarIdx = i1;
            p1Price  = prc2; p2Price = prc1;
         }
      }
   }

   // ---- Hidden Bullish: Price HL, RSI LL ----
   if(divFound == DIV_NONE && swLowCount >= 2)
   {
      int   i1 = swLowIdx[0], i2 = swLowIdx[1];
      double prc1 = swLowPrc[0], prc2 = swLowPrc[1];
      double rsi1 = rsiBuffer[i1], rsi2 = rsiBuffer[i2];
      int    span = i2 - i1;

      if(span >= InpMinDivSpan && span <= InpMaxDivSpan)
      {
         if(prc1 > prc2 &&               // Price: higher low (HL)
            rsi1 < rsi2 &&               // RSI: lower low (LL)
            (rsi2 - rsi1) >= InpMinRSIDelta)
         {
            divFound = DIV_HID_BULL;
            p1BarIdx = i2; p2BarIdx = i1;
            p1Price  = prc2; p2Price = prc1;
         }
      }
   }

   // ---- Hidden Bearish: Price LH, RSI HH ----
   if(divFound == DIV_NONE && swHighCount >= 2)
   {
      int   i1 = swHighIdx[0], i2 = swHighIdx[1];
      double prc1 = swHighPrc[0], prc2 = swHighPrc[1];
      double rsi1 = rsiBuffer[i1], rsi2 = rsiBuffer[i2];
      int    span = i2 - i1;

      if(span >= InpMinDivSpan && span <= InpMaxDivSpan)
      {
         if(prc1 < prc2 &&               // Price: lower high (LH)
            rsi1 > rsi2 &&               // RSI: higher high (HH)
            (rsi1 - rsi2) >= InpMinRSIDelta)
         {
            divFound = DIV_HID_BEAR;
            p1BarIdx = i2; p2BarIdx = i1;
            p1Price  = prc2; p2Price = prc1;
         }
      }
   }

   // --- No divergence found ---
   if(divFound == DIV_NONE)
   {
      ctx.ReasonCode = "REJECT_NO_DIVERGENCE";
      ctx.ReasonText = "No qualifying divergence pattern found on H1";
      WriteCSVRow("REJECT", ctx);
      return false;
   }

   // --- Populate divergence fields in context ---
   ctx.DivType         = divFound;
   ctx.Bias            = (divFound == DIV_REG_BULL || divFound == DIV_HID_BULL) ? "BULL" : "BEAR";
   ctx.H1_Pivot1_Time  = iTime(ctx.Symbol, PERIOD_H1, p1BarIdx);
   ctx.H1_Pivot1_Price = p1Price;
   ctx.H1_Pivot1_RSI   = rsiBuffer[p1BarIdx];
   ctx.H1_Pivot2_Time  = iTime(ctx.Symbol, PERIOD_H1, p2BarIdx);
   ctx.H1_Pivot2_Price = p2Price;
   ctx.H1_Pivot2_RSI   = rsiBuffer[p2BarIdx];
   ctx.H1_Div_RSIDelta = MathAbs(ctx.H1_Pivot2_RSI - ctx.H1_Pivot1_RSI);
   ctx.H1_Div_SpanBars = MathAbs(p2BarIdx - p1BarIdx);

   // --- Spread filter ---
   long spreadPts = SymbolInfoInteger(ctx.Symbol, SYMBOL_SPREAD);
   ctx.Spread_Points = (double)spreadPts;
   if(ctx.Spread_Points > InpMaxSpread)
   {
      ctx.ReasonCode = "REJECT_SPREAD_TOO_HIGH";
      ctx.ReasonText = "Spread " + DoubleToString(ctx.Spread_Points, 1) +
                       " > max " + DoubleToString(InpMaxSpread, 1);
      WriteCSVRow("REJECT", ctx);
      return false;
   }

   // --- Regime filter ---
   bool isBullDiv = (ctx.Bias == "BULL");
   if(ctx.TrendStrongFlag)
   {
      bool trendIsBull = (closeNow > ema200);
      // Reject if divergence is against strong trend
      if(isBullDiv && !trendIsBull)
      {
         ctx.RegimeReject = true;
         ctx.ReasonCode   = "REJECT_REGIME_STRONG_TREND";
         ctx.ReasonText   = "Strong bearish trend rejects bullish divergence";
         WriteCSVRow("REJECT", ctx);
         return false;
      }
      if(!isBullDiv && trendIsBull)
      {
         ctx.RegimeReject = true;
         ctx.ReasonCode   = "REJECT_REGIME_STRONG_TREND";
         ctx.ReasonText   = "Strong bullish trend rejects bearish divergence";
         WriteCSVRow("REJECT", ctx);
         return false;
      }
   }
   ctx.RegimeReject = false;

   // --- Scoring ---
   // Swing depth for PivotSignificance: distance between the two pivot prices
   double swingDepth = MathAbs(p1Price - p2Price);
   ctx.Score_DivStrength       = ScoreDivStrength(ctx.H1_Div_RSIDelta);
   ctx.Score_PivotSignificance = ScorePivotSignificance(swingDepth, atr);
   ctx.Score_RegimeQuality     = ScoreRegimeQuality(closeNow, ema200, atr);
   ctx.Score_RoomToMove        = ScoreRoomToMove();
   ctx.Score_Total             = ctx.Score_DivStrength +
                                 ctx.Score_PivotSignificance +
                                 ctx.Score_RegimeQuality +
                                 ctx.Score_RoomToMove;
   ctx.MinScore                = InpMinScore;

   if(ctx.Score_Total < (double)InpMinScore)
   {
      ctx.ReasonCode = "REJECT_SCORE_BELOW_MIN";
      ctx.ReasonText = "Score " + DoubleToString(ctx.Score_Total, 1) +
                       " < min " + IntegerToString(InpMinScore);
      WriteCSVRow("REJECT", ctx);
      return false;
   }

   // --- Divergence valid: write SIGNAL row and advance state ---
   ctx.SignalID++;
   WriteCSVRow("SIGNAL", ctx);
   Print(ctx.Symbol, " [", DivTypeToStr(divFound), "] Divergence detected. "
         "RSI delta=", DoubleToString(ctx.H1_Div_RSIDelta, 2),
         " Score=", DoubleToString(ctx.Score_Total, 1));
   return true;
}

//+------------------------------------------------------------------+
//|  Stage 2: Set up CHoCH levels when first entering WAIT_CHOCH     |
//|  Called once on the bar where divergence was confirmed           |
//+------------------------------------------------------------------+
void SetupCHoCHLevels(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Find H1 bar index for Pivot1 (the older divergence pivot)
   int pivot1Bar = iBarShift(ctx.Symbol, PERIOD_H1, ctx.H1_Pivot1_Time, false);
   if(pivot1Bar < 0)
   {
      Print(ctx.Symbol, " SetupCHoCHLevels: iBarShift failed for Pivot1 time — skipping CHoCH setup");
      return;
   }
   if(pivot1Bar < 1) pivot1Bar = 1; // safety: at least bar 1

   if(ctx.Bias == "BULL")
   {
      // TriggerLevel = highest HIGH between bar 1 (last closed) and Pivot1 bar inclusive
      // When price CLOSES above this level it is a bullish CHoCH
      double highestHigh = 0.0;
      for(int b = 1; b <= pivot1Bar; b++)
      {
         double h = iHigh(ctx.Symbol, PERIOD_H1, b);
         if(h > highestHigh) highestHigh = h;
      }
      ctx.TriggerLevel      = highestHigh;
      ctx.InvalidationLevel = ctx.H1_Pivot2_Price; // recent swing low invalidates bull bias
   }
   else // BEAR
   {
      // TriggerLevel = lowest LOW between bar 1 (last closed) and Pivot1 bar inclusive
      // When price CLOSES below this level it is a bearish CHoCH
      double lowestLow = DBL_MAX;
      for(int b = 1; b <= pivot1Bar; b++)
      {
         double l = iLow(ctx.Symbol, PERIOD_H1, b);
         if(l < lowestLow) lowestLow = l;
      }
      ctx.TriggerLevel      = lowestLow;
      ctx.InvalidationLevel = ctx.H1_Pivot2_Price; // recent swing high invalidates bear bias
   }

   // Initialise wait tracking
   sd.CHoCH_WaitStartBarTime = iTime(ctx.Symbol, PERIOD_H1, 0);
   sd.CHoCH_BarsWaited       = 0;

   Print(ctx.Symbol, " CHoCH setup — Bias=", ctx.Bias,
         " Trigger=", DoubleToString(ctx.TriggerLevel, ctx.Digits),
         " Invalidation=", DoubleToString(ctx.InvalidationLevel, ctx.Digits));
}

//+------------------------------------------------------------------+
//|  Stage 2: Check CHoCH on each new H1 bar (STATE_WAIT_CHOCH)      |
//|                                                                  |
//|  CRITICAL RULE: only the candle CLOSE counts — no wick, no       |
//|  body/range ratio. Mesti body closed candle — bukan wick.        |
//+------------------------------------------------------------------+
void CheckCHoCH(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Count this bar
   sd.CHoCH_BarsWaited++;

   double closeH1 = iClose(ctx.Symbol, PERIOD_H1, 1); // last fully closed bar

   // Refresh ATR; fall back to stored value if indicator not ready yet
   double atr = GetIndicatorValue(sd.hATR_H1, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0) atr = ctx.ATR_H1;
   double tolerance = InpCHoCHTolATR * atr;

   // --- 1. Timeout check ---
   if(sd.CHoCH_BarsWaited > InpCHoCHTimeout)
   {
      ctx.ReasonCode = "REJECT_NO_CHOCH";
      ctx.ReasonText = "Timeout after " + IntegerToString(sd.CHoCH_BarsWaited) + " bars";
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      sd.CHoCH_BarsWaited   = 0;
      sd.M5_TouchDetected   = false;
      sd.Retest_BarsWaited  = 0;
      sd.MicroBOS_BarsWaited= 0;
      sd.MicroBOS_StartTime = 0;
      sd.State = STATE_SCAN_DIV;
      return;
   }

   // --- 2. Invalidation check ---
   if(ctx.Bias == "BULL")
   {
      if(closeH1 < ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_CHOCH";
         ctx.ReasonText = "Invalidation: close " + DoubleToString(closeH1, ctx.Digits) +
                          " below " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID = prevID;
         sd.CHoCH_BarsWaited   = 0;
         sd.M5_TouchDetected   = false;
         sd.Retest_BarsWaited  = 0;
         sd.MicroBOS_BarsWaited= 0;
         sd.MicroBOS_StartTime = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }
   else // BEAR
   {
      if(closeH1 > ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_CHOCH";
         ctx.ReasonText = "Invalidation: close " + DoubleToString(closeH1, ctx.Digits) +
                          " above " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID = prevID;
         sd.CHoCH_BarsWaited   = 0;
         sd.M5_TouchDetected   = false;
         sd.Retest_BarsWaited  = 0;
         sd.MicroBOS_BarsWaited= 0;
         sd.MicroBOS_StartTime = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }

   // --- 3. CHoCH confirmation — CLOSE PRICE ONLY (body, not wick) ---
   bool chochConfirmed = false;
   if(ctx.Bias == "BULL")
   {
      // Body must close ABOVE TriggerLevel — wick alone does NOT count
      if(closeH1 > ctx.TriggerLevel + tolerance)
         chochConfirmed = true;
   }
   else // BEAR
   {
      // Body must close BELOW TriggerLevel — wick alone does NOT count
      if(closeH1 < ctx.TriggerLevel - tolerance)
         chochConfirmed = true;
   }

   if(chochConfirmed)
   {
      ctx.H1_CHoCH_Time  = iTime(ctx.Symbol, PERIOD_H1, 1);
      ctx.H1_CHoCH_Close = closeH1;

      if(ctx.Bias == "BULL")
         ctx.Notes = "CHoCH confirmed: close " + DoubleToString(closeH1, ctx.Digits) +
                     " > trigger " + DoubleToString(ctx.TriggerLevel, ctx.Digits);
      else
         ctx.Notes = "CHoCH confirmed: close " + DoubleToString(closeH1, ctx.Digits) +
                     " < trigger " + DoubleToString(ctx.TriggerLevel, ctx.Digits);

      WriteCSVRow("SIGNAL", ctx);
      Print(ctx.Symbol, " CHoCH confirmed. Close=", DoubleToString(closeH1, ctx.Digits),
            " Trigger=", DoubleToString(ctx.TriggerLevel, ctx.Digits),
            " Bars waited=", sd.CHoCH_BarsWaited);

      // Initialize M5 retest tracking before entering STATE_WAIT_RETEST
      sd.M5_TouchDetected  = false;
      sd.Retest_BarsWaited = 0;
      sd.State = STATE_WAIT_RETEST;
   }
}

//+------------------------------------------------------------------+
//|  Stage 3: Check M5 Retest/Reclaim on each new M5 bar             |
//|  (STATE_WAIT_RETEST)                                             |
//|                                                                  |
//|  CRITICAL RULE: Touch uses wick (High/Low) to detect the candle  |
//|  that reached the zone. Reclaim uses CLOSE ONLY — body must      |
//|  confirm. Mesti body closed candle — bukan wick.                 |
//+------------------------------------------------------------------+
void CheckM5Retest(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Count this M5 bar
   sd.Retest_BarsWaited++;

   double closeM5 = iClose(ctx.Symbol, PERIOD_M5, 1); // last fully closed M5 bar

   // Get M5 ATR for touch tolerance
   double atrM5 = GetIndicatorValue(sd.hATR_M5, 1);
   if(atrM5 == EMPTY_VALUE || atrM5 <= 0.0) atrM5 = ctx.ATR_H1 / 12.0; // fallback: H1 ATR / 12 (60 min / 5 min per M5 bar)
   double tolerance = InpRetestTolATR * atrM5;

   // --- 1. Timeout check ---
   if(sd.Retest_BarsWaited > InpRetestTimeout)
   {
      ctx.ReasonCode = "REJECT_TIMEOUT_WAIT_RETEST";
      ctx.ReasonText = "Retest timeout after " + IntegerToString(sd.Retest_BarsWaited) + " M5 bars";
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID           = prevID;
      sd.M5_TouchDetected    = false;
      sd.Retest_BarsWaited   = 0;
      sd.MicroBOS_BarsWaited = 0;
      sd.MicroBOS_StartTime  = 0;
      sd.State = STATE_SCAN_DIV;
      return;
   }

   // --- 2. Invalidation check (CLOSE ONLY — body must confirm) ---
   if(ctx.Bias == "BULL")
   {
      if(closeM5 < ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_RECLAIM";
         ctx.ReasonText = "M5 invalidation: close " + DoubleToString(closeM5, ctx.Digits) +
                          " below invalidation " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID           = prevID;
         sd.M5_TouchDetected    = false;
         sd.Retest_BarsWaited   = 0;
         sd.MicroBOS_BarsWaited = 0;
         sd.MicroBOS_StartTime  = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }
   else // BEAR
   {
      if(closeM5 > ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_RECLAIM";
         ctx.ReasonText = "M5 invalidation: close " + DoubleToString(closeM5, ctx.Digits) +
                          " above invalidation " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID           = prevID;
         sd.M5_TouchDetected    = false;
         sd.Retest_BarsWaited   = 0;
         sd.MicroBOS_BarsWaited = 0;
         sd.MicroBOS_StartTime  = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }

   if(!sd.M5_TouchDetected)
   {
      // --- 3. Touch detection via WICK ---
      // BULL: price pulls back DOWN — M5 Low must touch or go below TriggerLevel + tolerance
      // BEAR: price pulls back UP   — M5 High must touch or go above TriggerLevel - tolerance
      bool touched = false;
      if(ctx.Bias == "BULL")
         touched = (iLow(ctx.Symbol, PERIOD_M5, 1) <= ctx.TriggerLevel + tolerance);
      else
         touched = (iHigh(ctx.Symbol, PERIOD_M5, 1) >= ctx.TriggerLevel - tolerance);

      if(touched)
      {
         sd.M5_TouchDetected = true;
         ctx.M5_Touch_Time   = iTime(ctx.Symbol, PERIOD_M5, 1);
         ctx.Notes = ctx.Notes + " | M5_Touch@" +
                     TimeToString(ctx.M5_Touch_Time, TIME_DATE|TIME_MINUTES);
         Print(ctx.Symbol, " M5 Touch detected. Trigger=",
               DoubleToString(ctx.TriggerLevel, ctx.Digits),
               " Bar=", TimeToString(ctx.M5_Touch_Time, TIME_DATE|TIME_MINUTES));
         // Reclaim is checked on subsequent bars (the NEXT candle must confirm)
      }
   }
   else
   {
      // --- 4. Reclaim detection via CLOSE ONLY (body must confirm) ---
      // BULL: M5 CLOSE > TriggerLevel (body closed above — reclaimed as support)
      // BEAR: M5 CLOSE < TriggerLevel (body closed below — reclaimed as resistance)
      bool reclaimed = false;
      if(ctx.Bias == "BULL")
         reclaimed = (closeM5 > ctx.TriggerLevel);
      else
         reclaimed = (closeM5 < ctx.TriggerLevel);

      if(reclaimed)
      {
         ctx.M5_Reclaim_Time = iTime(ctx.Symbol, PERIOD_M5, 1);
         ctx.Notes = ctx.Notes + " | M5_Reclaim@" +
                     TimeToString(ctx.M5_Reclaim_Time, TIME_DATE|TIME_MINUTES);
         WriteCSVRow("SIGNAL", ctx);
         Print(ctx.Symbol, " M5 Reclaim confirmed. Close=", DoubleToString(closeM5, ctx.Digits),
               " Trigger=", DoubleToString(ctx.TriggerLevel, ctx.Digits),
               " Bar=", TimeToString(ctx.M5_Reclaim_Time, TIME_DATE|TIME_MINUTES));

         // Advance to Micro-BOS stage
         sd.State = STATE_WAIT_MICROBOS;
         SetupMicroBOS(idx);
      }
   }
}

//+------------------------------------------------------------------+
//|  Stage 4: Set up Micro-BOS level when entering STATE_WAIT_MICROBOS|
//|  Called once on the M5 bar where reclaim was confirmed            |
//+------------------------------------------------------------------+
void SetupMicroBOS(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Initialise wait tracking
   sd.MicroBOS_BarsWaited = 0;
   sd.MicroBOS_StartTime  = iTime(ctx.Symbol, PERIOD_M5, 0);

   // Lookback for M5 micro pivot detection — needs room for InpMicroPivotBars each side
   // +20 provides buffer to find at least a few fully formed pivots in recent price action
   int lookback = InpMicroPivotBars * 2 + 20;

   int    swIdx[];
   double swPrc[];

   if(ctx.Bias == "BULL")
   {
      // Find swing HIGHs — price must close above the highest one for micro-BOS
      int swCount = FindPivots(ctx.Symbol, PERIOD_M5, 1,
                               InpMicroPivotBars, lookback, 5, swIdx, swPrc);
      if(swCount > 0)
      {
         // Use the highest swing high as the level to break
         double highest = swPrc[0];
         for(int k = 1; k < swCount; k++)
            if(swPrc[k] > highest) highest = swPrc[k];
         ctx.M5_MicroLevel = highest;
      }
      else
      {
         // Fallback: recent highest high
         int barHigh = iHighest(ctx.Symbol, PERIOD_M5, MODE_HIGH, lookback, 1);
         ctx.M5_MicroLevel = iHigh(ctx.Symbol, PERIOD_M5, barHigh);
      }
   }
   else // BEAR
   {
      // Find swing LOWs — price must close below the lowest one for micro-BOS
      int swCount = FindPivots(ctx.Symbol, PERIOD_M5, -1,
                               InpMicroPivotBars, lookback, 5, swIdx, swPrc);
      if(swCount > 0)
      {
         // Use the lowest swing low as the level to break
         double lowest = swPrc[0];
         for(int k = 1; k < swCount; k++)
            if(swPrc[k] < lowest) lowest = swPrc[k];
         ctx.M5_MicroLevel = lowest;
      }
      else
      {
         // Fallback: recent lowest low
         int barLow = iLowest(ctx.Symbol, PERIOD_M5, MODE_LOW, lookback, 1);
         ctx.M5_MicroLevel = iLow(ctx.Symbol, PERIOD_M5, barLow);
      }
   }

   Print(ctx.Symbol, " Micro-BOS setup — Bias=", ctx.Bias,
         " MicroLevel=", DoubleToString(ctx.M5_MicroLevel, ctx.Digits));
}

//+------------------------------------------------------------------+
//|  Stage 4: Check M5 Micro-BOS on each new M5 bar                  |
//|  (STATE_WAIT_MICROBOS)                                           |
//|                                                                  |
//|  CRITICAL RULE: CLOSE ONLY — body must confirm the break.        |
//|  Mesti body closed candle — bukan wick.                          |
//+------------------------------------------------------------------+
void CheckMicroBOS(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Count this M5 bar
   sd.MicroBOS_BarsWaited++;

   double closeM5 = iClose(ctx.Symbol, PERIOD_M5, 1); // last fully closed M5 bar

   // --- 1. Timeout check ---
   if(sd.MicroBOS_BarsWaited > InpMicroBOSTimeout)
   {
      ctx.ReasonCode = "REJECT_NO_MICROBOS";
      ctx.ReasonText = "Micro-BOS timeout after " + IntegerToString(sd.MicroBOS_BarsWaited) + " M5 bars";
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID           = prevID;
      sd.M5_TouchDetected    = false;
      sd.Retest_BarsWaited   = 0;
      sd.MicroBOS_BarsWaited = 0;
      sd.MicroBOS_StartTime  = 0;
      sd.State = STATE_SCAN_DIV;
      return;
   }

   // --- 2. Invalidation check (CLOSE ONLY — body must confirm) ---
   if(ctx.Bias == "BULL")
   {
      if(closeM5 < ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_MICROBOS";
         ctx.ReasonText = "M5 invalidation: close " + DoubleToString(closeM5, ctx.Digits) +
                          " below invalidation " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID           = prevID;
         sd.M5_TouchDetected    = false;
         sd.Retest_BarsWaited   = 0;
         sd.MicroBOS_BarsWaited = 0;
         sd.MicroBOS_StartTime  = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }
   else // BEAR
   {
      if(closeM5 > ctx.InvalidationLevel)
      {
         ctx.ReasonCode = "REJECT_NO_MICROBOS";
         ctx.ReasonText = "M5 invalidation: close " + DoubleToString(closeM5, ctx.Digits) +
                          " above invalidation " + DoubleToString(ctx.InvalidationLevel, ctx.Digits);
         WriteCSVRow("REJECT", ctx);
         int prevID = ctx.SignalID;
         ResetContext(ctx, ctx.Symbol);
         ctx.SignalID           = prevID;
         sd.M5_TouchDetected    = false;
         sd.Retest_BarsWaited   = 0;
         sd.MicroBOS_BarsWaited = 0;
         sd.MicroBOS_StartTime  = 0;
         sd.State = STATE_SCAN_DIV;
         return;
      }
   }

   // --- 3. Dynamic MicroLevel update — rescan for new swing points ---
   // Use same lookback as SetupMicroBOS: InpMicroPivotBars each side + 20 bar buffer
   int lookback = InpMicroPivotBars * 2 + 20;
   int    swIdx[];
   double swPrc[];

   if(ctx.Bias == "BULL")
   {
      int swCount = FindPivots(ctx.Symbol, PERIOD_M5, 1,
                               InpMicroPivotBars, lookback, 5, swIdx, swPrc);
      if(swCount > 0)
      {
         double highest = swPrc[0];
         for(int k = 1; k < swCount; k++)
            if(swPrc[k] > highest) highest = swPrc[k];
         if(highest > ctx.M5_MicroLevel)
            ctx.M5_MicroLevel = highest; // update only if a new higher swing high formed
      }
   }
   else // BEAR
   {
      int swCount = FindPivots(ctx.Symbol, PERIOD_M5, -1,
                               InpMicroPivotBars, lookback, 5, swIdx, swPrc);
      if(swCount > 0)
      {
         double lowest = swPrc[0];
         for(int k = 1; k < swCount; k++)
            if(swPrc[k] < lowest) lowest = swPrc[k];
         if(lowest < ctx.M5_MicroLevel)
            ctx.M5_MicroLevel = lowest; // update only if a new lower swing low formed
      }
   }

   // --- 4. Micro-BOS confirmation via CLOSE ONLY (body must confirm the break) ---
   bool bosConfirmed = false;
   if(ctx.Bias == "BULL")
      bosConfirmed = (closeM5 > ctx.M5_MicroLevel);
   else
      bosConfirmed = (closeM5 < ctx.M5_MicroLevel);

   if(bosConfirmed)
   {
      ctx.M5_MicroBOS_Time = iTime(ctx.Symbol, PERIOD_M5, 1);
      ctx.Notes = ctx.Notes + " | M5_uBOS@" + DoubleToString(ctx.M5_MicroLevel, ctx.Digits) +
                  " T=" + TimeToString(ctx.M5_MicroBOS_Time, TIME_DATE|TIME_MINUTES);
      WriteCSVRow("SIGNAL", ctx);
      Print(ctx.Symbol, " M5 Micro-BOS confirmed. Close=", DoubleToString(closeM5, ctx.Digits),
            " MicroLevel=", DoubleToString(ctx.M5_MicroLevel, ctx.Digits),
            " Bar=", TimeToString(ctx.M5_MicroBOS_Time, TIME_DATE|TIME_MINUTES));

      sd.State = STATE_READY_ENTRY;
   }
}

//+------------------------------------------------------------------+
//|  Process one symbol on a new M5 bar — routes to correct handler  |
//+------------------------------------------------------------------+
void ProcessSymbolM5(int idx)
{
   SSymbolData &sd = g_Symbols[idx];

   if(sd.State == STATE_WAIT_RETEST)
      CheckM5Retest(idx);
   else if(sd.State == STATE_WAIT_MICROBOS)
      CheckMicroBOS(idx);
   else if(sd.State == STATE_READY_ENTRY)
      TryEnterTrade(idx);
}

//+------------------------------------------------------------------+
//|  Helper: normalize a lot size to symbol volume constraints        |
//+------------------------------------------------------------------+
double NormalizeVolume(double lots, const string symbol)
{
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step > 0.0)
      lots = MathFloor(lots / step) * step;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   // Determine decimal precision from the step size
   int digits = 0;
   double s = step;
   while(s < 1.0 - 1e-10) { s *= 10.0; digits++; }
   return NormalizeDouble(lots, digits);
}

//+------------------------------------------------------------------+
//|  Helper: reset position tracking fields in SSymbolData            |
//+------------------------------------------------------------------+
void ResetEntryFields(SSymbolData &sd)
{
   sd.PositionTicket     = 0;
   sd.PositionEntryPrice = 0.0;
   sd.PositionOrigVolume = 0.0;
   sd.PositionSL         = 0.0;
   sd.PositionTP1        = 0.0;
   sd.PositionTP2        = 0.0;
   sd.PositionTP3        = 0.0;
   sd.TP1_Done           = false;
   sd.TP2_Done           = false;
   sd.TP3_Done           = false;
}

//+------------------------------------------------------------------+
//|  Environment filter: check if current time is within session     |
//+------------------------------------------------------------------+
bool IsWithinSession(const string symbol)
{
   if(!InpUseSessionFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMins   = dt.hour * 60 + dt.min;
   int startMins = InpSessionStartHour * 60 + InpSessionStartMin;
   int endMins   = InpSessionEndHour   * 60 + InpSessionEndMin;

   if(startMins <= endMins)
      return (nowMins >= startMins && nowMins < endMins);
   else // overnight wrap
      return (nowMins >= startMins || nowMins < endMins);
}

//+------------------------------------------------------------------+
//|  Environment filter: return true if Friday cutoff is active      |
//+------------------------------------------------------------------+
bool IsFridayCutoff()
{
   if(!InpUseFridayCutoff) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= InpFridayCutoffHour);
}

//+------------------------------------------------------------------+
//|  Environment filter: return true if spread is within limit       |
//+------------------------------------------------------------------+
bool IsSpreadOK(const string symbol)
{
   long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (spread <= (long)InpEntryMaxSpread);
}

//+------------------------------------------------------------------+
//|  Environment filter: check ATR-based volatility gate             |
//+------------------------------------------------------------------+
bool IsVolatilityOK(int atrH1Handle)
{
   if(!InpUseVolatilityGate) return true;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrH1Handle, 0, 1, 20, atrBuf) < 20) return true; // not enough data — allow

   double current = atrBuf[0];
   if(current <= 0.0) return true;

   double sum = 0.0;
   for(int i = 0; i < 20; i++) sum += atrBuf[i];
   double avg = sum / 20.0;
   if(avg <= 0.0) return true;

   if(current < avg * InpATR_H1_FloorMult) return false; // too quiet
   if(current > avg * InpATR_H1_CeilMult)  return false; // too volatile
   return true;
}

//+------------------------------------------------------------------+
//|  Stage 5: Attempt trade entry when STATE_READY_ENTRY              |
//|  Hard rejections reset state to STATE_SCAN_DIV.                  |
//|  Soft/transient failures return false without state change.       |
//+------------------------------------------------------------------+
bool TryEnterTrade(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   bool isBuy = (ctx.Bias == "BULL");

   // --- Environment gates (soft rejection — retry next bar) ---
   if(!IsWithinSession(ctx.Symbol))
      return false; // silent retry — not within trading session

   if(IsFridayCutoff())
      return false; // silent retry — Friday cutoff

   if(!IsSpreadOK(ctx.Symbol))
   {
      Print(ctx.Symbol, " TryEnterTrade: spread too high, retrying...");
      return false;
   }

   if(!IsVolatilityOK(sd.hATR_H1))
   {
      Print(ctx.Symbol, " TryEnterTrade: volatility outside range, retrying...");
      return false;
   }

   // Current entry price (market order)
   double entryPrice = isBuy ? SymbolInfoDouble(ctx.Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(ctx.Symbol, SYMBOL_BID);

   // ATR values — soft failure if unavailable (retry next tick)
   double atrH1 = GetIndicatorValue(sd.hATR_H1, 1);
   double atrM5 = GetIndicatorValue(sd.hATR_M5, 1);
   if(atrH1 == EMPTY_VALUE || atrH1 <= 0.0 || atrM5 == EMPTY_VALUE || atrM5 <= 0.0)
      return false; // transient — do not log, retry

   // --- Compute SL ---
   double slBuffer = InpSL_Buffer_ATR_M5 * atrM5;
   double slPrice  = isBuy ? ctx.InvalidationLevel - slBuffer
                           : ctx.InvalidationLevel + slBuffer;
   double slDist   = MathAbs(entryPrice - slPrice);
   if(slDist <= 0.0)
   {
      ctx.ReasonCode = "REJECT_SL_ZERO";
      ctx.ReasonText = "SL distance is zero";
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      ResetEntryFields(sd);
      sd.State = STATE_SCAN_DIV;
      return false;
   }

   // --- SL width check ---
   if(slDist > InpMaxSL_ATR_H1 * atrH1)
   {
      ctx.ReasonCode = "REJECT_SL_TOO_WIDE";
      ctx.ReasonText = "SL dist=" + DoubleToString(slDist / atrH1, 2) +
                       "xATR_H1 > max " + DoubleToString(InpMaxSL_ATR_H1, 1);
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      ResetEntryFields(sd);
      sd.State = STATE_SCAN_DIV;
      return false;
   }

   // --- Compute TP levels ---
   double tp1 = isBuy ? entryPrice + InpTP1_ATR_H1 * atrH1
                      : entryPrice - InpTP1_ATR_H1 * atrH1;
   double tp2 = isBuy ? entryPrice + InpTP2_ATR_H1 * atrH1
                      : entryPrice - InpTP2_ATR_H1 * atrH1;
   double tp3 = isBuy ? entryPrice + InpTP3_ATR_H1 * atrH1
                      : entryPrice - InpTP3_ATR_H1 * atrH1;

   // --- Room-to-move check ---
   double minTP = isBuy ? entryPrice + InpMinRR * slDist
                        : entryPrice - InpMinRR * slDist;
   bool roomOK  = isBuy ? (tp1 >= minTP) : (tp1 <= minTP);
   if(!roomOK)
   {
      ctx.ReasonCode = "REJECT_NO_ROOM";
      ctx.ReasonText = "TP1 RR=" + DoubleToString(MathAbs(tp1 - entryPrice) / slDist, 2) +
                       " < min " + DoubleToString(InpMinRR, 1);
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      ResetEntryFields(sd);
      sd.State = STATE_SCAN_DIV;
      return false;
   }

   // --- Position sizing ---
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt    = balance * InpRiskPercent / 100.0;
   double tickVal    = SymbolInfoDouble(ctx.Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(ctx.Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotMin     = SymbolInfoDouble(ctx.Symbol, SYMBOL_VOLUME_MIN);

   if(tickVal <= 0.0 || tickSize <= 0.0)
      return false; // transient — retry next tick

   double riskPerLot = (slDist / tickSize) * tickVal;
   if(riskPerLot <= 0.0)
      return false; // transient — retry next tick

   double lots = NormalizeVolume(riskAmt / riskPerLot, ctx.Symbol);
   if(lots < lotMin)
   {
      ctx.ReasonCode = "REJECT_LOT_BELOW_MIN";
      ctx.ReasonText = "Lot=" + DoubleToString(lots, 2) +
                       " < min=" + DoubleToString(lotMin, 2);
      WriteCSVRow("REJECT", ctx);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      ResetEntryFields(sd);
      sd.State = STATE_SCAN_DIV;
      return false;
   }

   // --- Send market order ---
   // Final spread check before committing the order
   if(!IsSpreadOK(ctx.Symbol))
   {
      Print(ctx.Symbol, " TryEnterTrade: spread widened before OrderSend, retrying...");
      return false;
   }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = ctx.Symbol;
   req.volume       = lots;
   req.type         = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price        = entryPrice;
   req.sl           = slPrice;
   req.tp           = tp1;
   req.deviation    = InpSlippage;
   req.magic        = InpMagicNumber;
   req.comment      = "AWRAFX_" + ctx.Symbol + "_" + IntegerToString(ctx.SignalID);
   req.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(req, res) ||
      (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      // Transient broker error — do not reset state, retry next tick
      Print(ctx.Symbol, " TryEnterTrade: OrderSend failed retcode=", res.retcode);
      return false;
   }

   // --- Trade opened successfully ---
   // res.order is the position ticket (order that opened the position)
   sd.PositionTicket     = res.order;
   sd.PositionEntryPrice = entryPrice;
   sd.PositionOrigVolume = lots;
   sd.PositionSL         = slPrice;
   sd.PositionTP1        = tp1;
   sd.PositionTP2        = tp2;
   sd.PositionTP3        = tp3;
   sd.TP1_Done           = false;
   sd.TP2_Done           = false;
   sd.TP3_Done           = false;
   sd.TradeMAE           = 0.0;
   sd.TradeMFE           = 0.0;
   g_TotalSignals++;

   ctx.Entry_Time  = TimeCurrent();
   ctx.Entry_Price = entryPrice;
   ctx.Notes = ctx.Notes + " | Entry@" + DoubleToString(entryPrice, ctx.Digits) +
               " SL=" + DoubleToString(slPrice, ctx.Digits) +
               " TP1=" + DoubleToString(tp1, ctx.Digits) +
               " Lots=" + DoubleToString(lots, 2);
   WriteCSVRow("SIGNAL", ctx);

   Print(ctx.Symbol, " Trade opened. Ticket=", sd.PositionTicket,
         " Lots=", DoubleToString(lots, 2),
         " Entry=", DoubleToString(entryPrice, ctx.Digits),
         " SL=", DoubleToString(slPrice, ctx.Digits),
         " TP1=", DoubleToString(tp1, ctx.Digits));

   sd.State = STATE_MANAGE_TRADE;
   return true;
}

//+------------------------------------------------------------------+
//|  Stage 6: Manage open position — partial TPs and state reset     |
//|  Called on every tick when STATE_MANAGE_TRADE                    |
//+------------------------------------------------------------------+
bool ManageOpenPosition(int idx)
{
   SSymbolData    &sd  = g_Symbols[idx];
   SSignalContext &ctx = sd.Ctx;

   // Check if position is still open
   if(!PositionSelectByTicket(sd.PositionTicket))
   {
      Print(ctx.Symbol, " Position closed (ticket=", sd.PositionTicket, ")");

      // --- Compute final Result, MAE_R, MFE_R and write CLOSED row ---
      double slDist = MathAbs(sd.PositionEntryPrice - sd.PositionSL);
      double finalPnL = 0.0;
      // Try to get profit from history
      if(HistorySelectByPosition(sd.PositionTicket))
      {
         int deals = HistoryDealsTotal();
         for(int d = 0; d < deals; d++)
         {
            ulong dTicket = HistoryDealGetTicket(d);
            if(dTicket > 0)
               finalPnL += HistoryDealGetDouble(dTicket, DEAL_PROFIT);
         }
      }
      double tickSize = SymbolInfoDouble(ctx.Symbol, SYMBOL_TRADE_TICK_SIZE);
      ctx.MAE_R = 0.0;
      ctx.MFE_R = 0.0;
      if(slDist > tickSize)
      {
         ctx.MAE_R = sd.TradeMAE / slDist;
         ctx.MFE_R = sd.TradeMFE / slDist;
      }
      if(finalPnL > 0.0)
         ctx.Result = "WIN";
      else if(finalPnL < 0.0)
         ctx.Result = "LOSS";
      else
         ctx.Result = "BE";
      WriteCSVRow("CLOSED", ctx);

      // Update global KPI counters
      g_SumMAE_R += ctx.MAE_R;
      g_SumMFE_R += ctx.MFE_R;
      if(ctx.Result == "WIN")      { g_Wins++;      g_SumProfit += finalPnL; }
      else if(ctx.Result == "LOSS"){ g_Losses++;    g_SumLoss   += MathAbs(finalPnL); }
      else                          { g_Breakeven++; }

      ResetEntryFields(sd);
      int prevID = ctx.SignalID;
      ResetContext(ctx, ctx.Symbol);
      ctx.SignalID = prevID;
      sd.State = STATE_SCAN_DIV;
      return true; // state changed
   }

   // --- Track MAE/MFE on every tick while position is open ---
   {
      bool   isBuyPos    = (ctx.Bias == "BULL");
      double curPricePos = isBuyPos ? SymbolInfoDouble(ctx.Symbol, SYMBOL_BID)
                                    : SymbolInfoDouble(ctx.Symbol, SYMBOL_ASK);
      double unrealPnL   = isBuyPos ? (curPricePos - sd.PositionEntryPrice)
                                    : (sd.PositionEntryPrice - curPricePos);
      sd.TradeMAE = MathMin(sd.TradeMAE, unrealPnL);
      sd.TradeMFE = MathMax(sd.TradeMFE, unrealPnL);
   }

   if(!InpUsePartialTP) return false;

   bool isBuy       = (ctx.Bias == "BULL");
   double curPrice  = isBuy ? SymbolInfoDouble(ctx.Symbol, SYMBOL_BID)
                            : SymbolInfoDouble(ctx.Symbol, SYMBOL_ASK);
   double tickSize  = SymbolInfoDouble(ctx.Symbol, SYMBOL_TRADE_TICK_SIZE);
   double curVol    = PositionGetDouble(POSITION_VOLUME);
   if(!sd.TP1_Done)
   {
      bool tp1Hit = isBuy ? (curPrice >= sd.PositionTP1) : (curPrice <= sd.PositionTP1);
      if(tp1Hit)
      {
         double closeVol = NormalizeVolume(sd.PositionOrigVolume * InpTP1_ClosePct, ctx.Symbol);
         double minLot   = SymbolInfoDouble(ctx.Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol > curVol) closeVol = curVol;
         if(closeVol >= minLot)
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action       = TRADE_ACTION_DEAL;
            req.symbol       = ctx.Symbol;
            req.volume       = closeVol;
            req.type         = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price        = curPrice;
            req.deviation    = InpSlippage;
            req.magic        = InpMagicNumber;
            req.comment      = "AWRAFX_TP1_" + IntegerToString(ctx.SignalID);
            req.position     = sd.PositionTicket;
            req.type_filling = ORDER_FILLING_IOC;
            if(OrderSend(req, res))
            {
               sd.TP1_Done = true;
               // Move SL to breakeven + 1 tick, respecting broker stops level
               long stopsLevel = SymbolInfoInteger(ctx.Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minDist  = stopsLevel * SymbolInfoDouble(ctx.Symbol, SYMBOL_POINT);
               double newSL    = isBuy ? sd.PositionEntryPrice + tickSize
                                       : sd.PositionEntryPrice - tickSize;
               // Ensure SL meets minimum distance from current price
               if(isBuy && (curPrice - newSL) < minDist)
                  newSL = curPrice - minDist;
               else if(!isBuy && (newSL - curPrice) < minDist)
                  newSL = curPrice + minDist;
               MqlTradeRequest modReq = {};
               MqlTradeResult  modRes = {};
               modReq.action   = TRADE_ACTION_SLTP;
               modReq.symbol   = ctx.Symbol;
               modReq.sl       = newSL;
               modReq.tp       = sd.PositionTP2;
               modReq.position = sd.PositionTicket;
               OrderSend(modReq, modRes);
               sd.PositionSL = newSL;
               Print(ctx.Symbol, " TP1 hit. Partial close=", closeVol, " SL moved to BE");
            }
         }
         else
            sd.TP1_Done = true; // volume too small, skip
      }
   }
   // --- TP2 ---
   else if(!sd.TP2_Done)
   {
      bool tp2Hit = isBuy ? (curPrice >= sd.PositionTP2) : (curPrice <= sd.PositionTP2);
      if(tp2Hit)
      {
         double closeVol = NormalizeVolume(sd.PositionOrigVolume * InpTP2_ClosePct, ctx.Symbol);
         double minLot   = SymbolInfoDouble(ctx.Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol > curVol) closeVol = curVol;
         if(closeVol >= minLot)
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action       = TRADE_ACTION_DEAL;
            req.symbol       = ctx.Symbol;
            req.volume       = closeVol;
            req.type         = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            req.price        = curPrice;
            req.deviation    = InpSlippage;
            req.magic        = InpMagicNumber;
            req.comment      = "AWRAFX_TP2_" + IntegerToString(ctx.SignalID);
            req.position     = sd.PositionTicket;
            req.type_filling = ORDER_FILLING_IOC;
            if(OrderSend(req, res))
            {
               sd.TP2_Done = true;
               MqlTradeRequest modReq = {};
               MqlTradeResult  modRes = {};
               modReq.action   = TRADE_ACTION_SLTP;
               modReq.symbol   = ctx.Symbol;
               modReq.sl       = sd.PositionSL;
               modReq.tp       = sd.PositionTP3;
               modReq.position = sd.PositionTicket;
               OrderSend(modReq, modRes);
               Print(ctx.Symbol, " TP2 hit. Partial close=", closeVol);
            }
         }
         else
            sd.TP2_Done = true;
      }
   }
   // --- TP3 (close all remaining) ---
   else if(!sd.TP3_Done)
   {
      bool tp3Hit = isBuy ? (curPrice >= sd.PositionTP3) : (curPrice <= sd.PositionTP3);
      if(tp3Hit && curVol > 0.0)
      {
         MqlTradeRequest req = {};
         MqlTradeResult  res = {};
         req.action       = TRADE_ACTION_DEAL;
         req.symbol       = ctx.Symbol;
         req.volume       = curVol;
         req.type         = isBuy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         req.price        = curPrice;
         req.deviation    = InpSlippage;
         req.magic        = InpMagicNumber;
         req.comment      = "AWRAFX_TP3_" + IntegerToString(ctx.SignalID);
         req.position     = sd.PositionTicket;
         req.type_filling = ORDER_FILLING_IOC;
         if(OrderSend(req, res))
         {
            sd.TP3_Done = true;
            Print(ctx.Symbol, " TP3 hit. Full close.");
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//|  Build dashboard comment string for all symbols                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   string dash = "=== AWRAFX TrendDiv EA ===\n";
   dash += "RunID: " + g_RunID + "\n";

   // --- Environment status line (uses first symbol for spread/vol if available) ---
   string envSession = IsWithinSession(g_SymbolCount > 0 ? g_Symbols[0].Symbol : "") ? "OK" : "BLOCKED";
   string envFriday  = IsFridayCutoff() ? "CUTOFF" : "OK";

   // Spread display (first symbol)
   string envSpread = "-";
   if(g_SymbolCount > 0)
   {
      long sp = SymbolInfoInteger(g_Symbols[0].Symbol, SYMBOL_SPREAD);
      envSpread = DoubleToString((double)sp, 1);
   }

   // Volatility display (first symbol)
   string envVol = "-";
   if(g_SymbolCount > 0)
   {
      if(!InpUseVolatilityGate)
         envVol = "OK";
      else if(IsVolatilityOK(g_Symbols[0].hATR_H1))
         envVol = "OK";
      else
      {
         // Determine which boundary
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(g_Symbols[0].hATR_H1, 0, 1, 20, atrBuf) >= 20)
         {
            double cur = atrBuf[0];
            double sum = 0.0;
            for(int j = 0; j < 20; j++) sum += atrBuf[j];
            double avg = sum / 20.0;
            envVol = (cur < avg * InpATR_H1_FloorMult) ? "TOO_QUIET" : "TOO_VOLATILE";
         }
         else
            envVol = "INSUF_DATA";
      }
   }

   dash += "Session: " + envSession +
           " | Spread: " + envSpread +
           " | Vol: " + envVol +
           " | Fri: " + envFriday + "\n\n";

   for(int i = 0; i < g_SymbolCount; i++)
   {
      SSymbolData &sd = g_Symbols[i];
      string stateStr = "";
      switch(sd.State)
      {
         case STATE_SCAN_DIV:      stateStr = "SCAN_DIV";      break;
         case STATE_WAIT_CHOCH:    stateStr = "WAIT_CHOCH";    break;
         case STATE_WAIT_RETEST:   stateStr = "WAIT_RETEST";   break;
         case STATE_WAIT_MICROBOS: stateStr = "WAIT_MICROBOS"; break;
         case STATE_READY_ENTRY:   stateStr = "READY_ENTRY";   break;
         case STATE_MANAGE_TRADE:  stateStr = "MANAGE_TRADE";  break;
         default:                  stateStr = "IDLE";           break;
      }

      dash += sd.Symbol + ": " + stateStr;
      if(sd.Ctx.DivType != DIV_NONE)
      {
         dash += " | Div=" + DivTypeToStr(sd.Ctx.DivType);
         dash += " | Bias=" + sd.Ctx.Bias;
         dash += " | Score=" + DoubleToString(sd.Ctx.Score_Total, 1);
         if(sd.Ctx.TrendStrongFlag)
            dash += " | TrendStrong";
         if(sd.Ctx.RegimeReject)
            dash += " | REGIME_REJECT";
         // CHoCH-specific display
         if(sd.State == STATE_WAIT_CHOCH)
         {
            int barsLeft = InpCHoCHTimeout - sd.CHoCH_BarsWaited;
            dash += " | CHoCH@" + DoubleToString(sd.Ctx.TriggerLevel, sd.Ctx.Digits) +
                    " | Inv@" + DoubleToString(sd.Ctx.InvalidationLevel, sd.Ctx.Digits) +
                    " | " + IntegerToString(barsLeft) + " bars left";
         }
         else if(sd.State == STATE_WAIT_RETEST || sd.State == STATE_WAIT_MICROBOS ||
                 sd.State == STATE_READY_ENTRY || sd.State == STATE_MANAGE_TRADE)
         {
            dash += " | CHoCH OK @" + DoubleToString(sd.Ctx.H1_CHoCH_Close, sd.Ctx.Digits);
            if(sd.State == STATE_WAIT_RETEST)
            {
               int barsLeft = InpRetestTimeout - sd.Retest_BarsWaited;
               string touchStr = sd.M5_TouchDetected ? "YES" : "NO";
               dash += " | M5 Retest | Touch=" + touchStr +
                       " | " + IntegerToString(barsLeft) + " bars left";
            }
            else if(sd.State == STATE_WAIT_MICROBOS)
            {
               int barsLeft = InpMicroBOSTimeout - sd.MicroBOS_BarsWaited;
               dash += " | M5 uBOS@" + DoubleToString(sd.Ctx.M5_MicroLevel, sd.Ctx.Digits) +
                       " | " + IntegerToString(barsLeft) + " bars left";
            }
            else if(sd.State == STATE_READY_ENTRY)
            {
               dash += " | READY OK | Attempting entry...";
            }
            else if(sd.State == STATE_MANAGE_TRADE)
            {
               dash += " | IN TRADE | Entry=" + DoubleToString(sd.PositionEntryPrice, sd.Ctx.Digits) +
                       " SL=" + DoubleToString(sd.PositionSL, sd.Ctx.Digits) +
                       " TP1=" + DoubleToString(sd.PositionTP1, sd.Ctx.Digits) +
                       (sd.TP1_Done ? " [TP1✓]" : "") +
                       (sd.TP2_Done ? " [TP2✓]" : "");
            }
         }
      }
      dash += "\n";
   }

   // KPI summary line
   int closed = g_Wins + g_Losses + g_Breakeven;
   double winrate = (closed > 0) ? (100.0 * g_Wins / closed) : 0.0;
   double avgMAE  = (closed > 0) ? (g_SumMAE_R / closed) : 0.0;
   double avgMFE  = (closed > 0) ? (g_SumMFE_R / closed) : 0.0;
   double pf      = (g_SumLoss > 0.0) ? (g_SumProfit / g_SumLoss) : 0.0;
   dash += "KPI: W=" + IntegerToString(g_Wins) +
           " L=" + IntegerToString(g_Losses) +
           " BE=" + IntegerToString(g_Breakeven) +
           " | WR=" + DoubleToString(winrate, 1) + "%" +
           " | avgMAE=" + DoubleToString(avgMAE, 2) + "R" +
           " | avgMFE=" + DoubleToString(avgMFE, 2) + "R" +
           " | PF=" + DoubleToString(pf, 2) + "\n";

   Comment(dash);
}

//+------------------------------------------------------------------+
//|  Process one symbol on a new H1 bar                              |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
{
   SSymbolData &sd = g_Symbols[idx];

   if(sd.State == STATE_SCAN_DIV)
   {
      // Skip divergence scanning near weekend to avoid queuing signals we won't trade
      if(InpUseFridayCutoff && IsFridayCutoff())
         return;

      // Increment SignalID for new attempt
      // (SignalID incremented inside DetectH1Divergence on success)
      // Reset context fields (keep SignalID counter)
      int prevSignalID = sd.Ctx.SignalID;
      ResetContext(sd.Ctx, sd.Symbol);
      sd.Ctx.SignalID = prevSignalID;

      if(DetectH1Divergence(sd))
      {
         // Divergence confirmed — advance to wait for CHoCH and set up levels
         sd.State = STATE_WAIT_CHOCH;
         SetupCHoCHLevels(idx);
      }
      // If not confirmed, remain in STATE_SCAN_DIV
   }
   else if(sd.State == STATE_WAIT_CHOCH)
   {
      // Check for CHoCH confirmation on each new H1 bar
      CheckCHoCH(idx);
   }
   // M5 states (WAIT_RETEST, WAIT_MICROBOS) are handled by ProcessSymbolM5()
   // which is called from OnTick() on each new M5 bar
}

//+------------------------------------------------------------------+
//|  OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_RunID = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   // Sanitize RunID for use in filenames if needed
   StringReplace(g_RunID, ":", "-");
   StringReplace(g_RunID, " ", "_");

   // Parse symbol list
   string symList[];
   int nSym = ParseSymbols(InpSymbols, symList);
   if(nSym <= 0)
   {
      Alert("AWRAFX EA: InpSymbols is empty — no symbols to scan.");
      return INIT_PARAMETERS_INCORRECT;
   }

   ArrayResize(g_Symbols, nSym);
   g_SymbolCount = 0;

   for(int i = 0; i < nSym; i++)
   {
      string sym = symList[i];
      if(!SymbolSelect(sym, true))
      {
         Print("WARNING: Cannot select symbol ", sym, " — skipping");
         continue;
      }

      SSymbolData &sd = g_Symbols[g_SymbolCount];
      sd.Symbol       = sym;
      sd.State        = STATE_SCAN_DIV;
      sd.LastBarTimeH1= 0;
      sd.LastBarTimeM5= 0;
      sd.CHoCH_WaitStartBarTime = 0;
      sd.CHoCH_BarsWaited       = 0;
      sd.M5_TouchDetected       = false;
      sd.Retest_BarsWaited      = 0;
      sd.MicroBOS_BarsWaited    = 0;
      sd.MicroBOS_StartTime     = 0;
      sd.PositionTicket         = 0;
      sd.PositionEntryPrice     = 0.0;
      sd.PositionOrigVolume     = 0.0;
      sd.PositionSL             = 0.0;
      sd.PositionTP1            = 0.0;
      sd.PositionTP2            = 0.0;
      sd.PositionTP3            = 0.0;
      sd.TP1_Done               = false;
      sd.TP2_Done               = false;
      sd.TP3_Done               = false;
      sd.TradeMAE               = 0.0;
      sd.TradeMFE               = 0.0;

      // Initialize indicator handles
      sd.hRSI_H1 = INVALID_HANDLE;
      sd.hEMA_H1 = INVALID_HANDLE;
      sd.hATR_H1 = INVALID_HANDLE;
      sd.hRSI_M5 = INVALID_HANDLE;
      sd.hEMA_M5 = INVALID_HANDLE;
      sd.hATR_M5 = INVALID_HANDLE;

      if(!InitHandles(sd))
      {
         Print("ERROR: Handle init failed for ", sym, " — skipping");
         continue;
      }

      // Initialize signal context
      ResetContext(sd.Ctx, sym);
      sd.Ctx.SignalID = 0;

      g_SymbolCount++;
   }

   if(g_SymbolCount == 0)
   {
      Alert("AWRAFX EA: No valid symbols initialized.");
      return INIT_FAILED;
   }

   // Compact the array to actual count
   ArrayResize(g_Symbols, g_SymbolCount);

   // Initialize CSV
   if(!InitCSV()) return INIT_FAILED;

   Print("AWRAFX TrendDiv EA initialized. Symbols: ", g_SymbolCount,
         " RunID: ", g_RunID);
   UpdateDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < g_SymbolCount; i++)
      ReleaseHandles(g_Symbols[i]);

   if(g_CSVHandle != INVALID_HANDLE)
   {
      FileClose(g_CSVHandle);
      g_CSVHandle = INVALID_HANDLE;
   }

   // Write KPI summary file
   if(InpWriteCSV)
   {
      int kpiHandle = FileOpen("FinalSpec_KPI_Summary.csv",
                               FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(kpiHandle != INVALID_HANDLE)
      {
         int closed = g_Wins + g_Losses + g_Breakeven;
         double winrate = (closed > 0) ? (100.0 * g_Wins / closed) : 0.0;
         double avgMAE  = (closed > 0) ? (g_SumMAE_R / closed) : 0.0;
         double avgMFE  = (closed > 0) ? (g_SumMFE_R / closed) : 0.0;
         double pf      = (g_SumLoss > 0.0) ? (g_SumProfit / g_SumLoss) : 0.0;

         FileWrite(kpiHandle,
            "RunID,TotalSignals,Wins,Losses,BE,Winrate,AvgMAE_R,AvgMFE_R,ProfitFactor");
         FileWrite(kpiHandle,
            g_RunID + "," +
            IntegerToString(g_TotalSignals) + "," +
            IntegerToString(g_Wins)         + "," +
            IntegerToString(g_Losses)       + "," +
            IntegerToString(g_Breakeven)    + "," +
            DoubleToString(winrate, 2)      + "," +
            DoubleToString(avgMAE,  4)      + "," +
            DoubleToString(avgMFE,  4)      + "," +
            DoubleToString(pf,      4));
         FileClose(kpiHandle);
      }
   }

   Comment(""); // Clear dashboard
   Print("AWRAFX TrendDiv EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//|  OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   bool anyUpdate = false;

   for(int i = 0; i < g_SymbolCount; i++)
   {
      SSymbolData &sd = g_Symbols[i];

      // New H1 bar check for this symbol
      datetime barTimeH1 = iTime(sd.Symbol, PERIOD_H1, 0);
      if(barTimeH1 != sd.LastBarTimeH1)
      {
         sd.LastBarTimeH1 = barTimeH1;
         ProcessSymbol(i);   // H1-level processing (divergence, CHoCH)
         anyUpdate = true;
      }

      // New M5 bar check — only when in M5-dependent states
      if(sd.State == STATE_WAIT_RETEST || sd.State == STATE_WAIT_MICROBOS ||
         sd.State == STATE_READY_ENTRY)
      {
         datetime barTimeM5 = iTime(sd.Symbol, PERIOD_M5, 0);
         if(barTimeM5 != sd.LastBarTimeM5)
         {
            sd.LastBarTimeM5 = barTimeM5;
            ProcessSymbolM5(i);  // M5-level processing (retest, micro-BOS, entry)
            anyUpdate = true;
         }
      }

      // Per-tick management for open positions
      if(sd.State == STATE_MANAGE_TRADE)
      {
         if(ManageOpenPosition(i))
            anyUpdate = true;
      }
   }

   if(anyUpdate)
      UpdateDashboard();
}
//+------------------------------------------------------------------+
