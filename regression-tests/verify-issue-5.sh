#!/bin/bash
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
set -e

# 1. Check that the files exist
if [ ! -f "engine/aimd/prompts.py" ]; then
    echo "engine/aimd/prompts.py does not exist"
    exit 1
fi

if [ ! -f "engine/tests/test_prompts.py" ]; then
    echo "engine/tests/test_prompts.py does not exist"
    exit 1
fi

# 2. Check required constant definitions
if ! grep -q "^CLASSIFY_SYSTEM" "engine/aimd/prompts.py"; then echo "CLASSIFY_SYSTEM constant missing"; exit 1; fi
if ! grep -q "^SPA_SYSTEM" "engine/aimd/prompts.py"; then echo "SPA_SYSTEM constant missing"; exit 1; fi
if ! grep -q "^API_SYSTEM" "engine/aimd/prompts.py"; then echo "API_SYSTEM constant missing"; exit 1; fi
if ! grep -q "^FIX_TEMPLATE" "engine/aimd/prompts.py"; then echo "FIX_TEMPLATE constant missing"; exit 1; fi

# 3. Verify no functions/classes are included (file must contain only the 4 constants)
if grep -qE "^[[:space:]]*(def |async def |class )" "engine/aimd/prompts.py"; then
    echo "prompts.py must contain constants only, no functions/classes"
    exit 1
fi

# 4. Run tests
cd engine
if command -v uv >/dev/null 2>&1; then
    uv run pytest tests/test_prompts.py -q
else
    python -m pytest tests/test_prompts.py -q
fi
