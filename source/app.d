/**
 * Vibe Server
 */

module app;

// vibe
import vibe.d;

// phobos
import core.thread;

import std.algorithm
     , std.concurrency
     , std.parallelism
     , std.getopt
     , std.stdio
     , std.array
     , std.conv
     , std.process
     , std.uri
     , std.regex
     , std.file;

// local
import browser
     , report
     , vibeSignals;

alias STid             = std.concurrency.Tid;
alias s_receive        = std.concurrency.receive;
alias s_receiveTimeout = std.concurrency.receiveTimeout;

alias VTid             = vibe.core.concurrency.Tid;
alias v_receive        = vibe.core.concurrency.receive;
alias v_receiveTimeout = vibe.core.concurrency.receiveTimeout;

// global variables shared between vibe and main
__gshared STid            mainTid;
__gshared SignalQUnitDone signalQUnitDone;

immutable string host = "127.0.0.1";
immutable ushort port = 8080;

private string qu_report;
private int    timeout_counter;

// vibe module variables
Json[][string]  qunitResults;

//--- VIBE SERVER THREAD ---
void stopVibe()
{
    writeln("exiting event loop");
    exitEventLoop();
}

void handleRequest( HTTPServerRequest  req,
                    HTTPServerResponse res )
{
	res.redirect("/index.html");
}

void stopVibeReq( HTTPServerRequest  req,
                  HTTPServerResponse res )
{
    writeln("stopping vibe");
    stopVibe();
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

void runReport( HTTPServerRequest  req,
                HTTPServerResponse res )
{
    string browserReports = generatePrettyReport(qunitResults);
    send(mainTid, SignalReportDone(true, browserReports));
}

shared static this()
{
    auto settings = new HTTPServerSettings;
    settings.port = port;

    auto router = new URLRouter;
    router.get("/", &handleRequest);
    router.get("*", serveStaticFiles("./public/"));
    router.get("/runreport",    &runReport);
    router.get("/stopvibe",     &stopVibeReq);
    router.post("/process_req", &processReq);

    listenHTTP(settings, router);
}

//--- MAIN THREAD ---
void launchVibe(STid tid)
{
    writeln("Running event loop...");
    try {
        send(tid, SignalVibeStatus( runEventLoop() ));
    } catch( Throwable th ){
        writefln("Unhandled exception in event loop: %s", th.toString());
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
        send(tid, SignalVibeStatus(300));
    }
}

void listenForVibe(STid tid)
{
    int   count = 0;
    bool  ready = false;
    while(!ready && count < 3) {
        try {
            auto sock = connectTCP(host, port);
            scope(exit) sock.close();
            ready = true;
            send(tid, SignalVibeReady(ready));
        }
        catch(Exception e) {
            sleep(1.seconds);
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
        sleep(1.seconds);
        count++;
    }
    return (count < timeout);
}

void runBrowsers(Browser[] availableBrowsers)
{
    signalQUnitDone = new SignalQUnitDone();
    foreach(browser; taskPool.parallel(availableBrowsers, 10)) {
        signalQUnitDone.connect(&browser.watchForQUnitDone);
        browser.open();
        if (!waitFor(browser.done)) {
            timeout_counter++;
            writefln("%s timed out!", browser.name);
        }
        signalQUnitDone.disconnect(&browser.watchForQUnitDone);
        browser.close();
    }
}

Browser[] getAvailableBrowsers(Args args)
{
    Browser[] availableBrowsers;
    Json pkgInfo = parseJsonString(readText("./package.json"));
    string[] browsers;
    deserializeJson(browsers, pkgInfo["available_browsers"]);
    foreach(browser; browsers) {
        availableBrowsers ~= new Browser(
            browser,
            args.testNumber,
            args.moduleName,
            host,
            to!string(port)
        );
    }
    return availableBrowsers;
}

struct Args
{
    string testNumber;
    string moduleName;
}

// returns -1 if something unexpected happened
// returns  0 if pass
// returns  1 if fail
// returns  2 if vibe server took a shit
int main(string[] argz)
{
    mainTid = thisTid;

    //writeln(argz); // sub quote custom args. Example: ~/vibed-qunit$>vibe -- -m '"Module 2"'
    Args args = Args();
    getopt(argz,
        "testnumber|t", &args.testNumber,
        "module|m",     &args.moduleName,
    );

    // set external call strings
    string stop_vibe  = "GET /stopvibe HTTP/1.1\r\n"  "Host: " ~ host ~ ":" ~ to!string(port) ~ "\r\n\r\n";
    string run_report = "GET /runreport HTTP/1.1\r\n" "Host: " ~ host ~ ":" ~ to!string(port) ~ "\r\n\r\n";

    Browser[] availableBrowsers = getAvailableBrowsers(args);

    // start server and run browsers
    spawn( &launchVibe, thisTid );
    listenForVibe(thisTid);

    assert(
        s_receiveTimeout(
            5.seconds,
            (SignalVibeReady vibeReady) {
                runBrowsers(availableBrowsers);

                // when browsers are done run the report **
                externalRequest(run_report, thisTid);
                assert(
                    s_receiveTimeout(
                        5.seconds,
                        (SignalReportDone reportDone) {
                            qu_report = reportDone.report;
                            writeln( reportDone.report );
                    }),
                    "Didn't receive report!"
                );
        }),
        "Couldn't reach vibe instance!"
    );

    // stop the server
    externalRequest(stop_vibe, thisTid);

    int vibeStatus = 100;
    assert(
        s_receiveTimeout(
            3.seconds,
            (SignalVibeStatus vStatus) { vibeStatus = vStatus.status; }),
        "Exit loop event never called home"
    );

    // parse results
    if (match(qu_report, regex(r"\sresult:\sF\s|^timeout:", "gm")) || timeout_counter > 0) {
        vibeStatus = 1;
    }

    writefln("VibeStatus: %s", vibeStatus);
    return vibeStatus;
}