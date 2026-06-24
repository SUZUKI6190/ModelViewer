#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMGUI_PKG="${HOME}/.dub/packages/bindbc-imgui/0.7.0/bindbc-imgui"
DUB_JSON="${IMGUI_PKG}/dub.json"

if [[ ! -d "${IMGUI_PKG}" ]]; then
  echo "Fetching bindbc-imgui..."
  dub fetch bindbc-imgui@0.7.0
fi

if ! grep -q '"bindbc-glfw"' "${DUB_JSON}"; then
  echo "Patching bindbc-imgui to depend on bindbc-glfw..."
  sed -i 's/"bindbc-sdl": "~>0.21.4"/"bindbc-sdl": "~>0.21.4",\n\t\t"bindbc-glfw": "~>0.13.0"/' "${DUB_JSON}"
fi

STDCXX_A="/usr/lib/gcc/x86_64-linux-gnu/13/libstdc++.a"
if [[ -f "${STDCXX_A}" && ! -e /usr/lib/libstdc++.a ]]; then
  echo "Linking libstdc++.a into /usr/lib for bindbc-imgui static builds..."
  sudo ln -sf "${STDCXX_A}" /usr/lib/libstdc++.a
fi

CIMGUI_DIR="${IMGUI_PKG}/deps/cimgui"
if [[ ! -f "${CIMGUI_DIR}/CMakeLists.txt" ]]; then
  echo "Cloning cimgui sources (tag 1.79dock)..."
  git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git "${CIMGUI_DIR}"
  git -C "${CIMGUI_DIR}" submodule update --init --recursive
fi

BUILD_DIR="${IMGUI_PKG}/deps/build_linux_x64_cimguiStatic"
if [[ ! -f "${IMGUI_PKG}/libs/x86_64/linux/Static/cimgui.a" ]]; then
  echo "Building static cimgui..."
  CXX="${CXX:-g++-13}" CC="${CC:-gcc-13}" \
    cmake -DSTATIC_CIMGUI= -DIMGUI_FREETYPE=no -S "${IMGUI_PKG}/deps" -B "${BUILD_DIR}"
  cmake --build "${BUILD_DIR}" --config Release
fi

echo "bindbc-imgui dependencies are ready."
