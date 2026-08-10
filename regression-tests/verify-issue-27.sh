#!/usr/bin/env bash
set -euo pipefail

grep -q "cannot load spec from" engine/aimd/validators.py
uv run --directory engine pytest tests/ -k load_module
echo "issue-27 verified"
