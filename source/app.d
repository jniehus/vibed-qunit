/**
 * Vibe Server
 */

module app;

// vibe
import vibe.vibe;

// phobos
import core.thread;
import std.algorithm;
import std.concurrency, std.parallelism;
import std.getopt, std.stdio, std.array, std.conv;
import std.process, std.uri, std.regex, std.file;

// local
import browser, report, vibeSignals;

// module variables
Json[][string]         qunitResults;
shared string          browserReports;
Tid                    mainTid;
shared string          host;
shared ushort          port;
int                    timeout_counter;
__gshared SignalQUnitDone signalQUnitDone;

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
    synchronized {
        qunitResults[data["browser"].toString()] ~= data;
    }
    return "done";
}

string qUnitDone(Json data)
{
    string name = to!string(data["browser"]);
    signalQUnitDone.message(name ~ " done");
    return "done";
}

// delegate tasks
void processReq(HttpServerRequest req, HttpServerResponse res)
{
    string resBody;
    switch(req.json["action"].toString())
    {
        case `"dowork"`:
            resBody = doWork(req.json); break;
        case `"testresults"`:
            resBody = recordResults(req.json); break;
        case `"suiteresults"`:
            resBody = recordResults(req.json); break;
        case `"qunitbegin"`:
            resBody = recordResults(req.json); break;
        case `"qunitdone"`:
            resBody = qUnitDone(req.json); break;
        case `"stopvibe"`:
            stopVibe(); break;
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
    settings.onStart = () => send(mainTid, SignalVibeReady(true));
    settings.port = port;

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
    auto reqVibeConn = connectTcp(host, port);
    scope(exit) reqVibeConn.close();
    reqVibeConn.write(req);
}

bool waitForSignal(Browser browser, int timeout = 10)
{
    int count = 0;
    while(!browser.done && count < timeout) {
        core.thread.Thread.sleep(dur!"seconds"(1));
        count++;
    }
    if (count == timeout) {
        return false;
    }
    return true;
}

void runBrowsers(Browser[] availableBrowsers)
{
    void updateTimeoutCounter(string browserName)
    {
        timeout_counter++;
        writeln(browserName ~ " timed out!");
    }

    timeout_counter = 0;
    foreach(browser; taskPool.parallel(availableBrowsers, 1)) {
        browser.open();
        if (!waitForSignal(browser)) {
            updateTimeoutCounter(browser.name);
            browser.close(); // make sure to close the browser
        }
    }
}

struct Args
{
    string testNumber = null;
    string moduleName = null;
    string host = "localhost";
    string port = "23432";
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
        "module|m",     &args.moduleName,
        "host|h",       &args.host,
        "port|p",       &args.port
    );

    host = args.host;
    port = to!ushort(args.port);

    // set external call strings
    string stop_vibe  = "GET /stopvibe HTTP/1.1\r\n"  "Host: " ~ args.host ~ ":" ~ args.port ~ "\r\n\r\n";
    string run_report = "GET /runreport HTTP/1.1\r\n" "Host: " ~ args.host ~ ":" ~ args.port ~ "\r\n\r\n";

    Browser[] availableBrowsers;
    //availableBrowsers ~= new Browser("ie",      args.testNumber, args.moduleName, args.host, args.port),  // windows only
    availableBrowsers ~= new Browser("firefox", args.testNumber, args.moduleName, args.host, args.port),
    availableBrowsers ~= new Browser("chrome",  args.testNumber, args.moduleName, args.host, args.port),
    availableBrowsers ~= new Browser("safari",  args.testNumber, args.moduleName, args.host, args.port);  // mac only
    //availableBrowsers ~= new Browser("opera",   args.testNumber, args.moduleName, args.host, args.port)

    signalQUnitDone = new SignalQUnitDone();
    foreach(browser; availableBrowsers) {
        signalQUnitDone.connect(&browser.watchForQUnitDone);
    }

    // start server and run browsers
    auto vibeTid = spawn( &launchVibe, thisTid );
    receiveTimeout(dur!"seconds"(20), (SignalVibeReady _vibeReady) {
        runBrowsers(availableBrowsers);

        // when browsers are done run the report **
        externalRequest(run_report);
        auto reported = receiveTimeout(dur!"seconds"(20), (SignalReportDone _reportDone) {
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
    if (match(browserReports, regex(r"\sresult:\sF\s|^timeout:", "gm")) || timeout_counter > 0) {
        vibeStatus = 1;
    }

    writeln(vibeStatus);
    return vibeStatus;
}
