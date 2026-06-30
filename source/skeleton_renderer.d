module skeleton_renderer;

import bindbc.opengl;
import gl3n.linalg;

import geo_model;
import mesh;
import shader;

private struct SkeletonLineBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
    bool valid;
}

struct SkeletonRenderer
{
    private SkeletonLineBatch _batch;

    @property bool uploaded() const
    {
        return _batch.valid;
    }

    @property bool hasContent() const
    {
        return _batch.valid && _batch.indexCount > 0;
    }

    bool upload(const(GeoModel) model)
    {
        destroyGpu();

        LineVertex[] vertices;
        uint[] indices;

        foreach (batch; model.triangles)
            collectSkeletonLines(batch.skeleton, vertices, indices);
        foreach (batch; model.lines)
            collectSkeletonLines(batch.skeleton, vertices, indices);

        if (vertices.length == 0 || indices.length == 0)
            return true;

        _batch.indexCount = cast(GLsizei)(indices.length);

        glGenVertexArrays(1, &_batch.vao);
        glGenBuffers(1, &_batch.vbo);
        glGenBuffers(1, &_batch.ebo);

        glBindVertexArray(_batch.vao);

        glBindBuffer(GL_ARRAY_BUFFER, _batch.vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * LineVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _batch.ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);

        enum stride = LineVertex.sizeof;
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
        glEnableVertexAttribArray(0);

        glBindVertexArray(0);
        _batch.valid = true;
        return true;
    }

    void draw(ShaderProgram lineShader, mat4 mvpMatrix) const
    {
        if (!hasContent)
            return;

        enum float[3] dimColor = [0.75f, 0.40f, 0.10f];
        enum float[3] brightColor = [1.0f, 0.55f, 0.15f];
        enum float lineWidth = 2.5f;

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        drawBatch(lineShader, mvpMatrix, dimColor, lineWidth);

        glDisable(GL_DEPTH_TEST);
        drawBatch(lineShader, mvpMatrix, brightColor, lineWidth);
        glEnable(GL_DEPTH_TEST);
    }

    void destroyGpu()
    {
        if (_batch.ebo != 0)
        {
            glDeleteBuffers(1, &_batch.ebo);
            _batch.ebo = 0;
        }
        if (_batch.vbo != 0)
        {
            glDeleteBuffers(1, &_batch.vbo);
            _batch.vbo = 0;
        }
        if (_batch.vao != 0)
        {
            glDeleteVertexArrays(1, &_batch.vao);
            _batch.vao = 0;
        }
        _batch.indexCount = 0;
        _batch.valid = false;
    }

    private static void collectSkeletonLines(
        const(Skeleton) skeleton,
        ref LineVertex[] vertices,
        ref uint[] indices)
    {
        if (!skeleton.isValid)
            return;

        foreach (bone; skeleton.bones)
            collectBoneLines(bone, vertices, indices);
    }

    private static void collectBoneLines(
        ref const(BoneNode) bone,
        ref LineVertex[] vertices,
        ref uint[] indices)
    {
        uint base = cast(uint)vertices.length;
        vertices ~= LineVertex([bone.pos.x, bone.pos.y, bone.pos.z]);
        vertices ~= LineVertex([bone.tailPos.x, bone.tailPos.y, bone.tailPos.z]);
        indices ~= [base, base + 1];

        foreach (child; bone.children)
        {
            uint link = cast(uint)vertices.length;
            vertices ~= LineVertex([bone.tailPos.x, bone.tailPos.y, bone.tailPos.z]);
            vertices ~= LineVertex([child.pos.x, child.pos.y, child.pos.z]);
            indices ~= [link, link + 1];
            collectBoneLines(child, vertices, indices);
        }
    }

    private void drawBatch(
        ShaderProgram lineShader,
        mat4 mvpMatrix,
        float[3] color,
        float width) const
    {
        lineShader.use();
        glUniformMatrix4fv(lineShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(lineShader.location("uColor"), 1, color.ptr);
        glLineWidth(width);

        glBindVertexArray(_batch.vao);
        glDrawElements(GL_LINES, _batch.indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }
}
