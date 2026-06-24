module geo_parser;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.string;

import dxml.dom;
import dxml.parser : EntityType;

import geo_model;

GeoModel parseGeoFile(string path)
{
    import std.file : readText;
    return parseGeoXml(readText(path));
}

GeoModel parseGeoXml(string xmlText)
{
    auto doc = parseDOM!simpleXML(xmlText);
    auto geo = findGeoElement(doc);

    auto name = getAttribute(geo, "name");
    if (name.length == 0)
        throw new Exception("Geo element requires a name attribute");

    auto model = GeoModel(name);
    model.vertices = parseFloatArray(getChildText(geo, "vertex"));
    model.normals = parseFloatArray(getChildText(geo, "normal"));
    model.colors = parseFloatArray(getChildText(geo, "color"));
    model.uvs = parseFloatArray(getChildText(geo, "uv"));
    model.indices = parseUIntArray(getChildText(geo, "indices"));

    if (model.vertices.length == 0 || model.vertices.length % 3 != 0)
        throw new Exception("Invalid vertex array");

    if (model.indices.length == 0 || model.indices.length % 3 != 0)
        throw new Exception("Invalid indices array");

    if (model.normals.length == 0)
    {
        model.normals.length = model.vertices.length;
        for (size_t i = 0; i < model.vertexCount; ++i)
        {
            model.normals[i * 3 + 0] = 0.0f;
            model.normals[i * 3 + 1] = 0.0f;
            model.normals[i * 3 + 2] = 1.0f;
        }
    }

    if (model.normals.length != model.vertices.length)
        throw new Exception("Vertex and normal array lengths do not match");

    foreach (index; model.indices)
    {
        if (index >= model.vertexCount)
            throw new Exception("Index out of range: " ~ index.to!string);
    }

    return model;
}

private DOMEntity!string findGeoElement(DOMEntity!string doc)
{
    foreach (child; doc.children)
    {
        if (child.type == EntityType.elementStart && child.name == "Geo")
            return child;
    }

    throw new Exception("Geo element not found in XML document");
}

private string getAttribute(DOMEntity!string element, string attributeName)
{
    foreach (attr; element.attributes)
    {
        if (attr.name == attributeName)
            return attr.value.idup;
    }

    return "";
}

private string getChildText(DOMEntity!string parent, string tagName)
{
    foreach (child; parent.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        if (child.name != tagName)
            continue;

        foreach (textNode; child.children)
        {
            if (textNode.type == EntityType.text)
                return textNode.text.idup;
        }

        return "";
    }

    return "";
}

private float[] parseFloatArray(string text)
{
    if (text.strip.length == 0)
        return [];

    float[] values;
    foreach (token; text.replace(",", " ").splitter)
    {
        auto trimmed = token.strip;
        if (trimmed.length == 0)
            continue;
        values ~= to!float(trimmed);
    }

    return values;
}

private uint[] parseUIntArray(string text)
{
    if (text.strip.length == 0)
        return [];

    uint[] values;
    foreach (token; text.splitter)
    {
        auto trimmed = token.strip;
        if (trimmed.length == 0)
            continue;
        values ~= to!uint(trimmed);
    }

    return values;
}
