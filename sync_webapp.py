#!/usr/bin/env python3
"""Build the phone's web app and copy it into the app's resources.

The modern themes are a web app served from inside the phone by LTWebServer.
Its source lives in this repository, under webapp/, rather than in the desktop
app's checkout: the phone must not depend on another repository being present,
and the desktop app must not be modified to suit it.

The build has two stages, both of which exist because the phone runs iOS 9:

  * Tailwind 3, not Tailwind 4. Tailwind 4's CSS is built on @layer for the
    cascade and color-mix()/oklch() for colours; Safari learned @layer in 15.4
    and color-mix in 16.2, so on the phone 85% of the stylesheet was dropped
    and the page rendered unstyled.
  * One classic script, not an ES module. iOS 9's WebKit has no module
    support at all, and Safari only gained it in 10.3. scripts/legacy-bundle.mjs
    does that lowering.

The built bundle is committed under Resources/webapp, so building the app never
needs node. This script refreshes it.

    python3 sync_webapp.py            # build and copy
    python3 sync_webapp.py --no-build # copy the committed bundle only
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WEBAPP = HERE / "webapp"
DEST = HERE / "Resources" / "webapp"


def ensure_dependencies() -> bool:
    """Make sure the web app's dependencies are installed."""
    if (WEBAPP / "node_modules").is_dir():
        return True
    if not shutil.which("npm"):
        print("npm not on PATH; cannot build the web app")
        return False
    print("==> installing the web app's dependencies")
    result = subprocess.run(
        ["npm", "install", "--no-audit", "--no-fund"],
        cwd=str(WEBAPP), capture_output=True, text=True, timeout=900,
    )
    if result.returncode != 0:
        print(result.stdout[-1500:])
        print(result.stderr[-1500:])
        return False
    return True


def run_build() -> bool:
    if not ensure_dependencies():
        return False
    print("==> building the web app")
    result = subprocess.run(
        ["npm", "run", "build"],
        cwd=str(WEBAPP), capture_output=True, text=True, timeout=1200,
    )
    output = (result.stdout or "") + (result.stderr or "")
    for line in output.splitlines():
        if "lowered bundle" in line or "error" in line.lower() or "Error" in line:
            print("   " + line)
    if result.returncode != 0:
        print(output[-2500:])
        return False
    return True


def copy_dist() -> bool:
    dist = WEBAPP / "dist"
    if not (dist / "index.html").is_file():
        print(f"no build output at {dist}")
        return False
    if DEST.exists():
        shutil.rmtree(DEST)
    shutil.copytree(dist, DEST)
    size = sum(f.stat().st_size for f in DEST.rglob("*") if f.is_file())
    print(f"copied web app -> {DEST} ({size // 1024} KB)")
    return True


def prune_unreferenced() -> None:
    """Delete bundle files the page does not reference.

    The build produces an intermediate Vite bundle and then a lowered one, and
    only the lowered one is referenced by index.html. The intermediate is a
    couple of hundred kilobytes of source that would otherwise ship in every
    copy of the app.
    """
    index = DEST / "index.html"
    if not index.is_file():
        return
    html = index.read_text()
    assets = DEST / "assets"
    if not assets.is_dir():
        return
    removed = 0
    for path in assets.glob("*.js"):
        if path.name in html:
            continue
        path.unlink()
        removed += 1
    if removed:
        print(f"removed {removed} unreferenced bundle file(s)")


def fix_script_tag() -> None:
    """Make sure the bundle's script tag is a classic, deferred one.

    A module script is ignored outright by iOS 9. And it must be deferred: Vite
    puts the script in the document head, which is safe for a module because
    modules are deferred by default, but a classic script is not - it would run
    before the body was parsed and React would find no #root to mount into.
    """
    index = DEST / "index.html"
    if not index.is_file():
        return
    text = index.read_text()
    before = text
    text = text.replace('<script type="module" crossorigin defer ',
                        '<script defer ')
    text = text.replace('<script type="module" defer ', '<script defer ')
    text = text.replace('<script type="module" crossorigin ', '<script defer ')
    text = text.replace('<script type="module" ', '<script defer ')
    text = text.replace(' crossorigin src="./assets/', ' defer src="./assets/')
    if text != before:
        index.write_text(text)
        print("rewrote the bundle's script tag as a classic deferred script")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true",
                        help="skip the build, copy the committed bundle only")
    args = parser.parse_args()

    if not args.no_build:
        run_build()
    copy_dist()
    prune_unreferenced()
    fix_script_tag()

    if not (DEST / "index.html").is_file():
        print("FAIL: no web app bundle in Resources/webapp")
        return 1
    print("web app bundle OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
