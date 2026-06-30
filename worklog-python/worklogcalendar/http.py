"""http.py - tiny async HTTP helper.

Requests run on a background thread (urllib) and the callback is dispatched
back onto the GTK main loop via GLib.idle_add, so the UI never blocks. No
external HTTP library is needed — only the Python standard library.
"""
from __future__ import annotations
import base64
import threading
import urllib.error
import urllib.request

from gi.repository import GLib


class Http:
    def send(self, method, url, auth_header, api_key, body, cb):
        """cb(status:int, body:str) is invoked on the main thread."""
        def work():
            status, text = 0, ""
            try:
                data = body.encode("utf-8") if body is not None else None
                req = urllib.request.Request(url, data=data, method=method)
                req.add_header("Accept", "application/json")
                if auth_header:
                    req.add_header("Authorization", auth_header)
                if api_key:
                    req.add_header("X-Api-Key", api_key)
                if body is not None:
                    req.add_header("Content-Type", "application/json")
                try:
                    with urllib.request.urlopen(req, timeout=45) as resp:
                        status = resp.status
                        text = resp.read().decode("utf-8", "replace")
                except urllib.error.HTTPError as e:
                    status = e.code
                    try:
                        text = e.read().decode("utf-8", "replace")
                    except Exception:
                        text = ""
            except Exception as e:  # noqa: BLE001 - surface any network error
                status, text = 0, str(e)
            GLib.idle_add(cb, status, text)

        threading.Thread(target=work, daemon=True).start()

    @staticmethod
    def basic_auth(email: str, token: str) -> str:
        raw = f"{email}:{token}".encode("utf-8")
        return "Basic " + base64.b64encode(raw).decode("ascii")
