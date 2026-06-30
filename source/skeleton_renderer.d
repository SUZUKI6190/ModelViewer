module skeleton_renderer;

import std.algorithm;
import std.math;

import bindbc.opengl;
import gl3n.linalg;

import geo_model;
import mesh;
import shader;

enum SkeletonDisplayStyle
{
    lines,
    cones,
    both,
}

private struct GpuLineBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
    bool valid;
}

private struct GpuMeshBatch
{
    GLuint vao;
    GLuint vbo;
    GLuint ebo;
    GLsizei indexCount;
    bool valid;
}

struct SkeletonRenderer
{
    private GpuLineBatch _boneLines;
    private GpuLineBatch _axisXLines;
    private GpuLineBatch _axisYLines;
    private GpuLineBatch _axisZLines;
    private GpuMeshBatch _coneMesh;
    private GpuMeshBatch _rollMarkMesh;
    private bool _uploaded;

    enum coneSegments = 10;
    enum minBoneLength = 1e-4f;
    enum radiusFactor = 0.10f;
    enum minBaseRadius = 0.02f;
    enum axisLengthFactor = 0.50f;

    @property bool uploaded() const
    {
        return _uploaded;
    }

    @property bool hasContent() const
    {
        return _uploaded && (
            _boneLines.valid ||
            _axisXLines.valid ||
            _coneMesh.valid ||
            _rollMarkMesh.valid);
    }

    bool upload(const(GeoModel) model)
    {
        destroyGpu();

        LineVertex[] boneVertices;
        uint[] boneIndices;
        LineVertex[] axisXVertices;
        uint[] axisXIndices;
        LineVertex[] axisYVertices;
        uint[] axisYIndices;
        LineVertex[] axisZVertices;
        uint[] axisZIndices;
        MeshVertex[] coneVertices;
        uint[] coneIndices;
        MeshVertex[] rollVertices;
        uint[] rollIndices;

        MeshVertex[] unitCone;
        uint[] unitConeIndices;
        buildUnitCone(unitCone, unitConeIndices, coneSegments);

        MeshVertex[] unitRollMark;
        uint[] unitRollMarkIndices;
        buildUnitRollMark(unitRollMark, unitRollMarkIndices);

        foreach (batch; model.triangles)
            collectSkeletonGeometry(
                batch.skeleton,
                unitCone,
                unitConeIndices,
                unitRollMark,
                unitRollMarkIndices,
                boneVertices,
                boneIndices,
                axisXVertices,
                axisXIndices,
                axisYVertices,
                axisYIndices,
                axisZVertices,
                axisZIndices,
                coneVertices,
                coneIndices,
                rollVertices,
                rollIndices);
        foreach (batch; model.lines)
            collectSkeletonGeometry(
                batch.skeleton,
                unitCone,
                unitConeIndices,
                unitRollMark,
                unitRollMarkIndices,
                boneVertices,
                boneIndices,
                axisXVertices,
                axisXIndices,
                axisYVertices,
                axisYIndices,
                axisZVertices,
                axisZIndices,
                coneVertices,
                coneIndices,
                rollVertices,
                rollIndices);

        uploadLineBatch(_boneLines, boneVertices, boneIndices);
        uploadLineBatch(_axisXLines, axisXVertices, axisXIndices);
        uploadLineBatch(_axisYLines, axisYVertices, axisYIndices);
        uploadLineBatch(_axisZLines, axisZVertices, axisZIndices);
        uploadMeshBatch(_coneMesh, coneVertices, coneIndices);
        uploadMeshBatch(_rollMarkMesh, rollVertices, rollIndices);

        _uploaded = true;
        return true;
    }

