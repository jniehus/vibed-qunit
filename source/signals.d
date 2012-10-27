/**
 *  signals.d
**/

module signals;

struct SignalVibeReady
{
    bool isReady = false;
}

struct SignalQUnitDone
{
    bool isDone = false;
}

struct SignalReportDone
{
    bool isDone = false;
}

struct SignalVibeStatus
{
    int status;
}