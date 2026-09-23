"""Makes `pytest` work from a fresh checkout without a separate editable
install: prepends src/ so `import scope_gui` resolves either way."""

import sys
from pathlib import Path

_SRC = Path(__file__).resolve().parent.parent / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))