    void draw(
        SkeletonDisplayStyle style,
        bool showBoneAxes,
        bool showRollMark,
        ShaderProgram lineShader,
        ShaderProgram skeletonMeshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix) const
    {
        if (!_uploaded)
            return;

        const bool drawLines = style == SkeletonDisplayStyle.lines || style == SkeletonDisplayStyle.both;
        const bool drawCones = style == SkeletonDisplayStyle.cones || style == SkeletonDisplayStyle.both;

        enum float[3] dimLineColor = [0.75f, 0.40f, 0.10f];
        enum float[3] brightLineColor = [1.0f, 0.55f, 0.15f];
        enum float lineWidth = 2.5f;

        enum float[3] dimConeColor = [0.70f, 0.38f, 0.08f];
        enum float[3] brightConeColor = [1.0f, 0.55f, 0.15f];
        enum float[3] rollColor = [0.85f, 0.95f, 1.0f];

        enum float[3] axisXColor = [1.0f, 0.25f, 0.25f];
        enum float[3] axisYColor = [0.25f, 1.0f, 0.25f];
        enum float[3] axisZColor = [0.35f, 0.55f, 1.0f];
        enum float axisLineWidth = 2.0f;

        if (drawLines && _boneLines.valid)
            drawLineBatchTwoPass(_boneLines, lineShader, mvpMatrix, dimLineColor, brightLineColor, lineWidth);

        if (drawCones && _coneMesh.valid)
            drawMeshBatchTwoPass(
                _coneMesh, skeletonMeshShader, modelMatrix, mvpMatrix, dimConeColor, brightConeColor);

        if (showRollMark && _rollMarkMesh.valid)
            drawMeshBatchTwoPass(
                _rollMarkMesh, skeletonMeshShader, modelMatrix, mvpMatrix, rollColor, rollColor);

        if (showBoneAxes)
        {
            if (_axisXLines.valid)
                drawLineBatchTwoPass(_axisXLines, lineShader, mvpMatrix, axisXColor, axisXColor, axisLineWidth);
            if (_axisYLines.valid)
                drawLineBatchTwoPass(_axisYLines, lineShader, mvpMatrix, axisYColor, axisYColor, axisLineWidth);
            if (_axisZLines.valid)
                drawLineBatchTwoPass(_axisZLines, lineShader, mvpMatrix, axisZColor, axisZColor, axisLineWidth);
        }
    }

    void destroyGpu()
    {
        destroyLineBatch(_boneLines);
        destroyLineBatch(_axisXLines);
        destroyLineBatch(_axisYLines);
        destroyLineBatch(_axisZLines);
        destroyMeshBatch(_coneMesh);
        destroyMeshBatch(_rollMarkMesh);
        _uploaded = false;
    }

    private static void collectSkeletonGeometry(
        const(Skeleton) skeleton,
        MeshVertex[] unitCone,
        uint[] unitConeIndices,
        MeshVertex[] unitRollMark,
        uint[] unitRollMarkIndices,
        ref LineVertex[] boneVertices,
        ref uint[] boneIndices,
        ref LineVertex[] axisXVertices,
        ref uint[] axisXIndices,
        ref LineVertex[] axisYVertices,
        ref uint[] axisYIndices,
        ref LineVertex[] axisZVertices,
        ref uint[] axisZIndices,
        ref MeshVertex[] coneVertices,
        ref uint[] coneIndices,
        ref MeshVertex[] rollVertices,
        ref uint[] rollIndices)
    {
        if (!skeleton.isValid)
            return;

        foreach (bone; skeleton.bones)
        {
            collectBoneGeometry(
                bone,
                unitCone,
                unitConeIndices,
                unitRollMark,
                unitRollMarkIndices,
                boneVertices,
                boneIndices,
                axisXVertices,
                axisXIndices,
                axisYVertices,
                axisYIndices,
                axisZVertices,
                axisZIndices,
                coneVertices,
                coneIndices,
                rollVertices,
                rollIndices);
        }
    }

