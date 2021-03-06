/**
 *  report.d
**/

module report;

// vibe
import vibe.data.json;

// phobos
import std.parallelism;
import std.array, std.string, std.stdio;

string parseAsserts(Json[] asserts)
{
    string[] assertStrings;
    foreach(Json assertion; asserts) {
        string assert_string = "  - message: " ~ assertion["message"].toString().strip() ~ "\n";
        if (assertion["expected"].toString() != "undefined") {
            assert_string ~=   "    " ~ assertion["expected"].toString().replace("\"","").replace("\\", "").strip() ~ "\n";
        }
        if (assertion["result"].toString()   != "undefined") {
            assert_string ~=   "    " ~ assertion["result"].toString().replace("\"","").replace("\\", "").strip()   ~ "\n";
        }
        if (assertion["diff"].toString()     != "undefined") {
            assert_string ~=   "    " ~ assertion["diff"].toString().replace("\"","").replace("\\", "").strip()     ~ "\n";
        }
        if (assertion["source"].toString()   != "undefined") {
            assert_string ~=   "    " ~ assertion["source"].toString().replace("\"","").replace("\\", "").strip()   ~ "\n";
        }
        assertStrings ~= assert_string;
    }
    return std.array.join(assertStrings);
}

string[] parseTests(Json[] tests, ref Json summary)
{
    string[] testStrings;
    foreach(result; taskPool.parallel(tests, 1)) {
        if (result["action"].toString() == `"testresults"`) {
            string test_string =  "- name: "   ~ result["name"].toString() ~ "\n";
                   test_string ~= "  module: " ~ result["module"].toString() ~ "\n";
                   test_string ~= "  result: " ~ ((result["failed"].toString() != "0") ? "F" : "P") ~ "\n";
            if (result["failed"].toString() != "0") {
                test_string ~= "  assertions:\n";
                Json[] assertions = cast(Json[]) result["assertions"];
                test_string ~= parseAsserts(assertions);
                synchronized {
                    testStrings ~= test_string;
                }
            }
        }
        else if (result["action"].toString() == `"suiteresults"`) {
            summary = result;
        }
    }
    return testStrings;
}

string prettyReport(Json[] browserResults)
{
    Json summary = null;
    string pretty_summary = null;
    string pretty_header  = "\n--- !QUnit_Results\n";
    string pretty_browser = "browser: " ~ browserResults[0]["browser"].toString() ~ "\n";
    string pretty  = pretty_header ~ pretty_browser;
    string[] tests = parseTests(browserResults, summary);
    if (tests.length != 0 ) {
        string pretty_tests = "failed_tests:\n";
        pretty_tests ~= std.array.join(tests);
        pretty ~= pretty_tests;
    }
    if (summary != null) {
        pretty_summary = "summary:\n";
        pretty_summary ~= "  failed: "  ~ summary["failed"].toString()  ~ "\n";
        pretty_summary ~= "  passed: "  ~ summary["passed"].toString()  ~ "\n";
        pretty_summary ~= "  total: "   ~ summary["total"].toString()   ~ "\n";
        pretty_summary ~= "  runtime: " ~ summary["runtime"].toString() ~ "\n";
        pretty ~= pretty_summary;
    }
    else {
        pretty ~= "timeout: the browser stopped repsonding!\n";
    }
    return pretty;
}

string generatePrettyReport(Json[][string] qunitResults)
{
    string fancyReport = "";
    foreach(browserResults; taskPool.parallel(qunitResults.byValue(), 1)) {
        synchronized {
            string browserReport = prettyReport(browserResults);
            fancyReport ~= browserReport;
            //File(getBrowserName(browserResults[0]["browser"]) ~ "_report.yml", "w").write(browserReport);
        }
    }
    return fancyReport;
}