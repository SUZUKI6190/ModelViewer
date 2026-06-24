module geo_model;

import std.algorithm;

import gl3n.linalg;

struct GeoModel
{
    string name;
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

    void computeBounds(out vec3 minBound, out vec3 maxBound) const
    {
        if (vertices.length < 3)
        {
            minBound = vec3(0);
            maxBound = vec3(0);
            return;
        }

        minBound = vec3(vertices[0], vertices[1], vertices[2]);
        maxBound = minBound;

        for (size_t i = 3; i < vertices.length; i += 3)
        {
            vec3 p = vec3(vertices[i], vertices[i + 1], vertices[i + 2]);
            minBound.x = min(minBound.x, p.x);
            minBound.y = min(minBound.y, p.y);
            minBound.z = min(minBound.z, p.z);
            maxBound.x = max(maxBound.x, p.x);
            maxBound.y = max(maxBound.y, p.y);
            maxBound.z = max(maxBound.z, p.z);
        }
    }
}
