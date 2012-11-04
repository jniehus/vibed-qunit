/**
 * Vibe Server
**/

module app;

// vibe
import vibe.vibe;

// phobos
import core.thread;
import std.concurrency;
import std.getopt, std.stdio, std.array;
import std.process, std.uri, std.regex;

// local
import browser, report, signals;

// module variables
Json[][string]  qunitResults;
shared string   browserReports;
Tid             mainTid;

immutable string stop_vibe  = "GET /stopvibe HTTP/1.1\r\n"  "Host: localhost:23432\r\n\r\n";
immutable string run_report = "GET /runreport HTTP/1.1\r\n" "Host: localhost:23432\r\n\r\n";

//--- VIBE SERVER THREAD ---
void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.redirect("/index.html");
}

void stopVibe(HttpServerRequest req = null, HttpServerResponse res = null)
{
    exitEventLoop();
}

string doWork(Json data)
{
    writeln("The answer to life and the universe is " ~ data["data"].toString());
    return "done";
}

string recordResults(Json data)
{
    /*
      this is a good place to store results to mongoDB:
      db->app->tests->qunit->browser->testRun->result

      then a report generator will pull data from the
      last testRun for each browser
    */

    qunitResults[getBrowserName(data["browser"])] ~= data;
    return "done";
}

string qUnitDone(Json data)
{
    send(mainTid, SignalQUnitDone(true));
    return "done";
}

// delegate tasks
void processReq(HttpServerRequest req, HttpServerResponse res)
{
    string resBody;
    switch(req.json["action"].toString())
    {
    case `"dowork"`:
        resBody = doWork(req.json);
        break;
    case `"testresults"`:
        resBody = recordResults(req.json);
        break;
    case `"suiteresults"`:
        resBody = recordResults(req.json);
        break;
    case `"qunitdone"`:
        resBody = qUnitDone(req.json);
        break;
    case `"stopvibe"`:
        stopVibe();
        break;
    default:
        resBody = "fail";
    }

    res.headers["Access-Control-Allow-Origin"] = "*";
    res.writeBody(resBody);
}

void runReport(HttpServerRequest req = null, HttpServerResponse res = null)
{
    browserReports = generatePrettyReport(qunitResults);
    send(mainTid, SignalReportDone(true));
}

static this()
{
    auto settings = new HttpServerSettings;
    settings.port = 23432;
    settings.onStart = () => send(mainTid, SignalVibeReady(true));

    auto router = new UrlRouter;
    router.get("/", &handleRequest);
    router.get("*", serveStaticFiles("./public/"));
    router.post("/process_req", &processReq);
    router.get( "/runreport",   &runReport);
    router.get( "/stopvibe",    &stopVibe);

    listenHttp(settings, router);
}

void launchVibe(Tid tid)
{
    mainTid = tid;
    logInfo("Running event loop...");
    try {
        startListening(); // soon to be replaced or automatic
        send(tid, SignalVibeStatus(runEventLoop()));
    } catch( Throwable th ){
        logError("Unhandled exception in event loop: %s", th.toString());
        send(tid, SignalVibeStatus(2));
    }
}


//--- MAIN THREAD ---
void externalRequest(string req)
{
    auto reqVibeConn = connectTcp("localhost", 23432);
    scope(exit) reqVibeConn.close();
    reqVibeConn.write(req);
}

struct Args
{
    string testNumber = null;
    string moduleName = null;
}

// returns -1 if something unexpected happened
// returns  0 if pass
// returns  1 if fail
// returns  2 if vibe server took a shit
int main(string[] argz)
{
    //writeln(argz); // sub quote custom args. Example: ~/vibed-qunit$>vibe -- -m '"Module 2"'
    Args args = Args();
    getopt(argz,
        "testnumber|t", &args.testNumber,
        "module|m",     &args.moduleName);

    auto url = buildURL(args.testNumber, args.moduleName);
    Browser[] availableBrowsers = [
        //Browser("iexplore.exe", "C:\\Program Files\\Internet Explorer\\iexplore.exe"),         // windows
        //Browser("chrome.exe",   "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"), // windows
        //Browser("firefox.exe",  "C:\\Program Files\\Mozilla Firefox\\firefox.exe"),            // windows
        Browser("Firefox"),       // mac
        Browser("Google Chrome"), // mac
        Browser("Safari"),        // mac
        Browser("Opera")          // mac
    ];

    // start server and run browsers
    bool timeoutOccurred = false;
    auto vibeTid = spawn( &launchVibe, thisTid );
    receiveTimeout(dur!"seconds"(10), (SignalVibeReady _vibeReady) {
        foreach(Browser browser; availableBrowsers) {
            browser.open(url);
            if (!receiveTimeout(dur!"seconds"(10), (SignalQUnitDone _qunitDone) {})) {
                writeln(browser.name ~ " timed out!");
                timeoutOccurred = true;
            }
            browser.close();
        }

        // when browsers are done run the report
        externalRequest(run_report);
        auto reported = receiveTimeout(dur!"seconds"(10), (SignalReportDone _reportDone) {
            writeln(browserReports);
        });
    });

    // stop the server
    externalRequest(stop_vibe);
    int vibeStatus = -1;
    receive(
        (SignalVibeStatus _vStatus) { vibeStatus = _vStatus.status; }
    );

    // parse results
    if (match(browserReports, r"\sresult:\sF\s") || timeoutOccurred) { vibeStatus = 1; }
    writeln(vibeStatus);
    return vibeStatus;
}
