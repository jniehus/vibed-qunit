/**
 * Vibe Server
 */

module app;

// vibe
import vibe.d;

// phobos
import core.thread;
import std.algorithm;
import std.concurrency, std.parallelism;
import std.getopt, std.stdio, std.array, std.conv;
import std.process, std.uri, std.regex, std.file;

// local
import browser, report, vibeSignals;

alias STid             = std.concurrency.Tid;
alias s_receive        = std.concurrency.receive;
alias s_receiveTimeout = std.concurrency.receiveTimeout;

alias VTid             = vibe.core.concurrency.Tid;
alias v_receive        = vibe.core.concurrency.receive;
alias v_receiveTimeout = vibe.core.concurrency.receiveTimeout;

// global variables shared between vibe and main
__gshared STid            mainTid;
__gshared string          host;
__gshared ushort          port;
__gshared SignalQUnitDone signalQUnitDone;

// vibe module variables
Json[][string]  qunitResults;

//--- VIBE SERVER THREAD ---
void handleRequest( HTTPServerRequest  req,
                    HTTPServerResponse res )
{
	res.redirect("/index.html");
}

void stopVibe( HTTPServerRequest  req = null,
               HTTPServerResponse res = null )
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
    synchronized {
        string name = to!string(data["browser"]);
        signalQUnitDone.message(name ~ " done");
    }
    return "done";
}

// delegate tasks
void processReq( HTTPServerRequest  req,
                 HTTPServerResponse res )
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
        case `"qunitdone"`:
            resBody = qUnitDone(req.json); break;
        case `"stopvibe"`:
            stopVibe(); break;
        default:
            resBody = "fail";
    }

    res.writeBody(resBody);
}

void runReport( HTTPServerRequest  req = null,
                HTTPServerResponse res = null )
{
    string browserReports = generatePrettyReport(qunitResults);
    send(mainTid, SignalReportDone(true, browserReports));
}

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = 8080;

    auto router = new URLRouter;
    router.get("/", &handleRequest);
    router.get("*", serveStaticFiles("./public/"));
    router.post("/process_req", &processReq);
    router.get( "/runreport",   &runReport);
    router.get( "/stopvibe",    &stopVibe);

    writefln("VIBE> PORT: %s", port);
    writeln("VIBE> begin listen");
    listenHTTP(settings, router);
}

//--- MAIN THREAD ---
void launchVibe(STid tid)
{
    mainTid = tid;
    logInfo("Running event loop...");
    try {
        send(tid, SignalVibeStatus( runEventLoop() ));
    } catch( Throwable th ){
        logError("Unhandled exception in event loop: %s", th.toString());
        send(tid, SignalVibeStatus(200));
    }
}

void externalRequest(string req, STid tid)
{
    try {
        auto reqVibeConn = connectTCP(host, port);
        scope(exit) reqVibeConn.close();
        reqVibeConn.write(req);
    }
    catch {
        writeln("REQ> %s", req);
        send(tid, SignalVibeStatus(300));
    }
}

void listenForVibe(STid tid)
{
    int   count = 0;
    bool  ready = false;
    while(!ready && count < 3) {
        try {
            logInfo("READY?> Attempting to connect to vibe @ %s:%s", host, port);
            auto sock = connectTCP(host, port);
            scope(exit) sock.close();
            writeln("READY?> Connection successful");
            ready = true;
            send(tid, SignalVibeReady(ready));
        }
        catch(Exception e) {
            writeln("READY?> Couldn't connect");
            sleep(dur!"seconds"(1));
            count++;
        }
    }

    if (!ready) {
        send(tid, SignalVibeReady(ready));
    }
}

bool waitFor(ref bool condition, int timeout = 10)
{
    int count = 0;
    while(!condition && count < timeout) {
        sleep(dur!"seconds"(1));
        count++;
    }
    return !(count == timeout);
}

void runBrowsers(Browser[] availableBrowsers, ref int timeout_counter)
{
    signalQUnitDone = new SignalQUnitDone();
    timeout_counter = 0;
    foreach(browser; taskPool.parallel(availableBrowsers, 1)) {
        signalQUnitDone.connect(&browser.watchForQUnitDone);
        browser.open();
        if (!waitFor(browser.done)) {
            timeout_counter++;
            writeln(browser.name ~ " timed out!");
        }
        signalQUnitDone.disconnect(&browser.watchForQUnitDone);
        browser.close();
    }
}

struct Args
{
    string testNumber = null;
    string moduleName = null;
    string host = "127.0.0.1";
    string port = "8080";
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
    //availableBrowsers ~= new Browser("ie",      args.testNumber, args.moduleName, args.host, args.port);  // windows only
    availableBrowsers ~= new Browser("firefox", args.testNumber, args.moduleName, args.host, args.port);
    //availableBrowsers ~= new Browser("chrome",  args.testNumber, args.moduleName, args.host, args.port);
    //availableBrowsers ~= new Browser("safari",  args.testNumber, args.moduleName, args.host, args.port);  // mac only
    //availableBrowsers ~= new Browser("opera",   args.testNumber, args.moduleName, args.host, args.port);

    // start server and run browsers
    string report;
    int timeout_counter;
    auto vibeTid = spawn( &launchVibe, thisTid );
    listenForVibe(thisTid);
    s_receiveTimeout(dur!"seconds"(20), (SignalVibeReady _vibeReady) {
        if (_vibeReady.isReady) {
            runBrowsers(availableBrowsers, timeout_counter);

            // when browsers are done run the report **
            externalRequest(run_report, thisTid);
            auto reported = s_receiveTimeout(dur!"seconds"(20), (SignalReportDone _reportDone) {
                report = _reportDone.report;
                writeln(_reportDone.report);
            });
        }
        else {
            writeln("READY?> couldn't reach vibe");
        }
    });

    // stop the server
    externalRequest(stop_vibe, thisTid);
    int vibeStatus = 100;
    s_receive(
        (SignalVibeStatus _vStatus) { vibeStatus = _vStatus.status; }
    );


    // parse results
    if (match(report, regex(r"\sresult:\sF\s|^timeout:", "gm")) || timeout_counter > 0) {
        vibeStatus = 1;
    }

    writeln("FIN> VibeStatus: %s", vibeStatus);
    return vibeStatus;
}