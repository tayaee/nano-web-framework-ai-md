#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "sys.modules\[module_name\] = module" engine/aimd/validators.py
uv run --directory engine pytest tests/test_validators.py -q
echo "issue-52 verified"
