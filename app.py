"""openMail Flask bootstrap.

For development, run with `python app.py` or `bash dev.sh` (enables reloader).
For production/public tunnel, use `bash start.sh`.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Ensure src/ is importable when running this file directly.
SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from openmail import create_app

app = create_app()

if __name__ == "__main__":
    host = os.environ.get("FLASK_HOST", "127.0.0.1")
    port = int(os.environ.get("FLASK_PORT", "5005"))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    app.run(host=host, port=port, debug=debug, use_reloader=debug)
