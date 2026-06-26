module axis_gizmo;

import bindbc.opengl;
import gl3n.linalg;

import mesh;
import shader;

private struct AxisLineBatch
{
    GLuint vao;
    GLuint vbo;
    float[3] color;
    float width;
    bool valid;
}

struct AxisGizmo
{
    private AxisLineBatch _worldX;
    private AxisLineBatch _worldY;
    private AxisLineBatch _worldZ;
    private AxisLineBatch _cornerX;
    private AxisLineBatch _cornerY;
    private AxisLineBatch _cornerZ;
    private float _worldLength = -1.0f;

    @property bool uploaded() const
    {
        return _worldX.valid && _cornerX.valid;
    }

    void upload(float worldLength)
    {
        if (_worldLength == worldLength && uploaded)
            return;

        destroyGpu();
        _worldLength = worldLength;

        _worldX = createAxisBatch(vec3(1, 0, 0), worldLength, [1.0f, 0.25f, 0.25f], 2.5f);
        _worldY = createAxisBatch(vec3(0, 1, 0), worldLength, [0.25f, 1.0f, 0.25f], 2.5f);
        _worldZ = createAxisBatch(vec3(0, 0, 1), worldLength, [0.35f, 0.55f, 1.0f], 2.5f);

        enum cornerLength = 1.0f;
        _cornerX = createAxisBatch(vec3(1, 0, 0), cornerLength, [1.0f, 0.25f, 0.25f], 2.0f);
        _cornerY = createAxisBatch(vec3(0, 1, 0), cornerLength, [0.25f, 1.0f, 0.25f], 2.0f);
        _cornerZ = createAxisBatch(vec3(0, 0, 1), cornerLength, [0.35f, 0.55f, 1.0f], 2.0f);
    }

    void drawWorld(ShaderProgram lineShader, mat4 mvpMatrix) const
    {
        drawBatch(_worldX, lineShader, mvpMatrix);
        drawBatch(_worldY, lineShader, mvpMatrix);
        drawBatch(_worldZ, lineShader, mvpMatrix);
    }

    void drawCorner(ShaderProgram lineShader, mat4 mvpMatrix) const
    {
        drawBatch(_cornerX, lineShader, mvpMatrix);
        drawBatch(_cornerY, lineShader, mvpMatrix);
        drawBatch(_cornerZ, lineShader, mvpMatrix);
    }

    void destroyGpu()
    {
        destroyBatch(_worldX);
        destroyBatch(_worldY);
        destroyBatch(_worldZ);
        destroyBatch(_cornerX);
        destroyBatch(_cornerY);
        destroyBatch(_cornerZ);
        _worldLength = -1.0f;
    }

    private static AxisLineBatch createAxisBatch(
        vec3 direction,
        float length,
        float[3] color,
        float width)
    {
        AxisLineBatch batch;
        LineVertex[2] vertices;
        vertices[0].position = [0.0f, 0.0f, 0.0f];
        vertices[1].position = [
            direction.x * length,
            direction.y * length,
            direction.z * length,
        ];
        batch.color = color;
        batch.width = width;

        glGenVertexArrays(1, &batch.vao);
        glGenBuffers(1, &batch.vbo);

        glBindVertexArray(batch.vao);
        glBindBuffer(GL_ARRAY_BUFFER, batch.vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.sizeof, vertices.ptr, GL_STATIC_DRAW);

        enum stride = LineVertex.sizeof;
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
        glEnableVertexAttribArray(0);

        glBindVertexArray(0);
        batch.valid = true;
        return batch;
    }

    private static void drawBatch(
        ref const(AxisLineBatch) batch,
        ShaderProgram lineShader,
        mat4 mvpMatrix)
    {
        if (!batch.valid || batch.vao == 0)
            return;

        lineShader.use();
        glUniformMatrix4fv(lineShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(lineShader.location("uColor"), 1, batch.color.ptr);
        glLineWidth(batch.width);

        glBindVertexArray(batch.vao);
        glDrawArrays(GL_LINES, 0, 2);
        glBindVertexArray(0);
    }

    private static void destroyBatch(ref AxisLineBatch batch)
    {
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
        batch.valid = false;
    }
}
