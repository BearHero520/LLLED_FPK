#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
python3 "$ROOT/tests/test_preview_web.py"
