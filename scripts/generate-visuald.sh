#!/usr/bin/env bash
# Generate Visual Studio / VisualD solution from dub.json (Linux/macOS host).
set -euo pipefail

CONFIG="${1:-application}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo "Project root: ${ROOT_DIR}"
echo "Configuration: ${CONFIG}"

if [[ ! -f "${ROOT_DIR}/deps/cimgui/cimgui.h" ]]; then
  echo "deps/cimgui not found. Running setup..."
  bash "${SCRIPT_DIR}/setup-bindbc-imgui.sh"
fi

if [[ "${CONFIG}" == "application" ]]; then
  echo "Compiling imgui_helper.cpp..."
  g++-13 -c -Ideps/cimgui -o source/c/imgui_helper.o source/c/imgui_helper.cpp
fi

echo "Fetching dub dependencies..."
dub fetch

if [[ "${CONFIG}" == "application" ]]; then
  echo "Pre-building via dub..."
  dub build --config=application
fi

echo "Generating VisualD project files..."
dub generate visuald --config="${CONFIG}"

cat <<EOF

Generated:
  modelviewer.sln
  .dub/*.visualdproj

Open modelviewer.sln in Visual Studio with VisualD installed (Windows).
On Linux this generates project files for cross-editing; build with dub on Windows.

Notes:
  - Prefer 'dub build --config=${CONFIG}' for reliable builds.
  - Re-run this script after dub.json changes.
EOF
