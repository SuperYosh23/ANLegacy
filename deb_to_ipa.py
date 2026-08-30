#!/usr/bin/env python3
"""
Convert a .deb (iOS tweak/app) file to a .ipa file.

Works for apps bundled inside a .deb. Follows this process:
  1. Extract the .deb, producing a data.tar archive.
  2. Extract the tar archive to reveal an Applications/ folder.
  3. Find the .app folder inside Applications/.
  4. Create a Payload/ folder and move the .app into it.
  5. Zip Payload/ into a .ipa file.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path


def run_cmd(cmd: list, cwd: str | None = None) -> None:
    """Run a shell command, raising an error if it fails."""
    print(f"  -> {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(cmd)}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


def convert_deb_to_ipa(deb_path: str, out_path: str | None = None) -> Path:
    deb_path = Path(deb_path).resolve()
    if not deb_path.is_file():
        raise FileNotFoundError(f".deb file not found: {deb_path}")

    # Validate it's a .deb (ar archive containing data.tar.*)
    with tempfile.TemporaryDirectory(prefix="deb2ipa_") as tmp:
        workdir = Path(tmp)

        # Step 1: Extract the .deb (ar archive -> data.tar.*)
        print(f"[1/5] Extracting .deb: {deb_path}")
        try:
            run_cmd(["ar", "x", str(deb_path)], cwd=str(workdir))
        except FileNotFoundError:
            print("  'ar' not found, trying 7z fallback...")
            run_cmd(["7z", "x", str(deb_path)], cwd=str(workdir))

        # Find data.tar.*
        data_tars = sorted(workdir.glob("data.tar*"))
        if not data_tars:
            raise RuntimeError("No data.tar archive found inside the .deb file.")
        data_tar = data_tars[0]
        print(f"  Found archive: {data_tar.name}")

        # Step 2: Extract the data.tar
        print(f"[2/5] Extracting {data_tar.name}")
        extraction_dir = workdir / "extracted"
        extraction_dir.mkdir()
        try:
            with tarfile.open(data_tar) as tf:
                tf.extractall(extraction_dir)
        except tarfile.ReadError:
            # Fallback for compressed tars (xz, gz, bz2) not auto-detected
            run_cmd(["tar", "-xf", str(data_tar), "-C", str(extraction_dir)])

        # Step 3: Locate Applications/<something>.app
        print("[3/5] Locating the .app bundle")
        apps_dir = extraction_dir / "Applications"
        if not apps_dir.is_dir():
            raise RuntimeError("No 'Applications' folder found after extraction.")
        app_bundles = [p for p in apps_dir.iterdir() if p.is_dir() and p.suffix == ".app"]
        if not app_bundles:
            raise RuntimeError(
                "No .app folder found in Applications/. "
                "Note: this method only works with apps, not tweaks."
            )
        if len(app_bundles) > 1:
            print(f"  Found multiple .app bundles: {[b.name for b in app_bundles]}")
        app_bundle = app_bundles[0]
        print(f"  Using bundle: {app_bundle.name}")

        # Step 4: Create Payload/ and move the .app into it
        print("[4/5] Creating Payload/ folder")
        payload_dir = workdir / "Payload"
        payload_dir.mkdir()
        shutil.copytree(app_bundle, payload_dir / app_bundle.name, symlinks=True)

        # Step 5: Zip Payload/ into the .ipa
        print("[5/5] Creating .ipa archive")
        if out_path is None:
            out_path = str(workdir / (deb_path.stem + ".ipa"))
        out_path = Path(out_path).resolve()

        with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(payload_dir):
                for name in files:
                    full = Path(root) / name
                    arcname = full.relative_to(payload_dir.parent)
                    zf.write(full, arcname)
                for name in dirs:
                    full = Path(root) / name
                    arcname = full.relative_to(payload_dir.parent)
                    zf.write(full, arcname)

        print(f"\nDone! .ipa created at: {out_path}")
        return out_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert a .deb iOS package to .ipa")
    parser.add_argument("deb", help="Path to the input .deb file")
    parser.add_argument(
        "-o", "--output", help="Output .ipa path (defaults to <debname>.ipa)"
    )
    args = parser.parse_args()

    try:
        convert_deb_to_ipa(args.deb, args.output)
    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
