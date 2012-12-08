/**
 *  browser.d
**/

module browser;

// phobos
import std.concurrency, std.regex;
import std.stdio, std.process, std.uri, std.path, std.file;

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

void startBrowser(Tid tid, string location, string url)
{
    try {
        writeln( shell("\"" ~ location ~ "\" " ~ url) );
    }
    catch {
        send(tid, 1);
    }
}

struct Browser
{
    string name;
    string cmdName;

    this(string name)
    {
        this.name    = name;
        this.cmdName = info[name];
    }

    string escapeCmdLineChars(string cmdStr)
    {
        string escapeCmdStr;
        auto nonAlpha = std.regex.regex(r"[^a-zA-Z]","g");
        version(Windows)
        {
            escapeCmdStr = std.regex.replace(cmdStr, nonAlpha, "^$&");
        }
        version(linux)
        {
            escapeCmdStr = std.regex.replace(cmdStr, nonAlpha, "\\$&");
        }
        return escapeCmdStr;
    }

    void open(string url = "www.nasa.gov")
    {
        writeln("opening " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "` ~ cmdName ~ `" to open location "` ~ url ~ `"'`));
        }
        else
        {
            url = escapeCmdLineChars(url);
            spawn( &startBrowser, thisTid, cmdName, url );
        }
    }

    void close()
    {
        writeln("closing " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "` ~ cmdName ~ `" to quit'`));
        }
        version(Windows)
        {
            string exeName = baseName(cmdName);
            writeln( shell("taskkill /F /im " ~ exeName) );
        }
        version(linux)
        {
            string exeName = baseName(cmdName);
            // pkill "google-chrome" doesnt work but `pkill chrome` does
            if (exeName == "google-chrome") { exeName = "chrome"; }
            writeln( shell("pkill " ~ exeName) );
        }
    }
}