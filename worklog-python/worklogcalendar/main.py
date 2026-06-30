"""main.py - entry point."""
from __future__ import annotations
import sys

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")


def main(argv=None):
    from .application import WorklogApp
    app = WorklogApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
