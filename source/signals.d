/**
 *  signals.d
**/

module signals;

struct SignalVibeReady  { bool isReady = false; }
struct SignalReportDone { bool isDone  = false; }
struct SignalVibeStatus { int status; }
struct SignalQUnitDone  { string browser; }
