module app;

import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;

import bindbc.opengl;
import dlangui;
import dlangui.graphics.glsupport : GLProgram, VAO;
import dlangui.graphics.resources;
static import gl3n.linalg;

import axis_gizmo;
import axis_label;
import camera;
import geo_model;
import geo_parser;
import mesh;
import settings;
import shader;

mixin APP_ENTRY_POINT;

struct AppState
{
    GeoModel model;
    GeoMesh mesh;
    ArcballCamera camera;
    string modelPath;
    string loadError;
    bool meshGpuDirty;
    bool showNormals;
    bool showWorldAxes = true;
    bool showCornerAxes = true;
    float axisLength = 1.0f;
    bool axisGpuDirty = true;
}

class ViewportWidget : Widget
{
    AppState* _state;
    ShaderProgram* _meshShader;
    ShaderProgram* _lineShader;
    bool _shaderCompileFailed;
    void delegate() _onGpuStateChanged;
    bool _gpuStateReported;
    AxisGizmo _axisGizmo;
    AxisLabelRenderer _axisLabels;

    this(
        AppState* state,
        ShaderProgram* meshShader,
        ShaderProgram* lineShader,
        void delegate() onGpuStateChanged = null)
    {
        super("viewport");
        _state = state;
        _meshShader = meshShader;
        _lineShader = lineShader;
        _onGpuStateChanged = onGpuStateChanged;
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        layoutWeight = 1;
        minWidth = 100;
        backgroundDrawable = DrawableRef(new OpenGLDrawable(&drawScene));
    }

    override void measure(int parentWidth, int parentHeight)
    {
        measuredContent(parentWidth, parentHeight, 100, 0);
    }

    private void reportGpuStateOnce()
    {
        if (_gpuStateReported || _onGpuStateChanged is null)
            return;
        _gpuStateReported = true;
        _onGpuStateChanged();
    }

    /// OpenGL calls must run while the drawable context is current (Win32 needs this).
    private bool ensureGpuResources()
    {
        if (_shaderCompileFailed)
        {
            reportGpuStateOnce();
            return false;
        }

        if (_meshShader.program == 0)
        {
            if (!_meshShader.compile(meshVertexShader, meshFragmentShader))
            {
                _shaderCompileFailed = true;
                _state.loadError = "Failed to compile mesh shaders";
                reportGpuStateOnce();
                return false;
            }
        }

        if (_lineShader.program == 0)
        {
            if (!_lineShader.compile(lineVertexShader, lineFragmentShader))
            {
                _shaderCompileFailed = true;
                _state.loadError = "Failed to compile line shaders";
                reportGpuStateOnce();
                return false;
            }
        }

        if (_state.meshGpuDirty)
        {
            _state.mesh.destroyGpu();
            _state.meshGpuDirty = false;
        }

        if (_state.model.hasDrawableGeometry && !_state.mesh.uploaded)
        {
            if (!_state.mesh.upload(_state.model))
            {
                _state.loadError = "Failed to upload mesh to GPU";
                reportGpuStateOnce();
                return false;
            }
        }

        if (_state.axisGpuDirty || !_axisGizmo.uploaded)
        {
            _axisGizmo.upload(_state.axisLength);
            _state.axisGpuDirty = false;
        }

        if (!_axisLabels.ensureGpu())
        {
            _state.loadError = "Failed to initialize axis labels";
            reportGpuStateOnce();
            return false;
        }

        reportGpuStateOnce();
        return true;
    }

    void resetGpuState()
    {
        _gpuStateReported = false;
        _shaderCompileFailed = false;
        _state.axisGpuDirty = true;
        _axisLabels.destroyGpu();
    }

    override bool onMouseEvent(MouseEvent event)
    {
        auto viewport = gl3n.linalg.vec2(cast(float)width, cast(float)height);
        auto mousePos = gl3n.linalg.vec2(cast(float)event.x, cast(float)event.y);

        switch (event.action)
        {
        case MouseAction.Wheel:
            _state.camera.registerScroll(cast(float)event.wheelDelta);
            invalidate();
            return true;

        case MouseAction.ButtonDown:
            beginCameraDrag(event, mousePos, viewport);
            invalidate();
            return true;

        case MouseAction.Move:
            if (_state.camera.dragging)
            {
                _state.camera.updateDrag(mousePos, viewport);
                invalidate();
            }
            return true;

        case MouseAction.ButtonUp:
            _state.camera.resetDrag();
            invalidate();
            return true;

        default:
            return false;
        }
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.action != KeyAction.KeyDown)
            return false;

        if (event.keyCode == KeyCode.KEY_R)
        {
            gl3n.linalg.vec3 minBound;
            gl3n.linalg.vec3 maxBound;
            _state.model.computeBounds(minBound, maxBound);
            _state.camera.fitToBounds(minBound, maxBound);
            invalidate();
            return true;
        }

