module app;

import std.algorithm;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;

import bindbc.glfw;
import bindbc.opengl;
import bindbc.imgui.bind.imgui;
import bindbc.imgui.dynload;

import gl3n.linalg;

import camera;
import geo_model;
import geo_parser;
import imgui_helper;
import imgui_input;
import imgui_ogl;
import mesh;
import shader;

struct AppState
{
    GeoModel model;
    Mesh mesh;
    ArcballCamera camera;
    string modelPath;
    string loadError;
    char[512] pathBuffer;
}

extern(C) void glfw_error_callback(int code, const(char)* description) nothrow @nogc
{
}

void main(string[] args)
{
    AppState state;
    state.modelPath = defaultModelPath(args);
    state.pathBuffer[] = 0;
    if (state.modelPath.length < state.pathBuffer.length)
        state.pathBuffer[0 .. state.modelPath.length] = state.modelPath;

    if (loadGLFW() == GLFWSupport.noLibrary)
    {
        writeln("Failed to load GLFW");
        return;
    }

    glfwSetErrorCallback(&glfw_error_callback);
    if (!glfwInit())
    {
        writeln("Failed to initialize GLFW");
        return;
    }
    scope (exit) glfwTerminate();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_SAMPLES, 4);

    GLFWwindow* window = glfwCreateWindow(1280, 720, "ModelViewer - Geo XML", null, null);
    if (window is null)
    {
        writeln("Failed to create GLFW window");
        return;
    }
    scope (exit) glfwDestroyWindow(window);

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    if (loadOpenGL() == GLSupport.noContext)
    {
        writeln("Failed to load OpenGL");
        return;
    }

    version (BindImGui_Dynamic)
    {
        import bindbc.imgui.config : ImGuiSupport;
        auto imguiSupport = loadImGui();
        if (imguiSupport == ImGuiSupport.noLibrary || imguiSupport == ImGuiSupport.badLibrary)
        {
            writeln("Failed to load ImGui: ", imguiSupport);
            return;
        }
        scope (exit) unloadImGui();
    }

    igCreateContext(null);
    scope (exit) igDestroyContext(null);
    igStyleColorsDark(null);

    ImGuiOpenGLBackend.init("#version 330");
    scope (exit) ImGuiOpenGLBackend.shutdown();

    installImGuiInput(window);

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_MULTISAMPLE);
    glClearColor(0.12f, 0.14f, 0.18f, 1.0f);

    if (!tryLoadModel(state))
        writeln("Initial load warning: ", state.loadError);
    else
        writeln("Loaded: ", state.model.name, " (", state.model.vertexCount, " vertices, ",
            state.model.triangleCount, " triangles)");

    ShaderProgram shader;
    if (!shader.compile(meshVertexShader, meshFragmentShader))
    {
        writeln("Failed to compile shaders");
        return;
    }
    scope (exit) shader.destroy();
    scope (exit) state.mesh.destroy();

    double lastFrameTime = glfwGetTime();

    while (!glfwWindowShouldClose(window))
    {
        glfwPollEvents();

        if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
            break;

        double currentTime = glfwGetTime();
        float deltaTime = cast(float)(currentTime - lastFrameTime);
        lastFrameTime = currentTime;
        if (deltaTime <= 0.0f)
            deltaTime = 1.0f / 60.0f;

        int width;
        int height;
        glfwGetFramebufferSize(window, &width, &height);
        if (width == 0 || height == 0)
            continue;

        imguiNewFrameFromGlfw(window, cast(float)width, cast(float)height, deltaTime);
        ImGuiOpenGLBackend.new_frame();
        igNewFrame();

        drawUiPanel(state);

        igRender();
        ImDrawData* drawData = igGetDrawData();

        if (glfwGetKey(window, GLFW_KEY_R) == GLFW_PRESS)
        {
            vec3 minBound;
            vec3 maxBound;
            state.model.computeBounds(minBound, maxBound);
            state.camera.fitToBounds(minBound, maxBound);
        }

        bool imguiCapturesMouse = mv_imgui_want_capture_mouse() != 0;
        if (!imguiCapturesMouse)
        {
            updateCameraInput(window, state.camera, cast(float)width, cast(float)height);
            state.camera.registerScroll(consumeGlfwScroll());
        }
        else
        {
            consumeGlfwScroll();
        }

        float scrollDelta = state.camera.consumeScrollPending();
        if (scrollDelta != 0.0f)
            state.camera.zoom(scrollDelta);

        mat4 modelMatrix = mat4.identity;
        mat4 viewMatrix = state.camera.viewMatrix();
        mat4 projectionMatrix = state.camera.projectionMatrix(cast(float)width, cast(float)height);
        mat4 mvpMatrix = projectionMatrix * viewMatrix * modelMatrix;

        glViewport(0, 0, width, height);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        state.mesh.draw(shader, modelMatrix, mvpMatrix);

        ImGuiOpenGLBackend.render_draw_data(drawData);

        glfwSwapBuffers(window);
    }
}

