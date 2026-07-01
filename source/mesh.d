module mesh;

import std.algorithm : min;

import bindbc.opengl;
import gl3n.linalg;

import geo_model;
import shader;
import skeleton;
import skinning;

struct MeshVertex
{
    float[3] position;
    float[3] normal;
}

struct SkinnedMeshVertex
{
    float[3] position;
    float[3] normal;
    float[4] boneIds;
    float[4] weights;
}

struct LineVertex
{
    float[3] position;
}

private struct VertexGroupHighlightGpu
{
    string name;
    GLuint ebo;
    GLsizei indexCount;
}

private struct TriangleGpuBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
    bool skinned;
    size_t boneCount;
    VertexGroupHighlightGpu[] highlights;
}

private struct LineGpuBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
    GLenum mode;
    float[3] color;
    float width;
}

struct GeoMesh
{
    private TriangleGpuBatch[] _triangles;
    private LineGpuBatch[] _lines;
    private LineGpuBatch[] _normalLines;
    private bool _uploaded;

    @property bool uploaded() const
    {
        return _uploaded;
    }

    @property bool hasSkinnedBatch() const
    {
        foreach (batch; _triangles)
        {
            if (batch.skinned)
                return true;
        }
        return false;
    }

    bool upload(const(GeoModel) model)
    {
        destroyGpu();

        foreach (batch; model.triangles)
        {
            if (batch.vertexCount == 0 || batch.indices.length == 0)
                continue;

            auto skinning = buildSkinningData(batch);
            const bool skinned = skinning.influencedVertices > 0;

            TriangleGpuBatch gpu;
            gpu.skinned = skinned;
            gpu.boneCount = skinning.bones.length;

            if (skinned)
            {
                SkinnedMeshVertex[] vertices;
                vertices.length = batch.vertexCount;

                for (size_t i = 0; i < batch.vertexCount; ++i)
                {
                    size_t base = i * 3;
                    vertices[i].position = [
                        batch.vertices[base],
                        batch.vertices[base + 1],
                        batch.vertices[base + 2]
                    ];
                    vertices[i].normal = [
                        batch.normals[base],
                        batch.normals[base + 1],
                        batch.normals[base + 2]
                    ];

                    auto skin = skinning.vertices[i];
                    foreach (j; 0 .. MAX_BONE_INFLUENCES)
                    {
                        vertices[i].boneIds[j] = skin.boneIds[j] >= 0
                            ? cast(float)skin.boneIds[j]
                            : -1.0f;
                        vertices[i].weights[j] = skin.weights[j];
                    }
                }

                gpu.indexCount = cast(GLsizei)(batch.indices.length);

                glGenVertexArrays(1, &gpu.vao);
                glGenBuffers(1, &gpu.vbo);
                glGenBuffers(1, &gpu.ebo);

                glBindVertexArray(gpu.vao);

                glBindBuffer(GL_ARRAY_BUFFER, gpu.vbo);
                glBufferData(
                    GL_ARRAY_BUFFER,
                    vertices.length * SkinnedMeshVertex.sizeof,
                    vertices.ptr,
                    GL_STATIC_DRAW);

                glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gpu.ebo);
                glBufferData(
                    GL_ELEMENT_ARRAY_BUFFER,
                    batch.indices.length * uint.sizeof,
                    batch.indices.ptr,
                    GL_STATIC_DRAW);

                enum stride = SkinnedMeshVertex.sizeof;
                glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
                glEnableVertexAttribArray(0);
                glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 3));
                glEnableVertexAttribArray(1);
                glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 6));
                glEnableVertexAttribArray(2);
                glVertexAttribPointer(3, 4, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 6 + float.sizeof * 4));
                glEnableVertexAttribArray(3);

                glBindVertexArray(0);
            }
            else
            {
                MeshVertex[] vertices;
                vertices.length = batch.vertexCount;

                for (size_t i = 0; i < batch.vertexCount; ++i)
                {
                    size_t base = i * 3;
                    vertices[i].position = [
                        batch.vertices[base],
                        batch.vertices[base + 1],
                        batch.vertices[base + 2]
                    ];
                    vertices[i].normal = [
                        batch.normals[base],
                        batch.normals[base + 1],
                        batch.normals[base + 2]
                    ];
                }

                gpu.indexCount = cast(GLsizei)(batch.indices.length);

                glGenVertexArrays(1, &gpu.vao);
                glGenBuffers(1, &gpu.vbo);
                glGenBuffers(1, &gpu.ebo);

                glBindVertexArray(gpu.vao);

                glBindBuffer(GL_ARRAY_BUFFER, gpu.vbo);
                glBufferData(GL_ARRAY_BUFFER, vertices.length * MeshVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

                glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gpu.ebo);
                glBufferData(GL_ELEMENT_ARRAY_BUFFER, batch.indices.length * uint.sizeof, batch.indices.ptr, GL_STATIC_DRAW);

                enum stride = MeshVertex.sizeof;
                glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
                glEnableVertexAttribArray(0);
                glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 3));
                glEnableVertexAttribArray(1);

                glBindVertexArray(0);
            }

            uploadVertexGroupHighlights(gpu, batch);
            _triangles ~= gpu;
        }

        vec3 minBound;
        vec3 maxBound;
        model.computeBounds(minBound, maxBound);
        float normalLength = (maxBound - minBound).length * 0.05f;
        if (normalLength <= 0.0f)
            normalLength = 0.1f;

        foreach (batch; model.triangles)
        {
            if (batch.vertexCount == 0)
                continue;

            LineGpuBatch gpu;
            LineVertex[] vertices;
            uint[] indices;
            vertices.reserve(batch.vertexCount * 2);
            indices.reserve(batch.vertexCount * 2);

            for (size_t i = 0; i < batch.vertexCount; ++i)
            {
                size_t base = i * 3;
                vec3 pos = vec3(
                    batch.vertices[base],
                    batch.vertices[base + 1],
                    batch.vertices[base + 2]);
                vec3 normal = vec3(
                    batch.normals[base],
                    batch.normals[base + 1],
                    batch.normals[base + 2]);

                float normalLen = normal.length;
                if (normalLen > 1e-6f)
                    normal /= normalLen;

                vec3 end = pos + normal * normalLength;
                uint segmentBase = cast(uint)vertices.length;
                vertices ~= LineVertex([pos.x, pos.y, pos.z]);
                vertices ~= LineVertex([end.x, end.y, end.z]);
                indices ~= [segmentBase, segmentBase + 1];
            }

            if (vertices.length == 0 || indices.length == 0)
                continue;

            gpu.indexCount = cast(GLsizei)(indices.length);
            gpu.color = [0.25f, 0.95f, 0.35f];
            gpu.width = 1.5f;
            gpu.mode = GL_LINES;

            glGenVertexArrays(1, &gpu.vao);
            glGenBuffers(1, &gpu.vbo);
            glGenBuffers(1, &gpu.ebo);

            glBindVertexArray(gpu.vao);

            glBindBuffer(GL_ARRAY_BUFFER, gpu.vbo);
            glBufferData(GL_ARRAY_BUFFER, vertices.length * LineVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gpu.ebo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);

            enum stride = LineVertex.sizeof;
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
            glEnableVertexAttribArray(0);

            glBindVertexArray(0);
            _normalLines ~= gpu;
        }

        foreach (batch; model.lines)
        {
            if (batch.vertexCount == 0 || batch.indices.length == 0)
                continue;

            LineGpuBatch gpu;
            LineVertex[] vertices;
            vertices.length = batch.vertexCount;

            for (size_t i = 0; i < batch.vertexCount; ++i)
            {
                size_t base = i * 3;
                vertices[i].position = [
                    batch.vertices[base],
                    batch.vertices[base + 1],
                    batch.vertices[base + 2]
                ];
            }

            gpu.indexCount = cast(GLsizei)(batch.indices.length);
            gpu.color = batch.color;
            gpu.width = batch.width;
            final switch (batch.topology)
            {
            case LineTopology.segments:
                gpu.mode = GL_LINES;
                break;
            case LineTopology.strip:
                gpu.mode = GL_LINE_STRIP;
                break;
            case LineTopology.loop:
                gpu.mode = GL_LINE_LOOP;
                break;
            }

            glGenVertexArrays(1, &gpu.vao);
            glGenBuffers(1, &gpu.vbo);
            glGenBuffers(1, &gpu.ebo);

            glBindVertexArray(gpu.vao);

            glBindBuffer(GL_ARRAY_BUFFER, gpu.vbo);
            glBufferData(GL_ARRAY_BUFFER, vertices.length * LineVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, gpu.ebo);
            glBufferData(GL_ELEMENT_ARRAY_BUFFER, batch.indices.length * uint.sizeof, batch.indices.ptr, GL_STATIC_DRAW);

            enum stride = LineVertex.sizeof;
            glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
            glEnableVertexAttribArray(0);

            glBindVertexArray(0);
            _lines ~= gpu;
        }

        _uploaded = _triangles.length > 0 || _lines.length > 0;
        return true;
    }

    void draw(
        ShaderProgram meshShader,
        ShaderProgram lineShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        bool showNormals = false,
        ShaderProgram skinnedMeshShader = ShaderProgram.init,
        mat4[] skinMatrices = null,
        bool highlightMode = false,
        string highlightGroupName = "") const
    {
        enum baseColor = [0.62f, 0.70f, 0.82f];
        enum dimColor = [0.36f, 0.40f, 0.46f];
        enum highlightColor = [1.0f, 0.55f, 0.15f];

        foreach (batch; _triangles)
        {
            if (batch.vao == 0 || batch.indexCount == 0)
                continue;

            const float[3] meshColor = highlightMode ? dimColor : baseColor;

            if (batch.skinned && skinnedMeshShader.program != 0 && skinMatrices.length > 0)
            {
                drawSkinnedTriangleBatch(
                    batch,
                    skinnedMeshShader,
                    modelMatrix,
                    mvpMatrix,
                    skinMatrices,
                    meshColor);

                if (highlightMode && highlightGroupName.length > 0)
                {
                    drawSkinnedTriangleBatchHighlight(
                        batch,
                        skinnedMeshShader,
                        modelMatrix,
                        mvpMatrix,
                        skinMatrices,
                        highlightGroupName,
                        highlightColor);
                }
            }
            else if (batch.skinned)
            {
                continue;
            }
            else
            {
                drawStaticTriangleBatch(
                    batch,
                    meshShader,
                    modelMatrix,
                    mvpMatrix,
                    meshColor);

                if (highlightMode && highlightGroupName.length > 0)
                {
                    drawStaticTriangleBatchHighlight(
                        batch,
                        meshShader,
                        modelMatrix,
                        mvpMatrix,
                        highlightGroupName,
                        highlightColor);
                }
            }
        }

        if (showNormals)
        {
            foreach (batch; _normalLines)
            {
                if (batch.vao == 0 || batch.indexCount == 0)
                    continue;

                lineShader.use();
                glUniformMatrix4fv(lineShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
                glUniform3fv(lineShader.location("uColor"), 1, batch.color.ptr);

                glLineWidth(batch.width);

                glBindVertexArray(batch.vao);
                glDrawElements(batch.mode, batch.indexCount, GL_UNSIGNED_INT, null);
                glBindVertexArray(0);
            }
        }

        foreach (batch; _lines)
        {
            if (batch.vao == 0 || batch.indexCount == 0)
                continue;

            lineShader.use();
            glUniformMatrix4fv(lineShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
            glUniform3fv(lineShader.location("uColor"), 1, batch.color.ptr);

            glLineWidth(batch.width);

            glBindVertexArray(batch.vao);
            glDrawElements(batch.mode, batch.indexCount, GL_UNSIGNED_INT, null);
            glBindVertexArray(0);
        }
    }

    void release()
    {
        _triangles = null;
        _lines = null;
        _normalLines = null;
        _uploaded = false;
    }

    void destroyGpu()
    {
        foreach (ref batch; _triangles)
            destroyTriangleBatch(batch);
        foreach (ref batch; _lines)
            destroyLineBatch(batch);
        foreach (ref batch; _normalLines)
            destroyLineBatch(batch);
        _triangles = null;
        _lines = null;
        _normalLines = null;
        _uploaded = false;
    }

    void destroy()
    {
        release();
    }

    private static void destroyTriangleBatch(ref TriangleGpuBatch batch)
    {
        foreach (ref highlight; batch.highlights)
        {
            if (highlight.ebo != 0)
            {
                glDeleteBuffers(1, &highlight.ebo);
                highlight.ebo = 0;
            }
            highlight.indexCount = 0;
        }
        batch.highlights = null;

        if (batch.ebo != 0)
        {
            glDeleteBuffers(1, &batch.ebo);
            batch.ebo = 0;
        }
        if (batch.vbo != 0)
        {
            glDeleteBuffers(1, &batch.vbo);
            batch.vbo = 0;
        }
        if (batch.vao != 0)
        {
            glDeleteVertexArrays(1, &batch.vao);
            batch.vao = 0;
        }
        batch.indexCount = 0;
        batch.skinned = false;
        batch.boneCount = 0;
    }

    private static void destroyLineBatch(ref LineGpuBatch batch)
    {
        if (batch.ebo != 0)
        {
            glDeleteBuffers(1, &batch.ebo);
            batch.ebo = 0;
        }
        if (batch.vbo != 0)
        {
            glDeleteBuffers(1, &batch.vbo);
            batch.vbo = 0;
        }
        if (batch.vao != 0)
        {
            glDeleteVertexArrays(1, &batch.vao);
            batch.vao = 0;
        }
        batch.indexCount = 0;
    }

    private static void uploadVertexGroupHighlights(
        ref TriangleGpuBatch gpu,
        const TriangleBatch batch)
    {
        foreach (group; batch.vertexGroups)
        {
            if (group.indices.length == 0)
                continue;

            auto highlightIndices = buildGroupHighlightIndices(batch.indices, group.indices);
            if (highlightIndices.length == 0)
                continue;

            VertexGroupHighlightGpu highlight;
            highlight.name = group.name;
            highlight.indexCount = cast(GLsizei)(highlightIndices.length);

            glGenBuffers(1, &highlight.ebo);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, highlight.ebo);
            glBufferData(
                GL_ELEMENT_ARRAY_BUFFER,
                highlightIndices.length * uint.sizeof,
                highlightIndices.ptr,
                GL_STATIC_DRAW);

            gpu.highlights ~= highlight;
        }
    }

    private static uint[] buildGroupHighlightIndices(
        const uint[] triangleIndices,
        const uint[] groupVertexIndices)
    {
        bool[uint] members;
        foreach (vi; groupVertexIndices)
            members[vi] = true;

        uint[] result;
        result.reserve(triangleIndices.length);

        for (size_t i = 0; i + 2 < triangleIndices.length; i += 3)
        {
            const i0 = triangleIndices[i];
            const i1 = triangleIndices[i + 1];
            const i2 = triangleIndices[i + 2];
            if (i0 in members || i1 in members || i2 in members)
                result ~= [i0, i1, i2];
        }

        return result;
    }

    private static void drawStaticTriangleBatch(
        const TriangleGpuBatch batch,
        ShaderProgram meshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        const float[3] color)
    {
        meshShader.use();
        glUniformMatrix4fv(meshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
        glUniformMatrix4fv(meshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(meshShader.location("uColor"), 1, color.ptr);

        float[9] normalMatrix = extractNormalMatrix(modelMatrix);
        glUniformMatrix3fv(meshShader.location("uNormalMatrix"), 1, GL_TRUE, normalMatrix.ptr);

        glBindVertexArray(batch.vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, batch.ebo);
        glDrawElements(GL_TRIANGLES, batch.indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }

    private static void drawStaticTriangleBatchHighlight(
        const TriangleGpuBatch batch,
        ShaderProgram meshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        string groupName,
        const float[3] color)
    {
        foreach (highlight; batch.highlights)
        {
            if (highlight.ebo == 0 || highlight.indexCount == 0)
                continue;
            if (highlight.name != groupName)
                continue;

            meshShader.use();
            glUniformMatrix4fv(meshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
            glUniformMatrix4fv(meshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
            glUniform3fv(meshShader.location("uColor"), 1, color.ptr);

            float[9] normalMatrix = extractNormalMatrix(modelMatrix);
            glUniformMatrix3fv(meshShader.location("uNormalMatrix"), 1, GL_TRUE, normalMatrix.ptr);

            glBindVertexArray(batch.vao);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, highlight.ebo);
            glDrawElements(GL_TRIANGLES, highlight.indexCount, GL_UNSIGNED_INT, null);
            glBindVertexArray(0);
            return;
        }
    }

    private static void drawSkinnedTriangleBatch(
        const TriangleGpuBatch batch,
        ShaderProgram skinnedMeshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        mat4[] skinMatrices,
        const float[3] color)
    {
        skinnedMeshShader.use();
        glUniformMatrix4fv(skinnedMeshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
        glUniformMatrix4fv(skinnedMeshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(skinnedMeshShader.location("uColor"), 1, color.ptr);

        const count = min(skinMatrices.length, MAX_GPU_BONES);
        GLint baseLoc = skinnedMeshShader.location("uBoneMatrices");
        if (baseLoc < 0)
            baseLoc = skinnedMeshShader.location("uBoneMatrices[0]");
        if (baseLoc >= 0)
        {
            foreach (i; 0 .. count)
            {
                glUniformMatrix4fv(
                    baseLoc + cast(GLint)i,
                    1,
                    GL_TRUE,
                    skinMatrices[i].value_ptr);
            }
        }

        glBindVertexArray(batch.vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, batch.ebo);
        glDrawElements(GL_TRIANGLES, batch.indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }

    private static void drawSkinnedTriangleBatchHighlight(
        const TriangleGpuBatch batch,
        ShaderProgram skinnedMeshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        mat4[] skinMatrices,
        string groupName,
        const float[3] color)
    {
        foreach (highlight; batch.highlights)
        {
            if (highlight.ebo == 0 || highlight.indexCount == 0)
                continue;
            if (highlight.name != groupName)
                continue;

            skinnedMeshShader.use();
            glUniformMatrix4fv(skinnedMeshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
            glUniformMatrix4fv(skinnedMeshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
            glUniform3fv(skinnedMeshShader.location("uColor"), 1, color.ptr);

            const count = min(skinMatrices.length, MAX_GPU_BONES);
            GLint baseLoc = skinnedMeshShader.location("uBoneMatrices");
            if (baseLoc < 0)
                baseLoc = skinnedMeshShader.location("uBoneMatrices[0]");
            if (baseLoc >= 0)
            {
                foreach (i; 0 .. count)
                {
                    glUniformMatrix4fv(
                        baseLoc + cast(GLint)i,
                        1,
                        GL_TRUE,
                        skinMatrices[i].value_ptr);
                }
            }

            glBindVertexArray(batch.vao);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, highlight.ebo);
            glDrawElements(GL_TRIANGLES, highlight.indexCount, GL_UNSIGNED_INT, null);
            glBindVertexArray(0);
            return;
        }
    }

    private static float[9] extractNormalMatrix(mat4 modelMatrix)
    {
        auto m = modelMatrix.matrix;
        float[9] result;
        result[0] = m[0][0];
        result[1] = m[0][1];
        result[2] = m[0][2];
        result[3] = m[1][0];
        result[4] = m[1][1];
        result[5] = m[1][2];
        result[6] = m[2][0];
        result[7] = m[2][1];
        result[8] = m[2][2];
        return result;
    }
}
