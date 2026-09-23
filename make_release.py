#!/usr/bin/env python3
"""Build every distributable in one go, all sharing a single version.

Produces four artifacts that between them cover every supported device:

  * rootful .deb   iphoneos-arm     armv7+arm64, iOS 6+   (Cydia/Sileo, rootful)
  * rootless .deb  iphoneos-arm64   arm64, iOS 15+        (/var/jb, Dopamine etc.)
  * modern .ipa    arm64, iOS 11+, sdk 14.0               (16e and modern sideloads)
  * legacy .ipa    armv7, iOS 6+                          (old 32-bit sideloads)

The .deb is built by Theos and defines the version (e.g. 10-9+debug); the
other three are derived from that same version so a release is always
internally consistent.

Every run also copies all four files into versions/<version>/ so each build
is kept as an immutable, self-contained snapshot.

Usage:
    ./make_release.py                 # make package, then build everything
    ./make_release.py --no-build      # reuse the newest existing rootful .deb
    ./make_release.py --deb path.deb  # use a specific rootful .deb
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import make_legacy_ipa  # noqa: E402
import make_modern_ipa  # noqa: E402
import make_rootless_deb  # noqa: E402

THEOS = Path("/home/superyosh23/theos")
PACKAGE = "com.legacymusic.app"


def newest_rootful_deb() -> Path:
    debs = sorted(
        (HERE / "packages").glob(f"{PACKAGE}_*_iphoneos-arm.deb"),
        key=lambda p: p.stat().st_mtime,
    )
    if not debs:
        raise SystemExit("No rootful .deb in packages/; run `make package` first.")
    return debs[-1]


def version_of(deb: Path) -> str:
    # com.legacymusic.app_10-9+debug_iphoneos-arm.deb -> 10-9+debug
    return deb.name.split("_", 1)[1].rsplit("_", 1)[0]


def run_make_package() -> None:
    env = os.environ.copy()
    env["THEOS"] = str(THEOS)
    env["PATH"] = f"{THEOS}/bin:" + env.get("PATH", "")
    print(f"==> make package ({THEOS})")
    subprocess.run(["make", "package"], cwd=str(HERE), env=env, check=True)


def archive(version: str, built: list) -> Path:
    """Copy every artifact into versions/<version>/ (created if needed).

    Each artifact is renamed to make its role obvious: .debs become
    -rootful/-rootless and .ipas become -64/-32 (the architecture width).
    """
    dest = HERE / "versions" / version
    dest.mkdir(parents=True, exist_ok=True)
    for _, path, _, archive_name in built:
        shutil.copy2(path, dest / archive_name)
    return dest


def human(path: Path) -> str:
    size = path.stat().st_size
    for unit in ("B", "K", "M", "G"):
        if size < 1024 or unit == "G":
            return f"{size:.0f}{unit}" if unit != "B" else f"{size}B"
        size /= 1024
    return f"{size:.1f}G"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--deb", help="rootful .deb to derive everything from")
    parser.add_argument("--no-build", action="store_true",
                        help="skip `make package`, reuse the newest rootful .deb")
    parser.add_argument("--skip-debs", action="store_true", help="only build the .ipas")
    parser.add_argument("--skip-ipas", action="store_true", help="only build the .debs")
    args = parser.parse_args()

    if args.deb:
        rootful = Path(args.deb).resolve()
    else:
        if not args.no_build:
            run_make_package()
        rootful = newest_rootful_deb()

    if not rootful.is_file():
        raise SystemExit(f"Rootful .deb not found: {rootful}")

    version = version_of(rootful)
    short = version.split("+", 1)[0]
    modern = HERE / f"LegacyMusic-{short}.ipa"
    legacy = HERE / f"LegacyMusic-{short}-legacy.ipa"
    rootless = HERE / "packages" / f"{make_rootless_deb.PACKAGE}_{version}_iphoneos-arm64.deb"

    print(f"\n==> Release {version}\n")

    # (label, built path, description, name used inside versions/<version>/)
    rel = version.split("-", 1)[0]  # "10-9+debug" -> "10" -> r10 in file names
    built = [("rootful deb ", rootful, "iphoneos-arm, armv7+arm64, iOS 6+",
              f"ANLegacy-r{rel}-rootful.deb")]

    if not args.skip_ipas:
        make_modern_ipa.build_modern_ipa(rootful, modern)
        built.append(("modern ipa  ", modern, "arm64, iOS 11+, sdk 14.0",
                      f"ANLegacy-r{rel}-64bit.ipa"))
        make_legacy_ipa.build_legacy_ipa(rootful, legacy)
        built.append(("legacy ipa  ", legacy, "armv7, iOS 6+",
                      f"ANLegacy-r{rel}-32bit.ipa"))

    if not args.skip_debs:
        # The rootless payload must be the modern (letterbox-fixed) app, so
        # fall back to the newest existing modern .ipa when --skip-ipas was used.
        source = modern
        if args.skip_ipas:
            source = make_rootless_deb.default_ipa()
        make_rootless_deb.build_rootless_deb(source, rootless, version)
        built.append(("rootless deb", rootless, "iphoneos-arm64, /var/jb, iOS 15+",
                      f"ANLegacy-r{rel}-rootless.deb"))

    print("\n==> Artifacts")
    for label, path, note, archive_name in built:
        print(f"  {label}  {path.name}  ({human(path)})  [{note}]")

    dest = archive(version, built)
    print(f"\n==> Archived {len(built)} file(s) to {dest}")
    for _, _, _, archive_name in built:
        print(f"      {archive_name}")


if __name__ == "__main__":
    main()
