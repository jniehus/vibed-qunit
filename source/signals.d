/**
 *  signals.d
**/

module signals;
import std.signals;

struct SignalVibeReady  { bool isReady = false; }
struct SignalReportDone { bool isDone  = false; }
struct SignalVibeStatus { int status; }

class SignalQUnitDone
{
    string message() { return _message; }
    string message(string msg) {
        if (msg != _message) {
            _message = msg;
            emit(msg);
        }
        return msg;
    }

    mixin Signal!(string);

private:
    string _message;
}