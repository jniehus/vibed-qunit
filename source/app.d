/**
 * Vibe Server
**/

module app;

import vibe.vibe;
import core.thread;
import std.concurrency, std.parallelism;
import std.getopt, std.stdio, std.array;
import std.process, std.uri;

Json[][string]  qunitResults;
shared string[] browserReports;
Tid             mainTid;

struct SignalVibeReady
{
    bool isReady = false;
}

struct SignalQUnitDone
{
    bool isDone = false;
}

struct SignalVibeStatus
{
    int status;
}

struct Browser
{
    string name;
    string location;

    void open(string url = "www.nasa.gov")
    {
        writeln("opening " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "`~ name ~`" to open location "`~ url ~ `"'`));
        }
        else
        {
            // windows/posix => Thread( "location" "url" )
            // windows: "c:\path\iexplore.exe" "url"
            // linux: /usr/bin/firefox "url"
            writeln("not implemented");
        }
    }

    void close()
    {
        writeln("closing " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "`~ name ~`" to quit'`));
        }
        version(Windows)
        {
            // windows: taskkill /F /im "name"
            writeln("not implemented");
        }
        version(linux)
        {
            // linux: pkill "name"
            writeln("not implemented");
        }
    }
}

// host the test
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

string getBrowserName(Json browserData)
{
    string name = "unknown";
    if (browserData["chrome"].toString() == "true") {
        name = "chrome";
    }
    else if (browserData["mozilla"].toString() == "true") {
        name = "firefox";
    }
    else if (browserData["opera"].toString()   == "true") {
        name = "opera";
    }
    else if (browserData["safari"].toString()  == "true") {
        name = "safari";
    }
    return name;
}

string recordResults(Json data)
{
    /*
      this is a good place to store results to mongoDB:
      db->app->tests->qunit->browser->testRun->result

      then a report generator will pull data from the
      last testRun for each browser
    */

    auto browserName = getBrowserName(data["browser"]);
    qunitResults[browserName] ~= data;
    return "done";
}

string prettyReport(string browserName)
{
    string pass_fail;
    Json summary = null;
    string pretty_summary = null;
    string pretty_header = "\n--- !QUnit_Command_Line_Example_Tests\n";
    string pretty_browser = "browser: " ~ qunitResults[browserName][0]["browser"].toString() ~ "\n";
    string pretty_tests = "tests:\n";
    foreach(Json result; qunitResults[browserName]) {
        if (result["action"].toString() == q{"testresults"}) {
            pretty_tests ~= "  - test:\n";
            pretty_tests ~= "      name: " ~ result["name"].toString() ~ "\n";
            pass_fail = ((result["failed"].toString() != "0") ? "F" : "P");
            pretty_tests ~= "      module: " ~ result["module"].toString() ~ "\n";
            pretty_tests ~= "      result: " ~ pass_fail ~ "\n";
            if (result["failed"].toString() != "0") {
                pretty_tests ~= "      assertions:\n";
                foreach(Json assertion; result["assertions"]) {
                    pretty_tests ~= "        - assert:\n";
                    if (assertion["message"].toString() != "undefined") {
                        pretty_tests ~= "           message: " ~ assertion["message"].toString() ~ "\n";
                    }
                    if (assertion["expected"].toString() != "undefined") {
                        pretty_tests ~= "           " ~ assertion["expected"].toString().replace("\"","").replace("\\", "") ~ "\n";
                    }
                    if (assertion["result"].toString() != "undefined") {
                        pretty_tests ~= "           " ~ assertion["result"].toString().replace("\"","").replace("\\", "")   ~ "\n";
                    }
                    if (assertion["diff"].toString() != "undefined") {
                        pretty_tests ~= "           " ~ assertion["diff"].toString().replace("\"","").replace("\\", "")     ~ "\n";
                    }
                    if (assertion["source"].toString() != "undefined") {
                        pretty_tests ~= "           " ~ assertion["source"].toString().replace("\"","").replace("\\", "")   ~ "\n";
                    }
                }
            }
        }
        else if (result["action"].toString() == q{"suiteresults"}) {
            summary = result;
        }
    }

    string pretty = pretty_header ~ pretty_browser ~ pretty_tests;
    if (summary != null) {
        pretty_summary = "summary:\n";
        pretty_summary ~= "  failed: "  ~ summary["failed"].toString() ~ "\n";
        pretty_summary ~= "  passed: "  ~ summary["passed"].toString() ~ "\n";
        pretty_summary ~= "  total: "   ~ summary["total"].toString()  ~ "\n";
        pretty_summary ~= "  runtime: " ~ summary["runtime"].toString() ~ "\n";
        pretty ~= pretty_summary;
    }

    return pretty;
}

