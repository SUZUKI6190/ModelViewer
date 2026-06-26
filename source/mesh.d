module mesh;

import bindbc.opengl;
import gl3n.linalg;

import geo_model;
import shader;

struct MeshVertex
{
    float[3] position;
    float[3] normal;
}

struct LineVertex
{
    float[3] position;
}

private struct TriangleGpuBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
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

    bool upload(const(GeoModel) model)
    {
        destroyGpu();

        foreach (batch; model.triangles)
        {
            if (batch.vertexCount == 0 || batch.indices.length == 0)
                continue;

            TriangleGpuBatch gpu;
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
        bool showNormals = false) const
    {
        foreach (batch; _triangles)
        {
            if (batch.vao == 0 || batch.indexCount == 0)
                continue;

            meshShader.use();
            glUniformMatrix4fv(meshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
            glUniformMatrix4fv(meshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);

            float[9] normalMatrix = extractNormalMatrix(modelMatrix);
            glUniformMatrix3fv(meshShader.location("uNormalMatrix"), 1, GL_TRUE, normalMatrix.ptr);

            glBindVertexArray(batch.vao);
            glDrawElements(GL_TRIANGLES, batch.indexCount, GL_UNSIGNED_INT, null);
            glBindVertexArray(0);
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
