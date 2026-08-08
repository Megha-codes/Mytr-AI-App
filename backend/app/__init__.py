"""
Loads backend/.env into the process environment before any submodule of
`app` is imported — this must happen here, not in main.py, because
app.core.security reads JWT_SECRET at MODULE IMPORT TIME (it raises
immediately if unset), and main.py's very first import
(`.api.activity` -> `.auth` -> `..core.security`) would already be too
late if the load happened there instead.

Explicit path (not a bare load_dotenv()) so this works regardless of the
current working directory uvicorn was launched from — python-dotenv's
default search walks up from cwd, which is fragile if uvicorn is started
from the repo root instead of backend/.
"""

from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
except ImportError:
    # python-dotenv is in requirements.txt, but not every environment this
    # code runs in is guaranteed to have it installed (e.g. the test suite
    # has historically been run against a system interpreter without it) —
    # degrade to "nothing gets auto-loaded from .env" rather than crashing
    # every import of `app`. Whatever's already in the OS environment (env
    # vars set another way, or supervisor's `environment=` on the VPS)
    # still works either way.
    pass
