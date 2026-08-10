#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -euo pipefail

uv run --directory engine pytest tests/test_prompts.py -q
echo "issue-32 verified"
