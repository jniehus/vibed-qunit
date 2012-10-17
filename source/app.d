/**
 * Vibe Server
**/

module qunit;

import vibe.vibe;
import core.thread, std.concurrency;
import std.getopt, std.stdio, std.array;
import std.process, std.conv, std.uri;

Json[] qunitResults;
string browser;
string[string] finalReport;
Tid mainTid;

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

string recordResults(Json data)
{
    qunitResults ~= data;
    return "done";
}

string prettyReport()
{
    string pass_fail;
    Json summary = null;
    string pretty_summary = null;
    string pretty_header = "\n--- !QUnit_Command_Line_Example_Tests\n";
    string pretty_browser = "browser: " ~ browser ~ "\n";
    string pretty_tests = "tests:\n";
    foreach(Json result; qunitResults) {
        if (result["action"].toString() == q{"testresults"}) {
            pretty_tests ~= "  - test:\n";
            pretty_tests ~= "      name: " ~ result["name"].toString() ~ "\n";
            pass_fail = ((result["failed"].toString() != "0") ? "F" : "P");
            pretty_tests ~= "      module: " ~ result["module"].toString() ~ "\n";
            pretty_tests ~= "      result: " ~ pass_fail ~ "\n";
            if (result["failed"].toString() != "0") {
                finalReport["result"] = "F";
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

string generateReport()
{
    finalReport["result"] = "P";
    finalReport["details"] = prettyReport();
    writeln(finalReport["details"]);
    qunitResults = null;
    send(mainTid, "qunit complete");
    return "done";
}

// delegate tasks
void processReq(HttpServerRequest req, HttpServerResponse res)
{
    string resBody;
    switch(req.json["action"].toString())
    {
    case `"browserinfo"`:
        browser = req.json["info"].toString();
        resBody = "done";
        break;
    case `"doWork"`:
        resBody = doWork(req.json);
        break;
    case `"testresults"`:
        resBody = recordResults(req.json);
        break;
    case `"suiteresults"`:
        resBody = recordResults(req.json);
        break;
    case `"generatereport"`:
        resBody = generateReport();
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
    auto settings = new HttpServerSettings;
    settings.port = 23432;
    settings.onStart = () => send(mainTid, true);

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
    int status;
    scope(exit) { send(tid, status); }

    logInfo("Running event loop...");
    try {
        startListening(); // soon to be replaced or automatic
        status = runEventLoop();
    } catch( Throwable th ){
        logError("Unhandled exception in event loop: %s", th.toString());
        status = 2;
    }
}

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
    //writeln(argz); // sub quote custom args. Example: $>vibe -- -m '"Module 2"'
    Args args = Args();
    getopt(argz,
        "testnumber|t", &args.testNumber,
        "module|m",     &args.moduleName);

    auto url = buildURL(args);
    Browser[string] availableBrowsers = [
        // windows: "ie": Browser("iexplore.exe", "C:\\Program Files\\Internet Explorer\\iexplore.exe")
        "safari":  Browser("Safari"),
        "chrome":  Browser("Google Chrome"),
        "firefox": Browser("Firefox"),
        "opera":   Browser("Opera")
    ];

    // start server and run available browsers
    auto vibeTid = spawn( &launchVibe, thisTid );
    if (receiveTimeout(dur!"seconds"(10), (bool vibeReady) {})) {
        foreach(string browser, Browser obj; availableBrowsers) {
            availableBrowsers[browser].open(url);
            if (!receiveTimeout(dur!"seconds"(5), (string qunitDone) {})) {
                writeln(browser ~ " timed out!");
            }
            availableBrowsers[browser].close();
        }
        externalStopVibe();
    }

    // stop server after a period of time if it doesnt close by itself
    int vibeStatus = 2; // 2 = some error occured
    auto received = receiveTimeout( dur!"seconds"(10), (int _vibeStatus) {
        vibeStatus = _vibeStatus;
    });
    if (!received) { externalStopVibe(); }

    writeln(vibeStatus);
    return vibeStatus;
}