        return false;
    }

    private void beginCameraDrag(MouseEvent event, gl3n.linalg.vec2 mousePos, gl3n.linalg.vec2 viewport)
    {
        bool shiftDown = (event.flags & MouseFlag.Shift) != 0;
        DragMode mode;
        if (shiftDown)
            mode = DragMode.fastPan;
        else if (event.button == MouseButton.Right)
            mode = DragMode.pan;
        else if (event.button == MouseButton.Left)
            mode = DragMode.rotate;
        else
            return;

        _state.camera.beginDrag(mode, mousePos, viewport);
    }

    private void drawScene(Rect windowRect, Rect rc)
    {
        if (rc.width <= 0 || rc.height <= 0)
        {
            Log.w("Viewport draw skipped: zero size ", rc);
            return;
        }

        if (!ensureGpuResources())
            return;

        float scrollDelta = _state.camera.consumeScrollPending();
        if (scrollDelta != 0.0f)
            _state.camera.zoom(scrollDelta);

        glViewport(rc.left, windowRect.height - rc.bottom, rc.width, rc.height);
        glEnable(GL_SCISSOR_TEST);
        glScissor(rc.left, windowRect.height - rc.bottom, rc.width, rc.height);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_MULTISAMPLE);
        glClearColor(0.12f, 0.14f, 0.18f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        gl3n.linalg.mat4 modelMatrix = gl3n.linalg.mat4.identity;
        gl3n.linalg.mat4 viewMatrix = _state.camera.viewMatrix();
        gl3n.linalg.mat4 projectionMatrix = _state.camera.projectionMatrix(
            cast(float)rc.width, cast(float)rc.height);
        gl3n.linalg.mat4 mvpMatrix = projectionMatrix * viewMatrix * modelMatrix;

        _state.mesh.draw(*_meshShader, *_lineShader, modelMatrix, mvpMatrix, _state.showNormals);

        if (_state.showWorldAxes)
        {
            gl3n.linalg.mat4 axisMvp = projectionMatrix * viewMatrix * modelMatrix;
            _axisGizmo.drawWorld(*_lineShader, axisMvp);
            if (_axisLabels.ready)
                _axisLabels.draw(axisMvp, _state.axisLength, rc.width, rc.height);
        }

        if (_state.showCornerAxes)
        {
            enum gizmoSize = cornerGizmoSize;
            int gizmoX = rc.left;
            int gizmoY = windowRect.height - rc.bottom;

            glViewport(gizmoX, gizmoY, gizmoSize, gizmoSize);
            glScissor(gizmoX, gizmoY, gizmoSize, gizmoSize);
            glClear(GL_DEPTH_BUFFER_BIT);

            gl3n.linalg.mat4 gizmoView = _state.camera.gizmoViewMatrix();
            gl3n.linalg.mat4 gizmoProj = gl3n.linalg.mat4.orthographic(
                -1.2f, 1.2f, -1.2f, 1.2f, 0.1f, 10.0f);
            gl3n.linalg.mat4 gizmoMvp = gizmoProj * gizmoView;
            _axisGizmo.drawCorner(*_lineShader, gizmoMvp);
            if (_axisLabels.ready)
                _axisLabels.draw(gizmoMvp, cornerAxisLength, gizmoSize, gizmoSize);
        }

        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_MULTISAMPLE);

        VAO.unbind();
        GLProgram.unbind();
    }
}

class ModelViewerWidget : HorizontalLayout
{
    AppState* _state;
    ShaderProgram _meshShader;
    ShaderProgram _lineShader;
    Window _window;

    EditLine _pathEdit;
    TextWidget _errorText;
    TextWidget _nameText;
    TextWidget _vertexText;
    TextWidget _triangleText;
    TextWidget _lineText;
    CheckBox _showNormalsCheck;
    CheckBox _showWorldAxesCheck;
    CheckBox _showCornerAxesCheck;
    VerticalLayout _panel;
    ViewportWidget _viewport;

