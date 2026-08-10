#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "prompt injection" engine/aimd/prompts.py
uv run --directory engine pytest tests/test_prompts.py -q
echo "issue-36 verified"
