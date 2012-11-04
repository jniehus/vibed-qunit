/**
 *  browser.d
**/

module browser;

// phobos
import std.concurrency, std.regex;
import std.stdio, std.process, std.uri;

string buildURL(string testNumber = null, string moduleName = null)
{
    string baseUrl = "http://localhost:23432/index.html";
    string url = baseUrl;
    if (testNumber != null) {
        url = baseUrl ~ "?testNumber=" ~ testNumber;
    }

    // modules take precedence
    if (moduleName != null) {
        url  = baseUrl ~ "?module=" ~ moduleName;
    }

    url = std.uri.encode(url);
    return url;
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
    string location;

    string escapeCmdLineChars(string cmdStr)
    {
        auto nonAlpha = std.regex.regex(r"[^a-zA-Z]","g");
        version(Windows)
        {
            return std.regex.replace(cmdStr, nonAlpha, "^$&");
        }
        version(linux)
        {
            return std.regex.replace(cmdStr, nonAlpha, "\\$&");
        }
    }

    void open(string url = "www.nasa.gov")
    {
        writeln("opening " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "` ~ name ~ `" to open location "` ~ url ~ `"'`));
        }
        else
        {
            url = escapeCmdLineChars(url);
            spawn( &startBrowser, thisTid, location, url );
        }
    }

    void close()
    {
        writeln("closing " ~ name ~ "...");
        version(OSX)
        {
            writeln(shell(`osascript -e 'tell application "` ~ name ~ `" to quit'`));
        }
        version(Windows)
        {
            writeln( shell("taskkill /F /im " ~ name) );
        }
        version(linux)
        {
            writeln( shell("pkill " ~ name) );
        }
    }
}