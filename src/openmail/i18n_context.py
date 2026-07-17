"""i18n context processor registration."""
from __future__ import annotations

from flask import Flask

from openmail.i18n import t, get_locale, _load, get_all_keys


def inject_locale() -> dict:
    return {
        't': t,
        '_': t,
        'locale': get_locale(),
        'locale_json': get_all_keys(),
    }


def register_context_processor(app: Flask) -> None:
    app.context_processor(inject_locale)
