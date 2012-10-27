/**
 *  browser.d
**/

module browser;

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
            // windows/posix => spawn( &startBrowser, "location", "url" )
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
            // windows: taskkill /im "name"
            writeln("not implemented");
        }
        version(linux)
        {
            // linux: pkill "name"
            writeln("not implemented");
        }
    }
}