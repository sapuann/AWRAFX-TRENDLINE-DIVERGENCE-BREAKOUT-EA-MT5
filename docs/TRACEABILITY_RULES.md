# Traceability Rules

## Strict Audit-Trace Specification

### Required Per-Signal Fields
- **SignalID**: Unique identifier for the signal.
- **Divergence Pivots**: Time and price details for divergence.
- **RSI**: Relative Strength Index values.
- **CHoCH Candle**: Change of Character Candle details.
- **Trigger**: Conditions that trigger the signal.
- **Invalidation**: Rules for invalidating signals.
- **M5 Touch/Reclaim Times**: Times for M5 touch and reclaim events.
- **Micro-BOS Level/Time**: Details on micro-Break of Structure levels and their timestamps.
- **Entry Time/Price**: When and at what price the signal triggers an entry.
- **Score Breakdown**: Detailed scoring metrics for the signal.
- **KPI Result**: Key Performance Indicator results linked to the signal.

### Reason Codes
- Define codes to explain reasons for actions taken based on signals.

### File Locations for CSV Artifacts
- Document the file paths where CSV artifacts are stored.

### Stop Rule
- Outline the rules to implement stops based on signal evaluations.

