"""
i18n module for openMail.

Simple JSON-based localization with:
- File-based locale storage (locales/{lang}.json)
- In-memory cache with reload on file change
- Key-based lookup with {kwargs} interpolation
- Fallback to "??key??" for missing keys
"""

import json
import os
import threading
from pathlib import Path
from typing import Optional

_LOCALES_DIR = Path(__file__).resolve().parent.parent.parent / "locales"
_DEFAULT_LOCALE = "cs"

_cache: dict[str, dict[str, str]] = {}
_cache_lock = threading.Lock()
_current_locale: str = _DEFAULT_LOCALE


def _load_locale(lang: str) -> dict[str, str]:
    """Load a locale file from disk. Returns {} on failure."""
    path = _LOCALES_DIR / f"{lang}.json"
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def _get_data(lang: str) -> dict[str, str]:
    """Get locale data, with cache."""
    with _cache_lock:
        if lang not in _cache:
            _cache[lang] = _load_locale(lang)
        return _cache[lang]


def _clear_cache(lang: Optional[str] = None):
    """Clear cache for one or all locales."""
    with _cache_lock:
        if lang:
            _cache.pop(lang, None)
        else:
            _cache.clear()


def get_locale() -> str:
    """Return the current locale code (e.g. 'cs', 'en')."""
    return _current_locale


def set_locale(lang: str):
    """Set the current locale. Falls back to 'cs' if the locale file doesn't exist."""
    global _current_locale
    if lang in ("cs", "en"):
        _current_locale = lang
    else:
        _current_locale = _DEFAULT_LOCALE


def t(key: str, **kwargs) -> str:
    """
    Translate a key using the current locale.

    Supports {placeholder} interpolation via kwargs.
    Falls back to "??key??" if the key is missing.
    """
    data = _get_data(_current_locale)
    value = data.get(key)
    if value is None:
        # Try fallback to cs
        if _current_locale != "cs":
            cs_data = _get_data("cs")
            value = cs_data.get(key)
        if value is None:
            return f"??{key}??"
    if kwargs:
        try:
            return value.format(**kwargs)
        except KeyError:
            return value
    return value


def _load():
    """Reload all locale data from disk."""
    _clear_cache()


def get_all_keys() -> dict[str, str]:
    """Return all keys for the current locale (useful for JS injection)."""
    return dict(_get_data(_current_locale))
