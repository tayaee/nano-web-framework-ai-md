#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

grep -q "message_lower = message.lower()" engine/aimd/llm.py
uv run --directory engine pytest tests/test_llm.py -q
echo "issue-39 verified"
