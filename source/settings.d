module settings;

import std.file;
import std.json;
import std.path;
import std.process : environment;
import std.stdio;

struct AppSettings
{
    string lastModelPath;

    JSONValue toJson() const
    {
        JSONValue result = JSONValue.emptyObject;
        result["lastModelPath"] = JSONValue(lastModelPath);
        return result;
    }

    static AppSettings fromJson(JSONValue value)
    {
        AppSettings result;
        if ("lastModelPath" in value && value["lastModelPath"].type == JSONType.string)
            result.lastModelPath = value["lastModelPath"].str;
        return result;
    }
}

string settingsFilePath()
{
    string dir = configDir();
    if (dir.length == 0)
        return "";
    return buildPath(dir, "settings.json");
}

AppSettings loadSettings()
{
    immutable path = settingsFilePath();
    if (path.length == 0 || !exists(path))
        return AppSettings.init;

    try
    {
        return AppSettings.fromJson(parseJSON(readText(path)));
    }
    catch (Exception ex)
    {
        writeln("Settings load skipped: ", ex.msg);
        return AppSettings.init;
    }
}

void saveLastModelPath(string modelPath)
{
    if (modelPath.length == 0)
        return;

    immutable path = settingsFilePath();
    if (path.length == 0)
        return;

    try
    {
        AppSettings settings;
        settings.lastModelPath = absolutePath(modelPath);
        immutable dir = dirName(path);
        if (!exists(dir))
            mkdirRecurse(dir);
        std.file.write(path, settings.toJson().toPrettyString());
    }
    catch (Exception ex)
    {
        writeln("Settings save skipped: ", ex.msg);
    }
}

private string configDir()
{
    version (Windows)
    {
        string base = environment.get("APPDATA", "");
        if (base.length == 0)
            return "";
        return buildPath(base, "ModelViewer");
    }
    else version (linux)
    {
        string base = environment.get("XDG_CONFIG_HOME", "");
        if (base.length == 0)
        {
            string home = environment.get("HOME", "");
            if (home.length == 0)
                return "";
            base = buildPath(home, ".config");
        }
        return buildPath(base, "modelviewer");
    }
    else
    {
        string home = environment.get("HOME", "");
        if (home.length == 0)
            return "";
        return buildPath(home, ".config", "modelviewer");
    }
}
