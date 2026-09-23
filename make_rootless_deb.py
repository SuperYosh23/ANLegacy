#!/usr/bin/env python3
"""Produce the rootless .deb for modern jailbreaks (iOS 15+).

Rootless jailbreaks (Dopamine, palera1n -l, etc.) install everything under a
virtual prefix, /var/jb, and expect packages to declare
`Architecture: iphoneos-arm64`.

The app payload is taken from the modern .ipa rather than rebuilt, so the
jailbroken install is byte-for-byte the same app that gets sideloaded: arm64,
sdk 14.0, with the launch storyboard that stops it letterboxing on notched
devices. The only differences are the ad-hoc signature (added here with ldid)
and the install location.

The .deb is assembled with Theos' own dm.pl so the output matches what
`make package` produces for the rootful build.

Usage:
    ./make_rootless_deb.py [input.ipa] -v VERSION [-o output.deb]
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

TOOLCHAIN = Path("/home/superyosh23/theos/toolchain/linux/iphone/bin")
LDID = TOOLCHAIN / "ldid"
THEOS_BIN = Path("/home/superyosh23/theos/bin")
DM_PL = THEOS_BIN / "dm.pl"
FAKEROOT_SH = THEOS_BIN / "fakeroot.sh"

EXECUTABLE = "LegacyMusic"
BUNDLE_NAME = "LegacyMusic.app"
INSTALL_DIR = "var/jb/Applications"
# The rootless build is published as its own app listing in the repo, so it
# needs its own package identifier (the app's CFBundleIdentifier stays the
# same, so it is still "the same app" to the user).
PACKAGE = "com.legacymusic.app.rootless"
PACKAGE_NAME = "audioNINJA Legacy (Rootless)"
DESCRIPTION = "YouTube Music client for legacy iOS devices (rootless jailbreaks, iOS 15+)"
MAINTAINER = "superyosh23"
AUTHOR = "superyosh23"
SECTION = "Multimedia"

POSTINST = """#!/bin/sh
# Register the app with the system so it shows up on the home screen.
if [ -x /var/jb/usr/bin/uicache ]; then
    /var/jb/usr/bin/uicache -p /var/jb/Applications/LegacyMusic.app >/dev/null 2>&1 || true
elif [ -x /usr/bin/uicache ]; then
    /usr/bin/uicache >/dev/null 2>&1 || true
fi
exit 0
"""


def run(cmd: list) -> None:
    print("  -> " + " ".join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True)


def default_ipa() -> Path:
    ipas = [p for p in (HERE).glob("LegacyMusic-*.ipa") if not p.name.endswith("-legacy.ipa")]
    if not ipas:
        raise SystemExit("No modern .ipa found; run make_modern_ipa.py first.")
    return max(ipas, key=lambda p: p.stat().st_mtime)


def is_macho(path: Path) -> bool:
    try:
        magic = path.open("rb").read(4)
    except OSError:
        return False
    if len(magic) < 4:
        return False
    return magic in (
        b"\xcf\xfa\xed\xfe",  # MH_MAGIC_64 (little endian)
        b"\xce\xfa\xed\xfe",  # MH_MAGIC (little endian)
        b"\xfe\xed\xfa\xcf",  # MH_MAGIC_64 (big endian)
        b"\xfe\xed\xfa\xce",  # MH_MAGIC (big endian)
        b"\xca\xfe\xba\xbe",  # FAT_MAGIC
        b"\xbe\xba\xfe\xca",  # FAT_CIGAM
    )


def sign_bundle(app: Path) -> None:
    """Ad-hoc sign every Mach-O in the bundle, main executable last.

    zipfile.extractall() does not restore permission bits, so make sure every
    Mach-O is executable before signing it -- an unrunnable (644) app binary
    is an easy mistake to ship.
    """
    targets = [p for p in app.rglob("*") if p.is_file() and is_macho(p)]
    exe = app / EXECUTABLE
    targets.sort(key=lambda p: p == exe)  # main binary last
    for target in targets:
        target.chmod(0o755)
        run([LDID, "-S", target])


def write_control(stage: Path, version: str) -> None:
    installed_size = subprocess.run(
        ["du", "-ks", str(stage)], capture_output=True, text=True, check=True
    ).stdout.split()[0]
    control = (
        f"Package: {PACKAGE}\n"
        f"Name: {PACKAGE_NAME}\n"
        f"Version: {version}\n"
        f"Architecture: iphoneos-arm64\n"
        f"Description: {DESCRIPTION}\n"
        f"Maintainer: {MAINTAINER}\n"
        f"Author: {AUTHOR}\n"
        f"Section: {SECTION}\n"
        f"Installed-Size: {installed_size}\n"
    )
    (stage / "DEBIAN" / "control").write_text(control)


def build_rootless_deb(ipa: Path, out: Path, version: str) -> Path:
    """Repack the modern `ipa` payload as a /var/jb rootless .deb at `out`."""
    ipa = Path(ipa).resolve()
    if not ipa.is_file():
        raise SystemExit(f"Input .ipa not found: {ipa}")
    for tool in (LDID, DM_PL, FAKEROOT_SH):
        if not tool.exists():
            raise SystemExit(f"Missing tool: {tool}")

    out = Path(out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="rootless_deb_") as tmp:
        tmpdir = Path(tmp)

        # 1. Unpack the IPA payload.
        work = tmpdir / "work"
        work.mkdir()
        with zipfile.ZipFile(ipa) as zf:
            zf.extractall(work)
        app = next(work.glob("Payload/*.app"))
        print(f"[rootless] Packaging {app.name} as {version}")

        # 2. Ad-hoc sign it (the sideload .ipa ships unsigned).
        sign_bundle(app)

        # 3. Lay out the rootless filesystem tree.
        stage = tmpdir / "stage"
        dest = stage / INSTALL_DIR / BUNDLE_NAME
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(app, dest, symlinks=True)

        (stage / "DEBIAN").mkdir(parents=True, exist_ok=True)
        postinst = stage / "DEBIAN" / "postinst"
        postinst.write_text(POSTINST)
        postinst.chmod(0o755)
        write_control(stage, version)

        # 4. Build the .deb with Theos' packer (run under its fakeroot wrapper
        #    so ownership ends up as root:root, like `make package`).
        persistence = tmpdir / "fakeroot"
        run([FAKEROOT_SH, "-p", persistence, "-r", DM_PL,
             "-Zlzma", "-z9", "-b", stage, out])

    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", nargs="?", help="input .ipa (default: newest modern IPA)")
    parser.add_argument("-v", "--version", required=True, help="package version, e.g. 10-9+debug")
    parser.add_argument("-o", "--output", help="output .deb path")
    args = parser.parse_args()

    ipa = Path(args.ipa) if args.ipa else default_ipa()
    out = Path(args.output) if args.output else (
        HERE / "packages" / f"{PACKAGE}_{args.version}_iphoneos-arm64.deb"
    )
    build_rootless_deb(ipa, out, args.version)
    print(f"\nDone: {out}")


if __name__ == "__main__":
    main()
