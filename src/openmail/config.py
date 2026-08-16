"""Application configuration loaded from environment."""
from __future__ import annotations

import os
import secrets
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.environ.get('SECRET_KEY', secrets.token_hex(32))

DB_PATH = Path("emails.db")
DATA_DIR = Path("data")
ATTACHMENTS_DIR = DATA_DIR / "attachments"

RESEND_API_KEY = os.environ.get("RESEND_API_KEY")
RESEND_DOMAIN = os.environ.get("RESEND_DOMAIN", "adamec.pro")
RESEND_WEBHOOK_SECRET = os.environ.get("RESEND_WEBHOOK_SECRET")
FROM_EMAIL = os.environ.get("FROM_EMAIL", f"dominik@{RESEND_DOMAIN}")
FROM_NAME = os.environ.get("FROM_NAME", "Dominik Adamec")

CF_ACCESS_ENABLED = os.environ.get('CLOUDFLARE_ACCESS_ENABLED', 'false').lower() == 'true'
CF_TEAM_DOMAIN = os.environ.get('CLOUDFLARE_TEAM_DOMAIN', '')
CF_AUD_TAG = os.environ.get('CLOUDFLARE_AUD_TAG', '')

DEFAULT_USER_PASSWORD = os.environ.get("DEFAULT_USER_PASSWORD", "adamec")
FLASK_HOST = os.environ.get("FLASK_HOST", "127.0.0.1")
FLASK_PORT = int(os.environ.get("FLASK_PORT", "5005"))

PBKDF2_ITERATIONS = 100_000
PBKDF2_ITERATIONS_LEGACY = 600_000

SESSION_TIMEOUT_MINUTES = 15
REMEMBER_ME_DAYS = int(os.environ.get("REMEMBER_ME_DAYS", "30"))
REMEMBER_USERNAME_DAYS = int(os.environ.get("REMEMBER_USERNAME_DAYS", "365"))

FLASK_DEBUG = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
