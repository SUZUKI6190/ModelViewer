module geo_model;

import std.algorithm;

import gl3n.linalg;

enum LineTopology
{
    segments,
    strip,
    loop,
}

struct BoneNode
{
    string name;
    vec3 pos;
    vec3 tailPos;
    vec3 xAxis = vec3(1, 0, 0);
    vec3 yAxis = vec3(0, 1, 0);
    vec3 zAxis = vec3(0, 0, 1);
    float[] weights;
    uint[] targetIndices;
    BoneNode[] children;

    @property size_t boneCount() const
    {
        size_t total = 1;
        foreach (child; children)
            total += child.boneCount;
        return total;
    }
}

struct Skeleton
{
    string name;
    uint count;
    BoneNode[] bones;

    @property bool isValid() const
    {
        return bones.length > 0;
    }

    @property size_t boneCount() const
    {
        size_t total;
        foreach (bone; bones)
            total += bone.boneCount;
        return total;
    }
}

struct VertexGroup
{
    string name;
    uint[] indices;
}

struct TriangleBatch
{
    float[] vertices;
    float[] normals;
    float[] colors;
    float[] uvs;
    uint[] indices;
    Skeleton skeleton;
    VertexGroup[] vertexGroups;

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
    Skeleton skeleton;
    VertexGroup[] vertexGroups;

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

    @property bool hasSkeleton() const
    {
        foreach (batch; triangles)
        {
            if (batch.skeleton.isValid)
                return true;
        }
        foreach (batch; lines)
        {
            if (batch.skeleton.isValid)
                return true;
        }
        return false;
    }

    @property size_t skeletonBoneCount() const
    {
        size_t total;
        foreach (batch; triangles)
            total += batch.skeleton.boneCount;
        foreach (batch; lines)
            total += batch.skeleton.boneCount;
        return total;
    }

    @property bool hasVertexGroups() const
    {
        foreach (batch; triangles)
        {
            foreach (group; batch.vertexGroups)
            {
                if (group.name.length > 0)
                    return true;
            }
        }
        return false;
    }

    string[] collectVertexGroupNames() const
    {
        bool[string] seen;
        string[] names;

        foreach (batch; triangles)
        {
            foreach (group; batch.vertexGroups)
            {
                if (group.name.length == 0 || group.name in seen)
                    continue;
                seen[group.name] = true;
                names ~= group.name;
            }
        }

        return names;
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
