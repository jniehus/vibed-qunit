/**
 *  report.d
**/

module report;

// vibe
import vibe.data.json;

// phobos
import std.array, std.string;

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

string parseAsserts(Json[] asserts)
{
    string[] assertStrings;
    foreach(Json assertion; asserts) {
        string assert_string = "        - assert:\n";
        if (assertion["message"].toString()  != "undefined") {
            assert_string ~= "            message: " ~ assertion["message"].toString().strip() ~ "\n";
        }
        if (assertion["expected"].toString() != "undefined") {
            assert_string ~= "            " ~ assertion["expected"].toString().replace("\"","").replace("\\", "").strip() ~ "\n";
        }
        if (assertion["result"].toString()   != "undefined") {
            assert_string ~= "            " ~ assertion["result"].toString().replace("\"","").replace("\\", "").strip()   ~ "\n";
        }
        if (assertion["diff"].toString()     != "undefined") {
            assert_string ~= "            " ~ assertion["diff"].toString().replace("\"","").replace("\\", "").strip()     ~ "\n";
        }
        if (assertion["source"].toString()   != "undefined") {
            assert_string ~= "            " ~ assertion["source"].toString().replace("\"","").replace("\\", "").strip()   ~ "\n";
        }
        assertStrings ~= assert_string;
    }
    return std.array.join(assertStrings);
}

string parseTests(Json[] tests, ref Json summary)
{
    string[] testStrings;
    foreach(Json result; tests) {
        if (result["action"].toString() == `"testresults"`) {
            string test_string = "  - test:\n";
            test_string ~= "      name: "   ~ result["name"].toString() ~ "\n";
            test_string ~= "      module: " ~ result["module"].toString() ~ "\n";
            test_string ~= "      result: " ~ ((result["failed"].toString() != "0") ? "F" : "P") ~ "\n";
            if (result["failed"].toString() != "0") {
                test_string ~= "      assertions:\n";
                Json[] assertions = cast(Json[]) result["assertions"];
                test_string ~= parseAsserts(assertions);
            }
            testStrings ~= test_string;
        }
        else if (result["action"].toString() == `"suiteresults"`) {
            summary = result;
        }
    }
    return std.array.join(testStrings);
}

string prettyReport(Json[] browserResults)
{
    Json summary = null;
    string pretty_summary = null;
    string pretty_header = "\n--- !QUnit_Command_Line_Example_Tests\n";
    string pretty_browser = "browser: " ~ browserResults[0]["browser"].toString() ~ "\n";
    string pretty_tests = "tests:\n";
    pretty_tests ~= parseTests(browserResults, summary);
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

string generatePrettyReport(Json[][string] qunitResults)
{
    string fancyReport = "";
    foreach(string browser, Json[] browserResults; qunitResults) {
        fancyReport ~= prettyReport(browserResults);
    }
    return fancyReport;
}