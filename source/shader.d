module shader;

import std.string;

import bindbc.opengl;

struct ShaderProgram
{
    GLuint program;

    bool compile(const(char)* vertexSource, const(char)* fragmentSource)
    {
        GLuint vertexShader = compileStage(GL_VERTEX_SHADER, vertexSource);
        if (vertexShader == 0)
            return false;

        GLuint fragmentShader = compileStage(GL_FRAGMENT_SHADER, fragmentSource);
        if (fragmentShader == 0)
        {
            glDeleteShader(vertexShader);
            return false;
        }

        program = glCreateProgram();
        glAttachShader(program, vertexShader);
        glAttachShader(program, fragmentShader);
        glLinkProgram(program);

        GLint linked = GL_FALSE;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        if (!linked)
        {
            GLint logLength;
            glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
            auto log = new char[logLength];
            glGetProgramInfoLog(program, logLength, null, log.ptr);
            import std.stdio : writeln;
            writeln("Shader link error: ", log.fromStringz);
            glDeleteProgram(program);
            program = 0;
        }

        glDeleteShader(vertexShader);
        glDeleteShader(fragmentShader);
        return program != 0;
    }

    void use() const
    {
        glUseProgram(program);
    }

    GLint location(const(char)* name) const
    {
        return glGetUniformLocation(program, name);
    }

    void destroy()
    {
        if (program != 0)
        {
            glDeleteProgram(program);
            program = 0;
        }
    }

    private static GLuint compileStage(GLenum type, const(char)* source)
    {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &source, null);
        glCompileShader(shader);

        GLint compiled = GL_FALSE;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
        if (!compiled)
        {
            GLint logLength;
            glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
            auto log = new char[logLength];
            glGetShaderInfoLog(shader, logLength, null, log.ptr);
            import std.stdio : writeln;
            writeln("Shader compile error: ", log.fromStringz);
            glDeleteShader(shader);
            return 0;
        }

        return shader;
    }
}

enum meshVertexShader = q{
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;

uniform mat4 uMVP;
uniform mat4 uModel;
uniform mat3 uNormalMatrix;

out vec3 vNormal;
out vec3 vWorldPos;

void main()
{
    vWorldPos = vec3(uModel * vec4(aPos, 1.0));
    vNormal = normalize(uNormalMatrix * aNormal);
    gl_Position = uMVP * vec4(aPos, 1.0);
}
};

enum meshFragmentShader = q{
#version 330 core
in vec3 vNormal;
in vec3 vWorldPos;

out vec4 FragColor;

void main()
{
    vec3 baseColor = vec3(0.62, 0.70, 0.82);
    vec3 lightDir = normalize(vec3(0.4, 0.9, 0.6));
    vec3 viewDir = normalize(-vWorldPos);
    vec3 halfDir = normalize(lightDir + viewDir);

    float ambient = 0.22;
    float diffuse = max(dot(vNormal, lightDir), 0.0);
    float specular = pow(max(dot(vNormal, halfDir), 0.0), 48.0) * 0.18;

    vec3 color = baseColor * (ambient + diffuse * 0.78) + vec3(specular);
    FragColor = vec4(color, 1.0);
}
};

enum lineVertexShader = q{
#version 330 core
layout (location = 0) in vec3 aPos;

uniform mat4 uMVP;

void main()
{
    gl_Position = uMVP * vec4(aPos, 1.0);
}
};

enum lineFragmentShader = q{
#version 330 core
uniform vec3 uColor;

out vec4 FragColor;

void main()
{
    FragColor = vec4(uColor, 1.0);
}
};

enum skeletonMeshVertexShader = q{
#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;

uniform mat4 uMVP;
uniform mat4 uModel;
uniform mat3 uNormalMatrix;

out vec3 vNormal;
out vec3 vWorldPos;

void main()
{
    vWorldPos = vec3(uModel * vec4(aPos, 1.0));
    vNormal = normalize(uNormalMatrix * aNormal);
    gl_Position = uMVP * vec4(aPos, 1.0);
}
};

enum skeletonMeshFragmentShader = q{
#version 330 core
in vec3 vNormal;
in vec3 vWorldPos;

uniform vec3 uColor;

out vec4 FragColor;

void main()
{
    vec3 lightDir = normalize(vec3(0.4, 0.9, 0.6));
    vec3 viewDir = normalize(-vWorldPos);
    vec3 halfDir = normalize(lightDir + viewDir);

    float ambient = 0.28;
    float diffuse = max(dot(vNormal, lightDir), 0.0);
    float specular = pow(max(dot(vNormal, halfDir), 0.0), 32.0) * 0.12;

    vec3 color = uColor * (ambient + diffuse * 0.72) + vec3(specular);
    FragColor = vec4(color, 1.0);
}
};

enum labelVertexShader = q{
#version 330 core
layout (location = 0) in vec2 aCorner;
layout (location = 1) in vec2 aTex;

uniform vec2 uOffset;
uniform vec2 uSize;
uniform vec2 uViewport;

out vec2 vTex;

void main()
{
    vec2 pixelPos = uOffset + aCorner * uSize;
    vec2 ndc;
    ndc.x = (pixelPos.x / uViewport.x) * 2.0 - 1.0;
    ndc.y = (pixelPos.y / uViewport.y) * 2.0 - 1.0;
    gl_Position = vec4(ndc, -0.1, 1.0);
    vTex = aTex;
}
};

enum labelFragmentShader = q{
#version 330 core
in vec2 vTex;

uniform sampler2D uTex;
uniform vec3 uColor;

out vec4 FragColor;

void main()
{
    float alpha = texture(uTex, vTex).a;
    if (alpha < 0.01)
        discard;
    FragColor = vec4(uColor, alpha);
}
};
