# Audit-Trace Specification

## CSV Schema
- **Column 1:** Timestamp (UTC) - Format: YYYY-MM-DD HH:MM:SS
- **Column 2:** RowType - Values: SIGNAL, REJECT
- **Column 3:** ReasonCode - Must be from the locked list below
- **Column 4:** Threshold - Indicates the stop rule threshold
- **Column 5:** ArtifactPath - Path to the relevant artifact

## RowType Definitions
- **SIGNAL:** Indicates a signal generation.
- **REJECT:** Indicates a signal rejection.

## Locked ReasonCode List
- REASON_CODE_1
- REASON_CODE_2
- REASON_CODE_3

## Stop Rule Thresholds
- Minimum Threshold: 0.1
- Maximum Threshold: 10.0

## Artifact Paths
- /path/to/artifact1
- /path/to/artifact2
