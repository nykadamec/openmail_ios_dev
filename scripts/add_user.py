#!/usr/bin/env python3
"""One-off script to add a local openMail user."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Make src/ importable when running this script directly.
REPO_ROOT = Path(__file__).resolve().parent.parent
SRC = REPO_ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from openmail import create_app
from openmail.auth.users import create_user


def main() -> None:
    parser = argparse.ArgumentParser(description="Add a new openMail user.")
    parser.add_argument("username", help="Login username")
    parser.add_argument("password", help="Initial password")
    parser.add_argument("email", help="Email address (e.g. info@adamec.pro)")
    parser.add_argument("--from-name", default=None, help="Display name used in From header")
    args = parser.parse_args()

    os.chdir(REPO_ROOT)
    app = create_app()
    with app.app_context():
        user_id = create_user(args.username, args.password, email=args.email, from_name=args.from_name)
        print(f"Created user '{args.username}' ({args.email}) with id {user_id}")


if __name__ == "__main__":
    main()
