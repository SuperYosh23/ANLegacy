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
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
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


LIPO = Path("/home/superyosh23/theos/toolchain/linux/iphone/bin/lipo")


def armv7_only_deb(deb_path: Path) -> None:
    """Rewrite a rootful .deb so its executable is the armv7 slice alone.

    Done after packaging rather than by changing ARCHS, because the rootless deb
    and the modern ipa are derived from the same fat binary and both need arm64.
    Uses the system `ar` rather than writing the archive by hand.
    """
    work = Path(tempfile.mkdtemp(prefix="armv7only_"))
    try:
        subprocess.run(["ar", "x", str(deb_path)], cwd=str(work), check=True)

        data_tar = next((p for p in work.iterdir()
                         if p.name.startswith("data.tar")), None)
        if data_tar is None:
            raise SystemExit(f"no data.tar in {deb_path}")
        ext = data_tar.name[len("data.tar"):]

        extract_dir = work / "x"
        extract_dir.mkdir()
        subprocess.run(["tar", "-xf", str(data_tar), "-C", str(extract_dir)],
                       check=True)

        exe = next(extract_dir.glob("Applications/*.app/LegacyMusic"), None)
        if exe is None:
            raise SystemExit(f"executable not found in {deb_path}")
        subprocess.run([str(LIPO), str(exe), "-thin", "armv7",
                        "-output", str(exe) + ".thin"], check=True)
        (Path(str(exe) + ".thin")).replace(exe)

        # Recompress with the same extension dm.pl used.
        inner = work / ("new.tar" + ext)
        subprocess.run(["tar", "-cf", str(inner), "-C", str(extract_dir),
                        "Applications"], check=True)
        if ext == ".lzma":
            subprocess.run(["xz", "--format=lzma", "-c", str(inner)],
                           stdout=open(work / "payload", "wb"), check=True)
        elif ext == ".gz":
            subprocess.run(["gzip", "-c", str(inner)],
                           stdout=open(work / "payload", "wb"), check=True)
        else:
            inner.rename(work / "payload")

        # Rebuild the .deb: debian-binary, control.tar.*, data.tar.*
        rebuild = work / "rebuilt.deb"
        subprocess.run(["ar", "rcs", str(rebuild),
                        "debian-binary",
                        *sorted(p.name for p in work.iterdir()
                                if p.name.startswith("control.tar")),
                        "data.tar" + ext], cwd=str(work), check=True)
        if (work / "payload").exists():
            payload = (work / "payload").read_bytes()
        else:
            payload = (work / ("data.tar" + ext)).read_bytes()
        (work / ("data.tar" + ext)).write_bytes(payload)
        subprocess.run(["ar", "rcs", str(rebuild),
                        "debian-binary",
                        *sorted(p.name for p in work.iterdir()
                                if p.name.startswith("control.tar")),
                        "data.tar" + ext], cwd=str(work), check=True)
        shutil.copyfile(rebuild, deb_path)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print(f"   [armv7-only] rewrote {deb_path.name} to the 32-bit slice")

def version_of(deb: Path) -> str:
    # com.legacymusic.app_10-9+debug_iphoneos-arm.deb -> 10-9+debug
    return deb.name.split("_", 1)[1].rsplit("_", 1)[0]


def run_ios6_gate() -> None:
    """Fail the release if the armv7 slice would break on iOS 6.

    The app compiles against the iOS 9.3 SDK but ships to iOS 6 devices, so
    the compiler accepts APIs that don't exist on the device. That only shows up
    at runtime (unrecognized selector) or at load time (dyld: Symbol not found,
    before main, with no crash report). Both happened during WARP development.
    """
    print("==> iOS 6 compatibility gate")
    subprocess.run([sys.executable, str(HERE / "ios6_compat_check.py")],
                   cwd=str(HERE), check=True)


def sync_plist_version() -> str:
    """Make the bundle's Info.plist authoritative, with control's version in it.

    Two Info.plist files exist and used to disagree. Theos reads
    LegacyMusic.plist (named after APPLICATION_NAME) to generate the bundle's
    Info.plist, and then the resource copy at Resources/Info.plist is copied in
    over the top of it. So Resources/Info.plist is the one that actually ships,
    and LegacyMusic.plist is dead weight - except that Theos still wants it to
    exist. Bumping only control's Version, as was done for 12 -> 13, therefore
    changed the .deb version while Settings kept reporting 12: the shipped plist
    was never touched.

    Rather than keep two plists in step by hand, Resources/Info.plist is treated
    as the single source of truth. LegacyMusic.plist is regenerated from it on
    every build (so Theos' template matches what ships, and the overwrite is a
    no-op), and the version is written from control.
    """
    version = None
    for line in (HERE / "control").read_text().splitlines():
        if line.startswith("Version:"):
            version = line.split(":", 1)[1].strip()
            break
    if not version:
        raise SystemExit("control has no Version: line")

    shipped = HERE / "Resources" / "Info.plist"
    if not shipped.is_file():
        raise SystemExit(f"missing {shipped}")
    text = shipped.read_text()

    # Only the two version keys; anything else in the plist is left alone.
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        pattern = rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)"
        text, n = re.subn(pattern, rf"\g<1>{version}\g<2>", text)
        if n != 1:
            raise SystemExit(f"expected exactly one {key} in the plist, found {n}")

    shipped.write_text(text)
    # Theos' template. Same content, so whichever file wins the copy the bundle
    # ends up identical.
    (HERE / "LegacyMusic.plist").write_text(text)
    return version