    private static void collectBoneGeometry(
        ref const(BoneNode) bone,
        MeshVertex[] unitCone,
        uint[] unitConeIndices,
        MeshVertex[] unitRollMark,
        uint[] unitRollMarkIndices,
        ref LineVertex[] boneVertices,
        ref uint[] boneIndices,
        ref LineVertex[] axisXVertices,
        ref uint[] axisXIndices,
        ref LineVertex[] axisYVertices,
        ref uint[] axisYIndices,
        ref LineVertex[] axisZVertices,
        ref uint[] axisZIndices,
        ref MeshVertex[] coneVertices,
        ref uint[] coneIndices,
        ref MeshVertex[] rollVertices,
        ref uint[] rollIndices)
    {
        vec3 xAxis;
        vec3 yAxis;
        vec3 zAxis;
        computeBoneFrame(bone, xAxis, yAxis, zAxis);

        mat4 boneMatrix = boneLocalMatrix(bone.pos, xAxis, yAxis, zAxis);
        float length = (bone.tailPos - bone.pos).length;
        float baseRadius = length > minBoneLength
            ? max(length * radiusFactor, minBaseRadius)
            : minBaseRadius;
        float axisLen = max(baseRadius * axisLengthFactor, minBaseRadius);

        collectBoneLines(bone, boneVertices, boneIndices);

        collectAxisLine(bone.pos, xAxis, axisLen, axisXVertices, axisXIndices);
        collectAxisLine(bone.pos, yAxis, axisLen, axisYVertices, axisYIndices);
        collectAxisLine(bone.pos, zAxis, axisLen, axisZVertices, axisZIndices);

        if (length > minBoneLength)
        {
            mat4 coneTransform = boneMatrix * mat4.scaling(baseRadius, length, baseRadius);
            appendTransformedMesh(unitCone, unitConeIndices, coneTransform, coneVertices, coneIndices);

            mat4 rollTransform = boneMatrix * mat4.scaling(baseRadius, baseRadius, baseRadius);
            appendTransformedMesh(unitRollMark, unitRollMarkIndices, rollTransform, rollVertices, rollIndices);
        }

        foreach (child; bone.children)
        {
            collectBoneGeometry(
                child,
                unitCone,
                unitConeIndices,
                unitRollMark,
                unitRollMarkIndices,
                boneVertices,
                boneIndices,
                axisXVertices,
                axisXIndices,
                axisYVertices,
                axisYIndices,
                axisZVertices,
                axisZIndices,
                coneVertices,
                coneIndices,
                rollVertices,
                rollIndices);
        }
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

    private static void collectAxisLine(
        vec3 origin,
        vec3 direction,
        float length,
        ref LineVertex[] vertices,
        ref uint[] indices)
    {
        if (direction.length_squared <= 1e-12f)
            return;

        vec3 end = origin + direction * length;
        uint base = cast(uint)vertices.length;
        vertices ~= LineVertex([origin.x, origin.y, origin.z]);
        vertices ~= LineVertex([end.x, end.y, end.z]);
        indices ~= [base, base + 1];
    }

    private static void buildUnitCone(
        ref MeshVertex[] vertices,
        ref uint[] indices,
        int segments)
    {
        vertices ~= MeshVertex([0.0f, 1.0f, 0.0f], [0.0f, 1.0f, 0.0f]);

        uint baseStart = cast(uint)vertices.length;
        for (int i = 0; i < segments; ++i)
        {
            float angle = (2.0f * PI * i) / segments;
            float x = cos(angle);
            float z = sin(angle);
            vec3 sideNormal = vec3(x, 0.35f, z);
            if (sideNormal.length_squared > 1e-12f)
                sideNormal = sideNormal.normalized;
            vertices ~= MeshVertex([x, 0.0f, z], [sideNormal.x, sideNormal.y, sideNormal.z]);
        }

        for (int i = 0; i < segments; ++i)
        {
            indices ~= [
                0,
                baseStart + i,
                baseStart + ((i + 1) % segments),
            ];
        }
    }

    private static void buildUnitRollMark(ref MeshVertex[] vertices, ref uint[] indices)
    {
        enum float markLength = 0.65f;
        enum float markWidth = 0.30f;
        vec3 up = vec3(0, 1, 0);

        vertices ~= MeshVertex([0.0f, 0.0f, 0.0f], [up.x, up.y, up.z]);
        vertices ~= MeshVertex([markLength, 0.0f, markWidth * 0.5f], [up.x, up.y, up.z]);
        vertices ~= MeshVertex([markLength, 0.0f, -markWidth * 0.5f], [up.x, up.y, up.z]);
        indices ~= [0, 1, 2];
    }

    private static void computeBoneFrame(
        ref const(BoneNode) bone,
        out vec3 xAxis,
        out vec3 yAxis,
        out vec3 zAxis)
    {
        vec3 delta = bone.tailPos - bone.pos;
        if (delta.length_squared > minBoneLength * minBoneLength)
            yAxis = delta.normalized;
        else
            yAxis = normalizeAxis(bone.yAxis);

        xAxis = normalizeAxis(bone.xAxis);
        xAxis = xAxis - yAxis * dot(xAxis, yAxis);
        if (xAxis.length_squared <= 1e-12f)
        {
            vec3 reference = fabs(yAxis.y) < 0.9f ? vec3(0, 1, 0) : vec3(1, 0, 0);
            xAxis = cross(reference, yAxis);
        }
        xAxis = xAxis.normalized;
        zAxis = cross(xAxis, yAxis).normalized;
    }

    private static mat4 boneLocalMatrix(vec3 origin, vec3 xAxis, vec3 yAxis, vec3 zAxis)
    {
        mat4 rotation = mat4(
            xAxis.x, yAxis.x, zAxis.x, 0.0f,
            xAxis.y, yAxis.y, zAxis.y, 0.0f,
            xAxis.z, yAxis.z, zAxis.z, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f,
        );
        return mat4.translation(origin) * rotation;
    }

    private static vec3 normalizeAxis(vec3 axis)
    {
        if (axis.length_squared <= 1e-12f)
            return vec3(0, 1, 0);
        return axis.normalized;
    }

    private static void appendTransformedMesh(
        MeshVertex[] unitMesh,
        uint[] unitIndices,
        mat4 transform,
        ref MeshVertex[] outVertices,
        ref uint[] outIndices)
    {
        mat3 rotation = mat3(transform);
        uint base = cast(uint)outVertices.length;

        foreach (vertex; unitMesh)
        {
            vec3 localPos = vec3(vertex.position[0], vertex.position[1], vertex.position[2]);
            vec3 localNormal = vec3(vertex.normal[0], vertex.normal[1], vertex.normal[2]);
            vec3 worldPos = transformPoint(transform, localPos);
            vec3 worldNormal = transformNormal(rotation, localNormal);
            outVertices ~= MeshVertex(
                [worldPos.x, worldPos.y, worldPos.z],
                [worldNormal.x, worldNormal.y, worldNormal.z],
            );
        }

        foreach (index; unitIndices)
            outIndices ~= base + index;
    }

    private static vec3 transformPoint(mat4 transform, vec3 point)
    {
        vec4 result = transform * vec4(point, 1.0f);
        return vec3(result.x, result.y, result.z);
    }

    private static vec3 transformNormal(mat3 rotation, vec3 normal)
    {
        vec3 result = rotation * normal;
        if (result.length_squared <= 1e-12f)
            return normal;
        return result.normalized;
    }

    private static void uploadLineBatch(
        ref GpuLineBatch batch,
        LineVertex[] vertices,
        uint[] indices)
    {
        if (vertices.length == 0 || indices.length == 0)
            return;

        batch.indexCount = cast(GLsizei)(indices.length);

        glGenVertexArrays(1, &batch.vao);
        glGenBuffers(1, &batch.vbo);
        glGenBuffers(1, &batch.ebo);

        glBindVertexArray(batch.vao);

        glBindBuffer(GL_ARRAY_BUFFER, batch.vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * LineVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, batch.ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);

        enum stride = LineVertex.sizeof;
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
        glEnableVertexAttribArray(0);

        glBindVertexArray(0);
        batch.valid = true;
    }

    private static void uploadMeshBatch(
        ref GpuMeshBatch batch,
        MeshVertex[] vertices,
        uint[] indices)
    {
        if (vertices.length == 0 || indices.length == 0)
            return;

        batch.indexCount = cast(GLsizei)(indices.length);

        glGenVertexArrays(1, &batch.vao);
        glGenBuffers(1, &batch.vbo);
        glGenBuffers(1, &batch.ebo);

        glBindVertexArray(batch.vao);

        glBindBuffer(GL_ARRAY_BUFFER, batch.vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * MeshVertex.sizeof, vertices.ptr, GL_STATIC_DRAW);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, batch.ebo);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof, indices.ptr, GL_STATIC_DRAW);

