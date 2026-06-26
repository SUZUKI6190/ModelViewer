module axis_label;

import bindbc.opengl;
static import gl3n.linalg;

import dlangui;
import dlangui.core.types : Glyph;
import dlangui.graphics.fonts : FontManager, FontFamily;

import shader;

enum cornerGizmoSize = 96;
enum cornerAxisLength = 1.0f;
enum axisLabelOffsetScale = 1.1f;

private struct LetterTexture
{
    GLuint id;
    int width;
    int height;
    bool valid;
}

struct AxisLabelRenderer
{
    private ShaderProgram _shader;
    private LetterTexture _x;
    private LetterTexture _y;
    private LetterTexture _z;
    private GLuint _vao;
    private GLuint _vbo;
    private bool _gpuReady;

    @property bool ready() const
    {
        return _gpuReady;
    }

    bool ensureGpu()
    {
        if (_shader.program == 0)
        {
            if (!_shader.compile(labelVertexShader, labelFragmentShader))
                return false;
        }

        if (!_x.valid)
        {
            FontRef font = FontManager.instance.getFont(
                14, cast(int)FontWeight.Bold, false, FontFamily.SansSerif, "");
            _x = createLetterTexture(font, "X"d);
            _y = createLetterTexture(font, "Y"d);
            _z = createLetterTexture(font, "Z"d);
            if (!_x.valid || !_y.valid || !_z.valid)
                return false;

            static immutable float[24] quadVertices = [
                0.0f, 0.0f, 0.0f, 1.0f,
                1.0f, 0.0f, 1.0f, 1.0f,
                1.0f, 1.0f, 1.0f, 0.0f,
                0.0f, 0.0f, 0.0f, 1.0f,
                1.0f, 1.0f, 1.0f, 0.0f,
                0.0f, 1.0f, 0.0f, 0.0f,
            ];

            glGenVertexArrays(1, &_vao);
            glGenBuffers(1, &_vbo);
            glBindVertexArray(_vao);
            glBindBuffer(GL_ARRAY_BUFFER, _vbo);
            glBufferData(GL_ARRAY_BUFFER, quadVertices.sizeof, quadVertices.ptr, GL_STATIC_DRAW);
            enum stride = 4 * float.sizeof;
            glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, null);
            glEnableVertexAttribArray(0);
            glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, cast(void*)(2 * float.sizeof));
            glEnableVertexAttribArray(1);
            glBindVertexArray(0);
        }

        _gpuReady = true;
        return true;
    }

    void draw(
        gl3n.linalg.mat4 mvp,
        float axisLength,
        int viewportWidth,
        int viewportHeight)
    {
        if (!_gpuReady || viewportWidth <= 0 || viewportHeight <= 0)
            return;

        struct LabelSpec
        {
            gl3n.linalg.vec3 direction;
            LetterTexture texture;
            float[3] color;
        }

        LabelSpec[] specs = [
            LabelSpec(gl3n.linalg.vec3(1, 0, 0), _x, [1.0f, 0.25f, 0.25f]),
            LabelSpec(gl3n.linalg.vec3(0, 1, 0), _y, [0.25f, 1.0f, 0.25f]),
            LabelSpec(gl3n.linalg.vec3(0, 0, 1), _z, [0.35f, 0.55f, 1.0f]),
        ];

        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        _shader.use();
        glUniform2f(_shader.location("uViewport"), cast(float)viewportWidth, cast(float)viewportHeight);

        glBindVertexArray(_vao);

        float labelLength = axisLength * axisLabelOffsetScale;
        foreach (spec; specs)
        {
            gl3n.linalg.vec3 tip = spec.direction * labelLength;
            float centerX;
            float centerY;
            if (!projectToViewport(mvp, tip, viewportWidth, viewportHeight, centerX, centerY))
                continue;

            float w = cast(float)spec.texture.width;
            float h = cast(float)spec.texture.height;
            float left = centerX - w * 0.5f;
            float bottom = centerY - h * 0.5f;

            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, spec.texture.id);
            glUniform1i(_shader.location("uTex"), 0);
            glUniform2f(_shader.location("uOffset"), left, bottom);
            glUniform2f(_shader.location("uSize"), w, h);
            glUniform3fv(_shader.location("uColor"), 1, spec.color.ptr);
            glDrawArrays(GL_TRIANGLES, 0, 6);
        }

        glBindVertexArray(0);
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    void destroyGpu()
    {
        destroyLetterTexture(_x);
        destroyLetterTexture(_y);
        destroyLetterTexture(_z);
        if (_vbo != 0)
        {
            glDeleteBuffers(1, &_vbo);
            _vbo = 0;
        }
        if (_vao != 0)
        {
            glDeleteVertexArrays(1, &_vao);
            _vao = 0;
        }
        _shader.destroy();
        _gpuReady = false;
    }

    private static bool projectToViewport(
        gl3n.linalg.mat4 mvp,
        gl3n.linalg.vec3 worldPos,
        int viewportWidth,
        int viewportHeight,
        out float glX,
        out float glY)
    {
        gl3n.linalg.vec4 clip = mvp * gl3n.linalg.vec4(worldPos, 1.0f);
        if (clip.w <= 1e-6f)
            return false;

        float invW = 1.0f / clip.w;
        float ndcX = clip.x * invW;
        float ndcY = clip.y * invW;

        glX = (ndcX + 1.0f) * 0.5f * viewportWidth;
        glY = (ndcY + 1.0f) * 0.5f * viewportHeight;
        return true;
    }

    private static LetterTexture createLetterTexture(FontRef font, dstring letter)
    {
        LetterTexture result;
        if (letter.length == 0)
            return result;

        Glyph* glyph = font.getCharGlyph(letter[0]);
        if (glyph is null || glyph.blackBoxX == 0 || glyph.blackBoxY == 0)
            return result;

        Point sz = font.textSize(letter);
        enum pad = 2;
        int w = sz.x + pad * 2;
        int h = sz.y + pad * 2;
        if (w < 1)
            w = 1;
        if (h < 1)
            h = 1;

        ubyte[] rgba = new ubyte[w * h * 4];

        int baseline = font.baseline;
        int gx = pad + glyph.originX;
        int gy = pad + baseline - glyph.originY;
        ubyte[] src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;

        foreach (yy; 0 .. srcdy)
        {
            int liney = gy + yy;
            if (liney < 0 || liney >= h)
                continue;
            ubyte* srcrow = src.ptr + yy * srcdx;
            foreach (xx; 0 .. srcdx)
            {
                ubyte cover = srcrow[xx];
                if (cover == 0)
                    continue;
                int colx = gx + xx;
                if (colx < 0 || colx >= w)
                    continue;
                size_t i = (liney * w + colx) * 4;
                rgba[i + 0] = 255;
                rgba[i + 1] = 255;
                rgba[i + 2] = 255;
                rgba[i + 3] = cover;
            }
        }

        glGenTextures(1, &result.id);
        glBindTexture(GL_TEXTURE_2D, result.id);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, rgba.ptr);
        glBindTexture(GL_TEXTURE_2D, 0);

        result.width = w;
        result.height = h;
        result.valid = result.id != 0;
        return result;
    }

    private static void destroyLetterTexture(ref LetterTexture tex)
    {
        if (tex.id != 0)
        {
            glDeleteTextures(1, &tex.id);
            tex.id = 0;
        }
        tex.valid = false;
        tex.width = 0;
        tex.height = 0;
    }
}
