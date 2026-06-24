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

struct Mesh
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;

    bool upload(const(GeoModel) model)
    {
        destroyGpu();

        MeshVertex[] vertices;
        vertices.length = model.vertexCount;

        for (size_t i = 0; i < model.vertexCount; ++i)
        {
            size_t base = i * 3;
            vertices[i].position = [
                model.vertices[base],
                model.vertices[base + 1],
                model.vertices[base + 2]
            ];
            vertices[i].normal = [
                model.normals[base],
                model.normals[base + 1],
                model.normals[base + 2]
            ];
        }

        indexCount = cast(GLsizei)(model.indices.length);

        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glGenBuffers(1, &ebo);

        glBindVertexArray(vao);

        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * MeshVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, model.indices.length * uint.sizeof, model.indices.ptr, GL_STATIC_DRAW);

        enum stride = MeshVertex.sizeof;
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 3));
        glEnableVertexAttribArray(1);

        glBindVertexArray(0);
        return true;
    }

    void draw(ShaderProgram shader, mat4 modelMatrix, mat4 mvpMatrix) const
    {
        if (vao == 0 || indexCount == 0)
            return;

        shader.use();
        glUniformMatrix4fv(shader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
        glUniformMatrix4fv(shader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);

        float[9] normalMatrix = extractNormalMatrix(modelMatrix);
        glUniformMatrix3fv(shader.location("uNormalMatrix"), 1, GL_TRUE, normalMatrix.ptr);

        glBindVertexArray(vao);
        glDrawElements(GL_TRIANGLES, indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }

    /// Drop host-side handles without calling OpenGL (safe when no GL context is current).
    void release()
    {
        vao = 0;
        vbo = 0;
        ebo = 0;
        indexCount = 0;
    }

    /// Delete GPU resources. Must be called only while an OpenGL context is current.
    void destroyGpu()
    {
        if (ebo != 0)
        {
            glDeleteBuffers(1, &ebo);
            ebo = 0;
        }
        if (vbo != 0)
        {
            glDeleteBuffers(1, &vbo);
            vbo = 0;
        }
        if (vao != 0)
        {
            glDeleteVertexArrays(1, &vao);
            vao = 0;
        }
        indexCount = 0;
    }

    /// Backwards-compatible alias for CPU-side release.
    void destroy()
    {
        release();
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
