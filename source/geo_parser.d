module geo_parser;

import std.algorithm;
import std.conv;
import std.exception;
import std.range;
import std.string;

import dxml.dom;
import dxml.parser : EntityType;

import geo_model;
import gl3n.linalg;

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

    foreach (child; geo.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        switch (child.name)
        {
        case "Triangle":
            {
                auto batch = tryParseTriangle(child);
                if (batch.isValid)
                    model.triangles ~= batch;
            }
            break;
        case "Line":
            {
                auto batch = tryParseLine(child, LineTopology.segments);
                if (batch.isValid)
                    model.lines ~= batch;
            }
            break;
        case "LineStripe":
            {
                auto batch = tryParseLine(child, LineTopology.strip);
                if (batch.isValid)
                    model.lines ~= batch;
            }
            break;
        case "LineLoop":
            {
                auto batch = tryParseLine(child, LineTopology.loop);
                if (batch.isValid)
                    model.lines ~= batch;
            }
            break;
        default:
            break;
        }
    }

    return model;
}

private TriangleBatch tryParseTriangle(DOMEntity!string element)
{
    auto vertices = parseFloatArray(getChildText(element, "vertex"));
    auto indices = parseUIntArray(getChildText(element, "indices"));

    if (vertices.length == 0 || vertices.length % 3 != 0)
        return TriangleBatch.init;
    if (indices.length == 0 || indices.length % 3 != 0)
        return TriangleBatch.init;

    auto vertexCount = vertices.length / 3;
    foreach (index; indices)
    {
        if (index >= vertexCount)
            return TriangleBatch.init;
    }

    TriangleBatch batch;
    batch.vertices = vertices;
    batch.indices = indices;
    batch.colors = parseFloatArray(getChildText(element, "color"));
    batch.uvs = parseFloatArray(getChildText(element, "uv"));
    batch.normals = parseFloatArray(getChildText(element, "normal"));

    if (batch.normals.length == 0)
    {
        batch.normals.length = batch.vertices.length;
        for (size_t i = 0; i < batch.vertexCount; ++i)
        {
            batch.normals[i * 3 + 0] = 0.0f;
            batch.normals[i * 3 + 1] = 0.0f;
            batch.normals[i * 3 + 2] = 1.0f;
        }
    }
    else if (batch.normals.length != batch.vertices.length)
    {
        return TriangleBatch.init;
    }

    batch.skeleton = parseSkeleton(element, "skelton");
    batch.vertexGroups = parseVertexGroups(element, "vertex_group");

    return batch;
}

private LineBatch tryParseLine(DOMEntity!string element, LineTopology topology)
{
    auto vertices = parseFloatArray(getChildText(element, "vertex"));
    auto indices = parseUIntArray(getChildText(element, "indices"));

    if (vertices.length == 0 || vertices.length % 3 != 0)
        return LineBatch.init;
    if (indices.length == 0)
        return LineBatch.init;

    final switch (topology)
    {
    case LineTopology.segments:
        if (indices.length % 2 != 0)
            return LineBatch.init;
        break;
    case LineTopology.strip:
        if (indices.length < 2)
            return LineBatch.init;
        break;
    case LineTopology.loop:
        if (indices.length < 3)
            return LineBatch.init;
        break;
    }

    auto vertexCount = vertices.length / 3;
    foreach (index; indices)
    {
        if (index >= vertexCount)
            return LineBatch.init;
    }

    LineBatch batch;
    batch.topology = topology;
    batch.vertices = vertices;
    batch.indices = indices;
    batch.color = parseColor(getChildText(element, "color"));
    batch.width = parseWidth(getChildText(element, "width"));
    batch.skeleton = parseSkeleton(element, "skelton");
    batch.vertexGroups = parseVertexGroups(element, "vertex_group");
    return batch;
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

private float[3] parseColor(string text)
{
    enum defaultColor = [0.95f, 0.85f, 0.35f];
    auto values = parseFloatArray(text);
    if (values.length < 3)
        return defaultColor;

    float[3] color;
    color[0] = values[0];
    color[1] = values[1];
    color[2] = values[2];
    return color;
}

private float parseWidth(string text)
{
    auto trimmed = text.strip;
    if (trimmed.length == 0)
        return 1.0f;

    auto width = to!float(trimmed);
    return width > 0.0f ? width : 1.0f;
}

private DOMEntity!string findChildElement(DOMEntity!string parent, string tagName)
{
    foreach (child; parent.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        if (child.name == tagName)
            return child;
    }

    return DOMEntity!string.init;
}

private bool hasElement(DOMEntity!string element)
{
    return element.type == EntityType.elementStart || element.type == EntityType.elementEmpty;
}

private VertexGroup[] parseVertexGroups(DOMEntity!string parent, string tagName)
{
    auto element = findChildElement(parent, tagName);
    if (!hasElement(element))
        return [];

    VertexGroup[] groups;
    foreach (child; element.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        if (child.name != "group")
            continue;

        VertexGroup group;
        group.name = getAttribute(child, "name");
        group.indices = parseUIntArray(getChildText(child, "indices"));
        groups ~= group;
    }

    return groups;
}

private Skeleton parseSkeleton(DOMEntity!string parent, string tagName)
{
    auto element = findChildElement(parent, tagName);
    if (!hasElement(element))
        return Skeleton.init;

    Skeleton skeleton;
    skeleton.name = getAttribute(element, "name");
    skeleton.count = parseUIntAttribute(element, "count");

    foreach (child; element.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        if (child.name != "node")
            continue;

        skeleton.bones ~= parseBoneNode(child);
    }

    return skeleton;
}

private BoneNode parseBoneNode(DOMEntity!string element)
{
    BoneNode bone;
    bone.name = getAttribute(element, "name");
    bone.pos = parseVec3(getChildText(element, "pos"));
    bone.tailPos = parseVec3(getChildText(element, "tail_pos"));
    bone.xAxis = parseVec3(getChildText(element, "x_axis"), vec3(1, 0, 0));
    bone.yAxis = parseVec3(getChildText(element, "y_axis"), vec3(0, 1, 0));
    bone.zAxis = parseVec3(getChildText(element, "z_axis"), vec3(0, 0, 1));
    bone.weights = parseFloatArray(getChildText(element, "weights"));
    bone.targetIndices = parseUIntArray(getChildText(element, "target_indices"));

    foreach (child; element.children)
    {
        if (child.type != EntityType.elementStart && child.type != EntityType.elementEmpty)
            continue;

        if (child.name != "node")
            continue;

        bone.children ~= parseBoneNode(child);
    }

    return bone;
}

private uint parseUIntAttribute(DOMEntity!string element, string attributeName, uint defaultValue = 0)
{
    auto value = getAttribute(element, attributeName);
    if (value.length == 0)
        return defaultValue;
    return to!uint(value);
}

private vec3 parseVec3(string text, vec3 defaultValue = vec3(0, 0, 0))
{
    auto values = parseFloatArray(text);
    if (values.length < 3)
        return defaultValue;

    return vec3(values[0], values[1], values[2]);
}
