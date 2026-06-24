# AGENTS.md

ModelViewer is a D-language desktop application that renders custom `geo.xml` 3D models
using GLFW + OpenGL 3.3 + ImGui. See `README.md` (Japanese) for feature and architecture
details.

## Cursor Cloud specific instructions

### Toolchain / how commands resolve
- The compiler is **LDC 1.42** installed under `~/dlang/ldc-1.42.0` (via the official
  dlang installer). It is activated automatically in interactive shells through `~/.bashrc`.
  In a non-interactive shell, run `source ~/dlang/ldc-1.42.0/activate` first so that `dub`
  and `ldc2` are on `PATH`.
- The bindbc-imgui / cimgui native dependency is prepared by `scripts/setup-bindbc-imgui.sh`
  (fetches `bindbc-imgui@0.7.0`, clones cimgui `1.79dock`, builds a static `cimgui.a`).
  It is idempotent and is run by the startup update script.

### Non-obvious build caveat
- The `application` dub config compiles `source/c/imgui_helper.cpp` with `-Ideps/cimgui`
  and lists `deps/cimgui` as an import path, but **nothing in the repo creates
  `deps/cimgui`** (it is git-ignored). The startup update script symlinks it to the cimgui
  sources inside the fetched bindbc-imgui package:
  `deps/cimgui -> ~/.dub/packages/bindbc-imgui/0.7.0/bindbc-imgui/deps/cimgui`.
  If `dub build --config=application` fails with `fatal error: cimgui.h: No such file or
  directory`, that symlink is missing — recreate it (or re-run the update script).

### Build / test / lint / run
- Parser-only test (no window, conclusive): `dub run --config=parser-test`
  (prints `name=Cube / vertices=14 / triangles=12` for `data/cube.geo.xml`).
- Build the GUI app: `dub build --config=application` (binary at `bin/modelviewer`).
- Run the GUI app: `./bin/modelviewer data/cube.geo.xml` (defaults to `data/cube.geo.xml`).
- Lint: `dub lint` (dscanner). Currently emits pre-existing "undocumented declaration"
  style warnings and exits non-zero; treat as advisory.

### Running the GUI under the headless desktop (important limitation)
- A virtual desktop is available on `DISPLAY=:1`; launch the app with `DISPLAY=:1
  ./bin/modelviewer ...`. The app builds and launches fine and loads/uploads the model
  without errors.
- GL rendering uses **software rendering (Mesa llvmpipe)**, which is unstable here: the GL
  window flickers between the rendered frame and the cleared buffer, the model appears very
  small, and the ImGui control panel is often not visible. `ffmpeg -f x11grab` of the root
  window captures only blank frames because the GLX surface is not composited into the root
  window — use the desktop screenshot tooling (computer-use) instead to see actual frames.
  These are software-GL/headless limitations, not application bugs; visual rendering is
  expected to be correct on real GPU hardware.
