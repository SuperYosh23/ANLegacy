#!/usr/bin/env python3
"""Produce the modern arm64-only .ipa used for sideloading on new iPhones.

Takes the .deb produced by `make package` and turns it into an .ipa whose
Mach-O reports a modern SDK version and which carries a compiled
LaunchScreen storyboard.

iOS reads the Mach-O SDK version (LC_BUILD_VERSION) to decide whether to put
an app in letterboxing ("compatibility") mode on notched devices. Updating
Info.plist alone is not enough; the binary's reported SDK version must be
modern, and a launch storyboard tells iOS the app supports every screen size.
This script applies both, thins the binary to arm64, and strips the signature
so the sideloading tool can re-sign it.

The binary is given a real LC_BUILD_VERSION (platform IOS, minos 11.0,
sdk 14.0) rather than a legacy LC_VERSION_MIN_IPHONEOS, matching how a
current build looks to iOS while staying below the iOS 26 SDK that triggers
Liquid Glass.

Usage:
    ./make_modern_ipa.py [input.deb] [-o output.ipa]
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
VTOOL = TOOLCHAIN / "vtool"
STORYBOARD = HERE / "ipa_extras" / "LaunchScreen.storyboardc"
EXECUTABLE = "LegacyMusic"

# arm64 deployment target: must stay compatible with iOS 11 and newer.
MIN_OS = "11.0"
# SDK reported in the Mach-O (LC_BUILD_VERSION) and Info.plist. Kept at the
# iOS 14 SDK so iOS 26+ does not apply the Liquid Glass redesign, which breaks
# this app's hand-built UI. (Reporting a >= 26 SDK turned Liquid Glass on.)
SDK_VERSION = "14.0"
# LC_BUILD_VERSION platform id: 2 == iOS.
BUILD_PLATFORM = "2"


def run(cmd: list) -> None:
    print("  -> " + " ".join(str(c) for c in cmd))
    subprocess.run([str(c) for c in cmd], check=True)


def default_deb() -> Path:
    pkgs = sorted((HERE / "packages").glob("*.deb"), key=lambda p: p.stat().st_mtime)
    if not pkgs:
        raise SystemExit("No .deb found in packages/; run `make package` first.")
    return pkgs[-1]


def ipa_name(deb: Path) -> str:
    # com.legacymusic.app_9.5-13+debug_iphoneos-arm.deb -> LegacyMusic-9.5-13.ipa
    stem = deb.stem
    if "_" in stem:
        stem = stem.split("_", 1)[1]
    version = stem.split("+", 1)[0]
    return f"LegacyMusic-{version}.ipa"


def build_modern_ipa(deb: Path, out: Path) -> Path:
    """Turn the arm64 slice of `deb` into the modern sideload .ipa at `out`."""
    deb = Path(deb).resolve()
    if not deb.is_file():
        raise SystemExit(f"Input .deb not found: {deb}")
    for tool in (LIPO, VTOOL):
        if not tool.exists():
            raise SystemExit(f"Missing tool: {tool}")
    if not STORYBOARD.is_dir():
        raise SystemExit(f"Missing launch storyboard: {STORYBOARD}")

    out = Path(out).resolve()
    with tempfile.TemporaryDirectory(prefix="modern_ipa_") as tmp:
        tmpdir = Path(tmp)

        # Reuse the tested deb -> ipa conversion, then modify the payload.
        base = tmpdir / "base.ipa"
        deb_to_ipa.convert_deb_to_ipa(str(deb), str(base))

        work = tmpdir / "work"
        work.mkdir()
        with zipfile.ZipFile(base) as zf:
            zf.extractall(work)

        app = next(work.glob("Payload/*.app"))
        print(f"[modern] Patching {app.name}")

        # 1. Thin to arm64 and bump the Mach-O SDK version.
        exe = app / EXECUTABLE
        thinned = app / (EXECUTABLE + ".thin")
        bumped = app / (EXECUTABLE + ".bumped")
        run([LIPO, exe, "-thin", "arm64", "-output", thinned])
        run([VTOOL, "-set-build-version", BUILD_PLATFORM, MIN_OS, SDK_VERSION,
             "-replace", "-output", bumped, thinned])
        thinned.unlink(missing_ok=True)
        bumped.replace(exe)
        exe.chmod(0o755)

        # 2. Add the compiled launch storyboard.
        dest = app / STORYBOARD.name
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(STORYBOARD, dest)

        # 3. Patch Info.plist.
        plist_path = app / "Info.plist"
        with plist_path.open("rb") as fh:
            info = plistlib.load(fh)
        info["UILaunchStoryboardName"] = "LaunchScreen"
        info["MinimumOSVersion"] = MIN_OS
        info["DTSDKName"] = f"iphoneos{SDK_VERSION}"
        info["DTPlatformVersion"] = SDK_VERSION
        info["UIRequiredDeviceCapabilities"] = ["arm64"]
        with plist_path.open("wb") as fh:
            plistlib.dump(info, fh, fmt=plistlib.FMT_BINARY)

        # 4. Strip any code signature; the sideloader re-signs the app.
        shutil.rmtree(app / "_CodeSignature", ignore_errors=True)
        (app / "embedded.mobileprovision").unlink(missing_ok=True)

        # 5. Repack.
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
    out = Path(args.output) if args.output else HERE / ipa_name(deb)
    build_modern_ipa(deb, out)
    print(f"\nDone: {out}")


if __name__ == "__main__":
    main()
