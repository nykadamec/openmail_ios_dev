"""Settings-related API routes."""
from __future__ import annotations

from flask import Blueprint

bp = Blueprint('settings', __name__, url_prefix='/api')

# Currently password change lives in auth.py; this module is reserved for future
# settings endpoints (e.g. display name, theme, notifications).
