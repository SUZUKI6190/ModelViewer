module geo_model;

import std.algorithm;

import gl3n.linalg;

enum LineTopology
{
    segments,
    strip,
    loop,
}

struct TriangleBatch
{
    float[] vertices;
    float[] normals;
    float[] colors;
    float[] uvs;
    uint[] indices;

    @property size_t vertexCount() const
    {
        return vertices.length / 3;
    }

    @property size_t triangleCount() const
    {
        return indices.length / 3;
    }

    @property bool isValid() const
    {
        return vertices.length > 0 && indices.length > 0;
    }
}

struct LineBatch
{
    LineTopology topology;
    float[] vertices;
    float[3] color = [1.0f, 1.0f, 1.0f];
    float width = 1.0f;
    uint[] indices;

    @property size_t vertexCount() const
    {
        return vertices.length / 3;
    }

    @property bool isValid() const
    {
        return vertices.length > 0 && indices.length > 0;
    }
}

struct GeoModel
{
    string name;
    TriangleBatch[] triangles;
    LineBatch[] lines;

    @property size_t vertexCount() const
    {
        size_t total;
        foreach (batch; triangles)
            total += batch.vertexCount;
        foreach (batch; lines)
            total += batch.vertexCount;
        return total;
    }

    @property size_t triangleCount() const
    {
        size_t total;
        foreach (batch; triangles)
            total += batch.triangleCount;
        return total;
    }

    @property size_t lineBatchCount() const
    {
        return lines.length;
    }

    @property bool hasDrawableGeometry() const
    {
        foreach (batch; triangles)
        {
            if (batch.vertexCount > 0 && batch.indices.length > 0)
                return true;
        }
        foreach (batch; lines)
        {
            if (batch.vertexCount > 0 && batch.indices.length > 0)
                return true;
        }
        return false;
    }

    void computeBounds(out vec3 minBound, out vec3 maxBound) const
    {
        bool found;

        void includeVertices(const float[] vertices)
        {
            if (vertices.length < 3)
                return;

            for (size_t i = 0; i < vertices.length; i += 3)
            {
                vec3 p = vec3(vertices[i], vertices[i + 1], vertices[i + 2]);
                if (!found)
                {
                    minBound = p;
                    maxBound = p;
                    found = true;
                }
                else
                {
                    minBound.x = min(minBound.x, p.x);
                    minBound.y = min(minBound.y, p.y);
                    minBound.z = min(minBound.z, p.z);
                    maxBound.x = max(maxBound.x, p.x);
                    maxBound.y = max(maxBound.y, p.y);
                    maxBound.z = max(maxBound.z, p.z);
                }
            }
        }

        foreach (batch; triangles)
            includeVertices(batch.vertices);
        foreach (batch; lines)
            includeVertices(batch.vertices);

        if (!found)
        {
            minBound = vec3(0);
            maxBound = vec3(0);
        }
    }
}
