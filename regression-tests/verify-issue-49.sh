#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q 'sub_scope\["raw_path"\]' engine/aimd/main.py
uv run --directory engine pytest tests/test_main.py -k test_py_subapp_receives_correct_scope -q
echo "issue-49 verified"