    this(Window window, AppState* state)
    {
        super("main");
        _window = window;
        _state = state;
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        auto panel = new VerticalLayout("panel");
        _panel = panel;
        panel.layoutWidth = 320;
        panel.minWidth = 320;
        panel.maxWidth = 320;
        panel.layoutHeight = FILL_PARENT;
        panel.margins = Rect(12, 12, 12, 12);
        panel.padding = Rect(8, 8, 8, 8);
        panel.backgroundColor = 0xFFF2F2F2u;

        auto title = new TextWidget("title", "Geo XML Viewer"d);
        title.fontSize = 18;
        title.fontWeight = FontWeight.Bold;
        panel.addChild(title);

        panel.addChild(new TextWidget("modelLabel", "Model"d));

        _pathEdit = new EditLine("path");
        _pathEdit.layoutWidth = FILL_PARENT;
        _pathEdit.text = _state.modelPath.to!dstring;
        panel.addChild(_pathEdit);

        auto loadButton = new Button("load", "Load"d);
        loadButton.click = &onLoadClicked;
        panel.addChild(loadButton);

        _errorText = new TextWidget("error");
        _errorText.textColor = 0xFFFF5959u;
        _errorText.visibility = Visibility.Gone;
        panel.addChild(_errorText);

        _nameText = new TextWidget("name");
        _nameText.visibility = Visibility.Gone;
        panel.addChild(_nameText);

        _vertexText = new TextWidget("vertices");
        _vertexText.visibility = Visibility.Gone;
        panel.addChild(_vertexText);

        _triangleText = new TextWidget("triangles");
        _triangleText.visibility = Visibility.Gone;
        panel.addChild(_triangleText);

        _lineText = new TextWidget("lines");
        _lineText.visibility = Visibility.Gone;
        panel.addChild(_lineText);

        _showNormalsCheck = new CheckBox("showNormals", "Show normals"d);
        _showNormalsCheck.checked = _state.showNormals;
        _showNormalsCheck.visibility = Visibility.Gone;
        _showNormalsCheck.addOnCheckChangeListener(&onShowNormalsChanged);
        panel.addChild(_showNormalsCheck);

        _showWorldAxesCheck = new CheckBox("showWorldAxes", "Show world axes"d);
        _showWorldAxesCheck.checked = _state.showWorldAxes;
        _showWorldAxesCheck.addOnCheckChangeListener(&onShowWorldAxesChanged);
        panel.addChild(_showWorldAxesCheck);

        _showCornerAxesCheck = new CheckBox("showCornerAxes", "Show corner axes"d);
        _showCornerAxesCheck.checked = _state.showCornerAxes;
        _showCornerAxesCheck.addOnCheckChangeListener(&onShowCornerAxesChanged);
        panel.addChild(_showCornerAxesCheck);

        auto spacer = new VSpacer();
        spacer.layoutHeight = 12;
        panel.addChild(spacer);

        panel.addChild(new TextWidget("controlsTitle", "Controls"d));
        panel.addChild(new TextWidget("ctrl1", "• Left drag: rotate (arcball)"d));
        panel.addChild(new TextWidget("ctrl2", "• Right drag: pan"d));
        panel.addChild(new TextWidget("ctrl3", "• Wheel: zoom"d));
        panel.addChild(new TextWidget("ctrl4", "• Shift + drag: fast pan"d));
        panel.addChild(new TextWidget("ctrl5", "• R: reset camera"d));
        panel.addChild(new TextWidget("ctrl6", "• Esc: quit"d));

        addChild(panel);

        _viewport = new ViewportWidget(_state, &_meshShader, &_lineShader, &onGpuStateChanged);
        addChild(_viewport);

        if (!tryLoadModel())
            writeln("Initial load warning: ", _state.loadError);
        else
            writeln("Loaded: ", _state.model.name, " (", _state.model.vertexCount,
                " vertices, ", _state.model.triangleCount, " triangles, ",
                _state.model.lineBatchCount, " line batches)");

        refreshUi();
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.Visible)
            return;
        Rect rc = _pos;
        applyMargins(rc);
        auto bgSaver = ClipRectSaver(buf, rc, alpha);
        DrawableRef bg = backgroundDrawable;
        if (!bg.isNull)
            bg.drawTo(buf, rc, state);
        applyPadding(rc);
        auto saver = ClipRectSaver(buf, rc, alpha);
        _viewport.onDraw(buf);
        _panel.onDraw(buf);
    }

    ~this()
    {
        _state.mesh.release();
        _meshShader.program = 0;
        _lineShader.program = 0;
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.KeyDown && event.keyCode == KeyCode.ESCAPE)
        {
            _window.close();
            return true;
        }
        return super.onKeyEvent(event);
    }

    private void refreshUi()
    {
        updateModelInfo();
        _panel.requestLayout();
        requestLayout();
        _window.update(true);
    }

    private void onGpuStateChanged()
    {
        refreshUi();
    }

    private bool onLoadClicked(Widget)
    {
        _state.modelPath = _pathEdit.text.to!string;
        _viewport.resetGpuState();
        if (!tryLoadModel())
            Log.w("Load failed: ", _state.loadError);
        else
            Log.i("Loaded: ", _state.model.name);

        refreshUi();
        return true;
    }

    private bool onShowNormalsChanged(Widget, bool checked)
    {
        _state.showNormals = checked;
        _viewport.invalidate();
        return true;
    }

    private bool onShowWorldAxesChanged(Widget, bool checked)
    {
        _state.showWorldAxes = checked;
        _viewport.invalidate();
        return true;
    }

    private bool onShowCornerAxesChanged(Widget, bool checked)
    {
        _state.showCornerAxes = checked;
        _viewport.invalidate();
        return true;
    }

    private bool tryLoadModel()
    {
        try
        {
            _state.mesh.release();
            _state.meshGpuDirty = true;
            _state.model = parseGeoFile(_state.modelPath);

            gl3n.linalg.vec3 minBound;
            gl3n.linalg.vec3 maxBound;
            _state.model.computeBounds(minBound, maxBound);
            _state.camera.fitToBounds(minBound, maxBound);

            float axisLen = (maxBound - minBound).length * 0.2f;
            _state.axisLength = axisLen > 1e-4f ? axisLen : 1.0f;
            _state.axisGpuDirty = true;

            _state.loadError = "";
            saveLastModelPath(_state.modelPath);
            return true;
        }
        catch (Exception ex)
        {
            _state.loadError = ex.msg;
            return false;
        }
    }

    private void updateModelInfo()
    {
        if (_state.loadError.length > 0)
        {
            _errorText.text = ("Error: " ~ _state.loadError).to!dstring;
            _errorText.visibility = Visibility.Visible;
            _nameText.visibility = Visibility.Gone;
            _vertexText.visibility = Visibility.Gone;
            _triangleText.visibility = Visibility.Gone;
            _lineText.visibility = Visibility.Gone;
            _showNormalsCheck.visibility = Visibility.Gone;
            return;
        }

        _errorText.visibility = Visibility.Gone;

        if (_state.model.name.length > 0)
        {
            _nameText.text = ("Name: " ~ _state.model.name).to!dstring;
            _vertexText.text = ("Vertices: " ~ _state.model.vertexCount.to!string).to!dstring;
            _triangleText.text = ("Triangles: " ~ _state.model.triangleCount.to!string).to!dstring;
            _lineText.text = ("Line batches: " ~ _state.model.lineBatchCount.to!string).to!dstring;
            _nameText.visibility = Visibility.Visible;
            _vertexText.visibility = Visibility.Visible;
            _triangleText.visibility = Visibility.Visible;
            _lineText.visibility = Visibility.Visible;

            if (_state.model.triangleCount > 0)
            {
                _showNormalsCheck.visibility = Visibility.Visible;
                _showNormalsCheck.checked = _state.showNormals;
            }
            else
            {
                _state.showNormals = false;
                _showNormalsCheck.checked = false;
                _showNormalsCheck.visibility = Visibility.Gone;
            }
        }
        else
        {
            _nameText.visibility = Visibility.Gone;
            _vertexText.visibility = Visibility.Gone;
            _triangleText.visibility = Visibility.Gone;
            _lineText.visibility = Visibility.Gone;
            _showNormalsCheck.visibility = Visibility.Gone;
        }
    }
}

