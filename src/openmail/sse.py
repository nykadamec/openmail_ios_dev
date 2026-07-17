"""Thread-safe Server-Sent Events client registry and notifier."""
from __future__ import annotations

import json
import queue
import threading
from typing import Any

from flask import Response, stream_with_context


_clients: list[queue.Queue] = []
_lock = threading.RLock()


def register() -> queue.Queue:
    q: queue.Queue = queue.Queue(maxsize=100)
    with _lock:
        _clients.append(q)
    return q


def unregister(q: queue.Queue) -> None:
    with _lock:
        try:
            _clients.remove(q)
        except ValueError:
            pass


def notify(event: str, data: dict) -> None:
    """Push event to all connected SSE clients."""
    with _lock:
        snapshot = list(_clients)
    payload = json.dumps(data)
    dead: list[queue.Queue] = []
    for q in snapshot:
        try:
            q.put_nowait((event, payload))
        except queue.Full:
            dead.append(q)
        except Exception:
            dead.append(q)
    if dead:
        with _lock:
            for q in dead:
                try:
                    _clients.remove(q)
                except ValueError:
                    pass


def stream() -> Response:
    q = register()

    def generate():
        try:
            yield "event: connected\ndata: {}\n\n"
            while True:
                try:
                    event, data = q.get(timeout=15)
                    yield f"event: {event}\ndata: {data}\n\n"
                except queue.Empty:
                    yield ": keepalive\n\n"
        except GeneratorExit:
            pass
        finally:
            unregister(q)

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
