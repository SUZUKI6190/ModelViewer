#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

get_dub_home() {
  if [[ -n "${DUB_HOME:-}" ]]; then
    echo "${DUB_HOME}"
  else
    echo "${HOME}/.dub"
  fi
}

find_bindbc_imgui_pkg() {
  local dub_home
  dub_home="$(get_dub_home)"
  local version_root="${dub_home}/packages/bindbc-imgui"
  if [[ ! -d "${version_root}" ]]; then
    return 1
  fi

  local candidate
  for candidate in "${version_root}"/*/bindbc-imgui; do
    if [[ -f "${candidate}/dub.json" ]]; then
      echo "${candidate}"
      return 0
    fi
  done
  return 1
}

ensure_project_cimgui() {
  local project_deps="${ROOT_DIR}/deps/cimgui"
  local source_dir="${1:-}"

  if [[ -f "${project_deps}/cimgui.h" ]]; then
    return 0
  fi

  mkdir -p "${ROOT_DIR}/deps"
  rm -rf "${project_deps}"

  if [[ -n "${source_dir}" && -f "${source_dir}/cimgui.h" ]]; then
    echo "Linking deps/cimgui -> ${source_dir}"
    ln -sfn "${source_dir}" "${project_deps}"
    return 0
  fi

  echo "Cloning cimgui (tag 1.79dock) into deps/cimgui ..."
  git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git "${project_deps}"
  git -C "${project_deps}" submodule update --init --recursive
}

echo "Project root: ${ROOT_DIR}"
echo "DUB home:     $(get_dub_home)"

(
  cd "${ROOT_DIR}"
  echo "Fetching dependencies (dub fetch)..."
  dub fetch
)

IMGUI_PKG=""
if IMGUI_PKG="$(find_bindbc_imgui_pkg)"; then
  :
else
  echo "bindbc-imgui not in cache yet; running dub build to download it..."
  (cd "${ROOT_DIR}" && dub build --config=parser-test)
  IMGUI_PKG="$(find_bindbc_imgui_pkg || true)"
fi

if [[ -n "${IMGUI_PKG}" ]]; then
  echo "Found bindbc-imgui at: ${IMGUI_PKG}"
  DUB_JSON="${IMGUI_PKG}/dub.json"

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
    echo "Cloning cimgui into bindbc-imgui package..."
    git clone --depth 1 --branch 1.79dock https://github.com/Inochi2D/cimgui.git "${CIMGUI_DIR}"
    git -C "${CIMGUI_DIR}" submodule update --init --recursive
  fi

  ensure_project_cimgui "${CIMGUI_DIR}"

  BUILD_DIR="${IMGUI_PKG}/deps/build_linux_x64_cimguiStatic"
  if [[ ! -f "${IMGUI_PKG}/libs/x86_64/linux/Static/cimgui.a" ]]; then
    echo "Building static cimgui..."
    CXX="${CXX:-g++-13}" CC="${CC:-gcc-13}" \
      cmake -DSTATIC_CIMGUI= -DIMGUI_FREETYPE=no -S "${IMGUI_PKG}/deps" -B "${BUILD_DIR}"
    cmake --build "${BUILD_DIR}" --config Release
  fi
else
  echo "Warning: bindbc-imgui package directory was not found under $(get_dub_home)/packages."
  echo "Continuing with project-local deps/cimgui only."
  ensure_project_cimgui ""
fi

if [[ ! -f "${ROOT_DIR}/deps/cimgui/cimgui.h" ]]; then
  echo "Failed to prepare deps/cimgui." >&2
  exit 1
fi

echo "Setup complete. deps/cimgui is ready."