private string modelPathFromArgs(string[] args)
{
    foreach (arg; args)
    {
        if (arg.length == 0)
            continue;

        immutable lower = baseName(arg).toLower;
        if (lower == "modelviewer.exe" || lower == "modelviewer")
            continue;

        if (exists(arg))
            return absolutePath(arg);
        return arg;
    }

    return "";
}

private string fallbackModelPath()
{
    immutable exeDir = thisExePath().dirName;
    string[] candidates = [
        buildPath(exeDir, "../data/cube.geo.xml"),
        buildPath(exeDir, "data/cube.geo.xml"),
        buildPath(getcwd(), "data/cube.geo.xml"),
    ];

    foreach (candidate; candidates)
    {
        if (exists(candidate))
            return absolutePath(candidate);
    }

    return absolutePath(candidates[0]);
}

private string resolveInitialModelPath(string[] args)
{
    string fromArgs = modelPathFromArgs(args);
    if (fromArgs.length > 0)
        return fromArgs;

    AppSettings settings = loadSettings();
    if (settings.lastModelPath.length > 0 && exists(settings.lastModelPath))
        return absolutePath(settings.lastModelPath);

    return fallbackModelPath();
}

/// entry point for dlangui based application
extern (C) int UIAppMain(string[] args)
{
    AppState state;
    state.modelPath = resolveInitialModelPath(args);

    Window window = Platform.instance.createWindow(
        "ModelViewer - Geo XML", null, WindowFlag.Resizable, 1280, 720);

    try
    {
        window.mainWidget = new ModelViewerWidget(window, &state);
    }
    catch (Exception ex)
    {
        writeln("Failed to initialize application: ", ex.msg);
        return 1;
    }

    window.show();
    window.update(true);
    return Platform.instance.enterMessageLoop();
}