private string defaultModelPath(string[] args)
{
    if (args.length > 1)
        return args[1];

    return buildPath(thisExePath().dirName, "../data/cube.geo.xml");
}

private bool tryLoadModel(ref AppState state)
{
    try
    {
        state.mesh.destroy();
        state.model = parseGeoFile(state.modelPath);

        vec3 minBound;
        vec3 maxBound;
        state.model.computeBounds(minBound, maxBound);
        state.camera.fitToBounds(minBound, maxBound);

        if (!state.mesh.upload(state.model))
        {
            state.loadError = "Failed to upload mesh to GPU";
            return false;
        }

        state.loadError = "";
        return true;
    }
    catch (Exception ex)
    {
        state.loadError = ex.msg;
        return false;
    }
}

private void drawUiPanel(ref AppState state)
{
    igBegin("Geo XML Viewer", null, ImGuiWindowFlags.None);

    igText("Model".ptr);
    igInputText("Path".ptr, state.pathBuffer.ptr, state.pathBuffer.length,
        ImGuiInputTextFlags.None, null, null);
    if (igButton("Load".ptr))
    {
        state.modelPath = state.pathBuffer.fromStringz.idup;
        if (!tryLoadModel(state))
            writeln("Load failed: ", state.loadError);
        else
            writeln("Loaded: ", state.model.name);
    }

    if (state.loadError.length > 0)
        igTextColored(ImVec4(1.0f, 0.35f, 0.35f, 1.0f), ("Error: " ~ state.loadError).ptr);
    else if (state.model.name.length > 0)
    {
        igSeparator();
        igText(("Name: " ~ state.model.name).ptr);
        igText(("Vertices: " ~ state.model.vertexCount.to!string).ptr);
        igText(("Triangles: " ~ state.model.triangleCount.to!string).ptr);
    }

    igSeparator();
    igText("Controls".ptr);
    igBulletText("Left drag: rotate (arcball)".ptr);
    igBulletText("Right drag: pan".ptr);
    igBulletText("Wheel: zoom".ptr);
    igBulletText("Shift + drag: fast pan".ptr);
    igBulletText("R: reset camera".ptr);
    igBulletText("Esc: quit".ptr);

    igEnd();
}

private void updateCameraInput(GLFWwindow* window, ref ArcballCamera camera, float width, float height)
{
    double cursorX;
    double cursorY;
    glfwGetCursorPos(window, &cursorX, &cursorY);
    vec2 mousePos = vec2(cast(float)cursorX, cast(float)cursorY);
    vec2 viewport = vec2(width, height);

    bool shiftDown = glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS
        || glfwGetKey(window, GLFW_KEY_RIGHT_SHIFT) == GLFW_PRESS;
    bool leftDown = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
    bool rightDown = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS;

    if (leftDown || rightDown)
    {
        DragMode mode;
        if (shiftDown)
            mode = DragMode.fastPan;
        else if (rightDown)
            mode = DragMode.pan;
        else
            mode = DragMode.rotate;

        if (!camera.dragging || camera.dragMode != mode)
            camera.beginDrag(mode, mousePos, viewport);
        else
            camera.updateDrag(mousePos, viewport);
    }
    else
    {
        camera.resetDrag();
    }
}