def verify_shipped_version(deb_path: Path) -> None:
    """Check the built .deb's Info.plist agrees with control's Version.

    Two Info.plist files and a resource directory all have to line up for
    Settings to report the right version, and getting it wrong fails silently:
    the app launches perfectly and simply quotes the wrong number. This has
    already shipped twice - once because the resource dir was pointed at the
    wrong case, and once because only control was bumped. Reading the version
    back out of the artifact that is actually going out is the only check that
    cannot be fooled by the intermediate files looking correct.
    """
    import plistlib
    import tarfile

    expected = None
    for line in (HERE / "control").read_text().splitlines():
        if line.startswith("Version:"):
            expected = line.split(":", 1)[1].strip().split("+", 1)[0]
            break
    if not expected:
        raise SystemExit("control has no Version: line")

    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ar", "x", str(deb_path)], cwd=tmp, check=True)
        data = next(Path(tmp).glob("data.tar.*"))
        # tarfile's default mode transparently handles gz/xz/bz2.
        with tarfile.open(data) as tar:
            plist = tar.extractfile("Applications/LegacyMusic.app/Info.plist")
            if plist is None:
                raise SystemExit(f"{deb_path.name} has no Applications/LegacyMusic.app/Info.plist")
            info = plistlib.loads(plist.read())

    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        got = info.get(key)
        if got != expected:
            raise SystemExit(
                f"version mismatch: {deb_path.name} ships {key}={got!r} but control says {expected!r}. "
                "Resources/Info.plist is the file that becomes the bundle's Info.plist; check it was "
                "regenerated and that LegacyMusic_RESOURCE_DIRS still points at Resources."
            )
    print(f"==> shipped version verified: {expected}")


def run_make_package() -> None:
    env = os.environ.copy()
    env["THEOS"] = str(THEOS)
    env["PATH"] = f"{THEOS}/bin:" + env.get("PATH", "")
    print(f"==> make package ({THEOS})")
    subprocess.run(["make", "package"], cwd=str(HERE), env=env, check=True)
    # After building, so the armv7 slice exists for the symbol scan. A failure
    # here aborts the release rather than shipping a binary that crashes on
    # launch for anyone still on iOS 6.
    run_ios6_gate()


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
    parser.add_argument("--no-armv7-only", action="store_true",
                        help="keep both slices in the rootful deb (unsafe on iOS < 11)")
    parser.add_argument("--skip-debs", action="store_true", help="only build the .ipas")
    parser.add_argument("--skip-ipas", action="store_true", help="only build the .debs")
    args = parser.parse_args()

    if args.deb:
        rootful = Path(args.deb).resolve()
    else:
        if not args.no_build:
            # Before the build, so the bundle that gets built carries it.
            print(f"==> syncing plist version from control ({sync_plist_version()})")
            run_make_package()
        rootful = newest_rootful_deb()

    if not rootful.is_file():
        raise SystemExit(f"Rootful .deb not found: {rootful}")

    verify_shipped_version(rootful)

    version = version_of(rootful)
    short = version.split("+", 1)[0]
    modern = HERE / f"LegacyMusic-{short}.ipa"
    legacy = HERE / f"LegacyMusic-{short}-legacy.ipa"
    rootless = HERE / "packages" / f"{make_rootless_deb.PACKAGE}_{version}_iphoneos-arm64.deb"

    print(f"\n==> Release {version}\n")

    rel = version.split("-", 1)[0]  # "10-9+debug" -> "10" -> r10 in file names

    # The arm64 slice is built for iOS 11+ (it has to be: it links against the
    # iOS 11.2 SDK). dyld does NOT reliably honour a fat binary's per-slice
    # minos when choosing a slice, and an iOS 9.2 iPhone 6s was observed running
    # the arm64 slice and crashing in __cxa_bad_cast the moment Now Playing or
    # iPod mode built a view. The only reliable way to keep old iOS on 32-bit is
    # to not offer it a slice it cannot run.
    #
    # This applies to the rootful deb, which is the artifact installed on
    # pre-iOS-11 jailbreaks. iOS 11 dropped 32-bit app support entirely, so an
    # armv7-only rootful deb costs nothing on modern devices: those use the
    # rootless deb or the modern ipa, which are arm64-only by construction.
    force_armv7_only = not args.no_armv7_only

    # (label, built path, description, name used inside versions/<version>/)
    desc = ("iphoneos-arm, armv7, iOS 6-10" if force_armv7_only
            else "iphoneos-arm, armv7+arm64, iOS 6+")
    built = [("rootful deb ", rootful, desc,
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

    # Strip arm64 from the rootful deb last: the ipa builders and the rootless
    # deb above all read the arm64 slice out of it, so thinning earlier would
    # leave them with nothing to package.
    if force_armv7_only:
        armv7_only_deb(rootful)

    print("\n==> Artifacts")
    for label, path, note, archive_name in built:
        print(f"  {label}  {path.name}  ({human(path)})  [{note}]")

    dest = archive(version, built)
    print(f"\n==> Archived {len(built)} file(s) to {dest}")
    for _, _, _, archive_name in built:
        print(f"      {archive_name}")


if __name__ == "__main__":
    main()
