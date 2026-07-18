"""openMail Flask application factory."""
from __future__ import annotations

import os
import sys
from datetime import timedelta
from pathlib import Path

# Ensure src/ is on path when running app.py directly.
SRC = Path(__file__).resolve().parent.parent
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from flask import Flask, request

from openmail import config
from openmail.db import init_db, close_db
from openmail.i18n_context import register_context_processor


REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def create_app() -> Flask:
    app = Flask(
        __name__,
        template_folder=str(REPO_ROOT / "templates"),
        static_folder=str(REPO_ROOT / "static"),
    )
    app.config['SECRET_KEY'] = config.SECRET_KEY
    app.config['SESSION_COOKIE_HTTPONLY'] = True
    app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
    app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(minutes=15)

    register_context_processor(app)

    if config.RESEND_API_KEY:
        import resend
        resend.api_key = config.RESEND_API_KEY

    # Register teardown
    app.teardown_appcontext(close_db)

    # Disable caching for static JS/CSS during development
    @app.after_request
    def disable_static_cache(response):
        if request.path.startswith('/static/'):
            response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
            response.headers['Pragma'] = 'no-cache'
            response.headers['Expires'] = '0'
        return response

    # Initialize database + migrations
    with app.app_context():
        init_db()

    # Register blueprints
    from openmail.routes import public, auth, emails, contacts, folders, settings
    app.register_blueprint(public.bp)
    app.register_blueprint(auth.bp)
    app.register_blueprint(emails.bp)
    app.register_blueprint(contacts.bp)
    app.register_blueprint(folders.bp)
    app.register_blueprint(settings.bp)

    return app