string qUnitDone(Json data)
{
    auto browserName = getBrowserName(data["browser"]);
    browserReports  ~= prettyReport(browserName);
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

static this()
{
    qunitResults = null;

    auto settings = new HttpServerSettings;
    settings.port = 23432;
    settings.onStart = () => send(mainTid, SignalVibeReady(true));

    auto router = new UrlRouter;
    router.get("/", &handleRequest);
    router.get("*", serveStaticFiles("./public/"));
    router.post("/process_req", &processReq);
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
        send(tid, 2);
    }
}

//---

void externalStopVibe()
{
    auto stopVibeConn = connectTcp("localhost", 23432);
    scope(exit) stopVibeConn.close();
    stopVibeConn.write("GET /stopvibe HTTP/1.1\r\n"
                        "Host: localhost:23432\r\n"
                        "\r\n");
}

string buildURL(Args args)
{
    string baseUrl = "http://localhost:23432/index.html";
    string url = baseUrl;
    if (args.testNumber != null) {
        url = baseUrl ~ "?testNumber=" ~ args.testNumber;
    }

    // modules take precedence
    if (args.moduleName != null) {
        url  = baseUrl ~ "?module=" ~ args.moduleName;
    }

    url = std.uri.encode(url);
    return url;
}

struct Args
{
    string testNumber = null;
    string moduleName = null;
}

// returns 0 if pass
// returns 1 if fail
// returns 2 if something went haywire
int main(string[] argz)
{
    //writeln(argz); // sub quote custom args. Example: ~/vibed-qunit$>vibe -- -m '"Module 2"'
    Args args = Args();
    getopt(argz,
        "testnumber|t", &args.testNumber,
        "module|m",     &args.moduleName);

    auto url = buildURL(args);
    Browser[] availableBrowsers = [
        // windows: "ie": Browser("iexplore.exe", "C:\\Program Files\\Internet Explorer\\iexplore.exe")
        Browser("Safari"),
        Browser("Google Chrome"),
        //"firefox": Browser("Firefox"),
        Browser("Opera")
    ];

    // start server and run available browsers
    auto vibeTid = spawn( &launchVibe, thisTid );
    if (receiveTimeout(dur!"seconds"(10), (SignalVibeReady _vibeReady) {})) {
        foreach(Browser browser; taskPool.parallel(availableBrowsers, 5)) {
            browser.open(url);
            if (!receiveTimeout(dur!"seconds"(5), (SignalQUnitDone _qunitDone) {})) {
                writeln(browser.name ~ " timed out!");
            }
            browser.close();
        }
        externalStopVibe();
    }

    // stop server after a period of time if it doesnt close by itself
    int vibeStatus = 2; // 2 = some error occured
    auto received  = receiveTimeout(dur!"seconds"(10), (SignalVibeStatus _vibeStatus) {
        vibeStatus = _vibeStatus.status;
    });
    if (!received) { externalStopVibe(); }

    foreach(report; browserReports) {
        writeln(report);
    }
    writeln(vibeStatus);
    return vibeStatus;
}
