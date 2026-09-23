#!/usr/bin/env python3
"""Produce the legacy 32-bit (armv7-only) .ipa for old iOS devices.

This is the counterpart to make_modern_ipa.py. It takes the same .deb and
keeps only the 32-bit armv7 slice, which runs on iOS 6 through 10.

Unlike the modern build it deliberately does NOT touch the Mach-O load
commands: the armv7 slice already reports minos 6.0 / sdk 9.3, which is
exactly right for these devices. No launch storyboard is added either, since
letterboxing is a notched-device concern and a modern storyboard would only
risk breaking on iOS 6.

The binary keeps the ad-hoc signature Theos gave it, so it also works on
jailbroken devices via ipainstaller/AppSync, while sideloading tools are free
to re-sign it.

Usage:
    ./make_legacy_ipa.py [input.deb] [-o output.ipa]
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import deb_to_ipa  # noqa: E402

TOOLCHAIN = Path("/home/superyosh23/theos/toolchain/linux/iphone/bin")
LIPO = TOOLCHAIN / "lipo"
EXECUTABLE = "LegacyMusic"

# armv7 deployment target and the SDK it was actually built against.
MIN_OS = "6.0"
SDK_VERSION = "9.3"


def run(cmd: list) -> None:
    print("  -> " + " ".join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True)


def default_deb() -> Path:
    pkgs = sorted((HERE / "packages").glob("*.deb"), key=lambda p: p.stat().st_mtime)
    if not pkgs:
        raise SystemExit("No .deb found in packages/; run `make package` first.")
    return pkgs[-1]


def legacy_ipa_name(deb: Path) -> str:
    # com.legacymusic.app_10-9+debug_iphoneos-arm.deb -> LegacyMusic-10-9-legacy.ipa
    stem = deb.stem
    if "_" in stem:
        stem = stem.split("_", 1)[1]
    version = stem.split("+", 1)[0]
    return f"LegacyMusic-{version}-legacy.ipa"


def build_legacy_ipa(deb: Path, out: Path) -> Path:
    """Turn the armv7 slice of `deb` into the legacy sideload .ipa at `out`."""
    deb = Path(deb).resolve()
    if not deb.is_file():
        raise SystemExit(f"Input .deb not found: {deb}")
    if not LIPO.exists():
        raise SystemExit(f"Missing tool: {LIPO}")

    out = Path(out).resolve()
    with tempfile.TemporaryDirectory(prefix="legacy_ipa_") as tmp:
        tmpdir = Path(tmp)

        base = tmpdir / "base.ipa"
        deb_to_ipa.convert_deb_to_ipa(str(deb), str(base))

        work = tmpdir / "work"
        work.mkdir()
        with zipfile.ZipFile(base) as zf:
            zf.extractall(work)

        app = next(work.glob("Payload/*.app"))
        print(f"[legacy] Patching {app.name}")

        # 1. Keep only the 32-bit slice. The load commands are already correct,
        #    and lipo carries the existing signature over to the thin binary.
        exe = app / EXECUTABLE
        thinned = app / (EXECUTABLE + ".thin")
        run([LIPO, exe, "-thin", "armv7", "-output", thinned])
        thinned.replace(exe)
        exe.chmod(0o755)

        # 2. Patch Info.plist for a 32-bit, non-notched device.
        plist_path = app / "Info.plist"
        with plist_path.open("rb") as fh:
            info = plistlib.load(fh)
        info["MinimumOSVersion"] = MIN_OS
        info["DTSDKName"] = f"iphoneos{SDK_VERSION}"
        info["DTPlatformVersion"] = SDK_VERSION
        info["UIRequiredDeviceCapabilities"] = ["armv7"]
        info.pop("UILaunchStoryboardName", None)
        with plist_path.open("wb") as fh:
            plistlib.dump(info, fh, fmt=plistlib.FMT_BINARY)

        # 3. Drop any bundle signature leftovers; the sideloader re-signs.
        shutil.rmtree(app / "_CodeSignature", ignore_errors=True)
        (app / "embedded.mobileprovision").unlink(missing_ok=True)

        # 4. Repack.
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(work.rglob("*")):
                zf.write(path, path.relative_to(work))

    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deb", nargs="?", help="input .deb (default: newest in packages/)")
    parser.add_argument("-o", "--output", help="output .ipa path")
    args = parser.parse_args()

    deb = Path(args.deb) if args.deb else default_deb()
    out = Path(args.output) if args.output else HERE / legacy_ipa_name(deb)
    build_legacy_ipa(deb, out)
    print(f"\nDone: {out}")


if __name__ == "__main__":
    main()
