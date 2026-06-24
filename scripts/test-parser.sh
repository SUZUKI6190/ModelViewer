#!/usr/bin/env bash
# Quick validation of Geo XML parsing without opening a window.
set -euo pipefail
source ~/dlang/ldc-1.42.0/activate
cd "$(dirname "$0")/.."
dub run --config=parser-test 2>&1
