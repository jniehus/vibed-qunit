/**
 * browser.d
 */

module browser;

// phobos
import core.thread;
import std.concurrency, std.regex;
import std.stdio, std.process, std.uri, std.path, std.file;

import core.sys.posix.signal: SIGKILL;

version(OSX)
{
    enum string[string] info = [
        "chrome"  : "Google Chrome",
        "safari"  : "Safari",
        "firefox" : "Firefox",
        "opera"   : "Opera"
    ];
}
version(Windows)
{
    enum string[string] info = [
        "chrome"  : "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "ie"      : "C:\\Program Files\\Internet Explorer\\iexplore.exe",
        "firefox" : "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
        "opera"   : "C:\\Program Files\\Opera\\opera.exe"
    ];
}
version(linux)
{
    enum string[string] info = [
        "chrome"  : "/usr/bin/google-chrome",
        "firefox" : "/usr/bin/firefox"
    ];
}

class Browser
{
    string name;
    string cmdName;
    string testNumber;
    string moduleName;
    string host;
    string port;
    string url;
    bool   done = false;
    Pid    browser_exe;

    this(string name, string testNumber = null, string moduleName = null, string host = "localhost", string port = "34000")
    {
        this.name       = name;
        this.cmdName    = info[name];
        this.testNumber = testNumber;
        this.moduleName = moduleName;
        this.host       = host;
        this.port       = port;
        this.url        = buildURL();
    }

    // slot
    void watchForQUnitDone(string msg)
    {
        if (msg == ("\"" ~ name ~ "\"" ~ " done")) {
            done = true;
        }
    }

    string buildURL()
    {
        string baseUrl = "http://" ~ host ~ ":" ~ port ~ "/index.html";
        string url = baseUrl;
        if (testNumber) {
            url = baseUrl ~ "?testNumber=" ~ testNumber;
        }

        // modules take precedence
        if (moduleName) {
            url = baseUrl ~ "?module=" ~ moduleName;
        }

        // set browser
        if (testNumber || moduleName) {
            url ~= "&browser=";
        }
        else {
            url ~= "?browser=";
        }
        url ~= name;

        url = std.uri.encode(url);
        return url;
    }

    void escapeCmdLineChars(ref string cmdUrl)
    {
        string escapeCmdStr;
        auto nonAlpha = std.regex.regex(r"[^a-zA-Z]","g");
        version(Windows)
        {
            escapeCmdStr = std.regex.replace(cmdUrl, nonAlpha, "^$&");
        }
        version(linux)
        {
            escapeCmdStr = std.regex.replace(cmdUrl, nonAlpha, "\\$&");
        }
    }

    void open()
    {
        writeln("opening " ~ name ~ " to " ~ url);
        version(OSX)
        {
            executeShell(`osascript -e 'tell application "` ~ cmdName ~ `" to open location "` ~ url ~ `"'`);
        }
        else
        {
            escapeCmdLineChars(url);
            browser_exe = spawnProcess( [cmdName, url] );
        }
    }

    void close()
    {
        writeln("closing " ~ name ~ "...");
        version(OSX)
        {
            executeShell(`osascript -e 'tell application "` ~ cmdName ~ `" to quit'`);
        }
        version(Windows)
        {
            kill( browser_exe, 10 );
            wait( browser_exe );
        }
        version(linux)
        {
            kill( browser_exe, SIGKILL );
            wait( browser_exe );
        }
    }
}