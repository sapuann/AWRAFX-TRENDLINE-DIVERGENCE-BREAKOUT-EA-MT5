# Traceability Rules (LOCKED)

## CSV location
Default: `MQL5/Files/FinalSpec_Audit.csv`
Optional: `Common/Files/FinalSpec_Audit.csv`

## RowType
- SIGNAL
- REJECT

## Required columns (locked minimum)
Identity:
- RunID, SignalID, Symbol, Bias, Digits, Point

H1 Divergence:
- DivType
- H1_Pivot1_Time, H1_Pivot1_Price, H1_Pivot1_RSI
- H1_Pivot2_Time, H1_Pivot2_Price, H1_Pivot2_RSI
- H1_Div_RSIDelta, H1_Div_SpanBars

CHoCH:
- H1_CHoCH_Time, H1_CHoCH_Close
- TriggerLevel, InvalidationLevel

Regime:
- EMA200_H1, ATR_H1, TrendStrongFlag, RegimeReject

M5:
- M5_Touch_Time, M5_Reclaim_Time
- M5_MicroLevel, M5_MicroBOS_Time

Entry:
- Entry_Time, Entry_Price

Score:
- Score_Total, MinScore
- Score_DivStrength, Score_PivotSignificance, Score_RegimeQuality, Score_RoomToMove

KPI:
- KPI_LookaheadBarsM5, Result, MAE_R, MFE_R
Meta:
- Spread_Points, Tol_Price, Notes
Reject-only:
- ReasonCode, ReasonText

## Locked ReasonCodes
- REJECT_SPREAD_TOO_HIGH
- REJECT_REGIME_STRONG_TREND
- REJECT_NO_DIVERGENCE
- REJECT_NO_CHOCH
- REJECT_TIMEOUT_WAIT_RETEST
- REJECT_NO_RECLAIM
- REJECT_NO_MICROBOS
- REJECT_SCORE_BELOW_MIN
- REJECT_DUPLICATE_SIGNAL
- REJECT_INVALID_R