        enum stride = MeshVertex.sizeof;
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, null);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, cast(void*)(float.sizeof * 3));
        glEnableVertexAttribArray(1);

        glBindVertexArray(0);
        batch.valid = true;
    }

    private static void drawLineBatchTwoPass(
        ref const(GpuLineBatch) batch,
        ShaderProgram lineShader,
        mat4 mvpMatrix,
        float[3] dimColor,
        float[3] brightColor,
        float width)
    {
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        drawLineBatch(batch, lineShader, mvpMatrix, dimColor, width);

        glDisable(GL_DEPTH_TEST);
        drawLineBatch(batch, lineShader, mvpMatrix, brightColor, width);
        glEnable(GL_DEPTH_TEST);
    }

    private static void drawMeshBatchTwoPass(
        ref const(GpuMeshBatch) batch,
        ShaderProgram meshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        float[3] dimColor,
        float[3] brightColor)
    {
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        drawMeshBatch(batch, meshShader, modelMatrix, mvpMatrix, dimColor);

        glDisable(GL_DEPTH_TEST);
        drawMeshBatch(batch, meshShader, modelMatrix, mvpMatrix, brightColor);
        glEnable(GL_DEPTH_TEST);
    }

    private static void drawLineBatch(
        ref const(GpuLineBatch) batch,
        ShaderProgram lineShader,
        mat4 mvpMatrix,
        float[3] color,
        float width)
    {
        if (!batch.valid || batch.indexCount == 0)
            return;

        lineShader.use();
        glUniformMatrix4fv(lineShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(lineShader.location("uColor"), 1, color.ptr);
        glLineWidth(width);

        glBindVertexArray(batch.vao);
        glDrawElements(GL_LINES, batch.indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }

    private static void drawMeshBatch(
        ref const(GpuMeshBatch) batch,
        ShaderProgram meshShader,
        mat4 modelMatrix,
        mat4 mvpMatrix,
        float[3] color)
    {
        if (!batch.valid || batch.indexCount == 0)
            return;

        meshShader.use();
        glUniformMatrix4fv(meshShader.location("uModel"), 1, GL_TRUE, modelMatrix.value_ptr);
        glUniformMatrix4fv(meshShader.location("uMVP"), 1, GL_TRUE, mvpMatrix.value_ptr);
        glUniform3fv(meshShader.location("uColor"), 1, color.ptr);

        float[9] normalMatrix = extractNormalMatrix(modelMatrix);
        glUniformMatrix3fv(meshShader.location("uNormalMatrix"), 1, GL_TRUE, normalMatrix.ptr);

        glBindVertexArray(batch.vao);
        glDrawElements(GL_TRIANGLES, batch.indexCount, GL_UNSIGNED_INT, null);
        glBindVertexArray(0);
    }

    private static void destroyLineBatch(ref GpuLineBatch batch)
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
        batch.valid = false;
    }

    private static void destroyMeshBatch(ref GpuMeshBatch batch)
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
        batch.valid = false;
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
