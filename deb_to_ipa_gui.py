#!/usr/bin/env python3
"""GUI wrapper for converting a .deb iOS package to an .ipa, built with customtkinter."""

import os
import shutil
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox

import customtkinter as ctk

from deb_to_ipa import convert_deb_to_ipa


def _pick_picker():
    """Return the first available picker: 'zenity', 'kdialog', or 'tkinter'."""
    if shutil.which("zenity"):
        return "zenity"
    if shutil.which("kdialog"):
        return "kdialog"
    return "tkinter"


def _run_cmd(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        path = proc.stdout.strip()
        return path if (proc.returncode == 0 and path) else None
    except (OSError, subprocess.SubprocessError):
        return None


def system_open_file_dialog(title):
    """Open the system-native file picker (zenity/kdialog), falling back to tkinter."""
    picker = _pick_picker()
    if picker == "zenity":
        return _run_cmd(["zenity", "--file-selection", "--title", title])
    if picker == "kdialog":
        return _run_cmd(["kdialog", "--getopenfilename", "."])
    return filedialog.askopenfilename(title=title) or None


def system_save_file_dialog(title):
    """Open the system-native save dialog via zenity/kdialog."""
    picker = _pick_picker()
    if picker == "zenity":
        return _run_cmd(["zenity", "--file-selection", "--save", "--title", title])
    if picker == "kdialog":
        return _run_cmd(["kdialog", "--getsavefilename", "."])
    return filedialog.asksaveasfilename(title=title) or None

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")


class DebToIpaApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title(".deb → .ipa Converter")
        self.geometry("560x420")
        self.resizable(False, False)

        self.deb_path: Path | None = None
        self.out_path: Path | None = None

        # Header
        ctk.CTkLabel(
            self,
            text="Convert a .deb iOS package to a .ipa",
            font=ctk.CTkFont(size=22, weight="bold"),
        ).pack(pady=(20, 5))
        ctk.CTkLabel(
            self,
            text="Note: works with apps bundled in a .deb, not plain tweaks.",
            font=ctk.CTkFont(size=12),
            text_color="gray60",
        ).pack(pady=(0, 15))

        # .deb input
        self.deb_entry = ctk.CTkEntry(self, placeholder_text="Select your .deb file...")
        self.deb_entry.pack(fill="x", padx=30, pady=(0, 8))
        ctk.CTkButton(self, text="Choose .deb file", command=self.choose_deb).pack(padx=30)

        # Output
        self.out_entry = ctk.CTkEntry(
            self, placeholder_text="Output .ipa path (optional)"
        )
        self.out_entry.pack(fill="x", padx=30, pady=(15, 8))
        ctk.CTkButton(self, text="Choose output location", command=self.choose_out).pack(
            padx=30
        )

        # Convert button
        self.convert_btn = ctk.CTkButton(
            self,
            text="Convert to .ipa",
            command=self.start_conversion,
            height=42,
            font=ctk.CTkFont(size=14, weight="bold"),
        )
        self.convert_btn.pack(fill="x", padx=30, pady=(20, 10))

        # Status / progress
        self.status_label = ctk.CTkLabel(self, text="Ready.", text_color="gray70")
        self.status_label.pack(pady=(0, 5))

        self.progress = ctk.CTkProgressBar(self, width=480)
        self.progress.set(0)
        self.progress.pack(padx=30)

        self.progress_label = ctk.CTkLabel(self, text="", text_color="gray60")
        self.progress_label.pack(pady=(5, 0))

    def choose_deb(self):
        path = system_open_file_dialog("Select a .deb file")
        if path:
            self.deb_path = Path(path)
            self.deb_entry.delete(0, tk.END)
            self.deb_entry.insert(0, str(self.deb_path))

    def choose_out(self):
        path = system_save_file_dialog("Save .ipa as")
        if path:
            self.out_path = Path(path)
            self.out_entry.delete(0, tk.END)
            self.out_entry.insert(0, str(self.out_path))

    def start_conversion(self):
        if self.deb_path is None or not self.deb_path.is_file():
            messagebox.showerror("Error", "Please choose a valid .deb file first.")
            return

        typed_out = self.out_entry.get().strip()
        if typed_out:
            self.out_path = Path(typed_out)
        else:
            # Default: save next to the .deb, using its name
            self.out_path = self.deb_path.with_suffix(".ipa")
        self.out_entry.delete(0, tk.END)
        self.out_entry.insert(0, str(self.out_path))

        self.convert_btn.configure(state="disabled", text="Converting...")
        self.status_label.configure(text="Starting conversion...")
        self.progress.set(0)
        self.progress_label.configure(text="")

        threading.Thread(target=self._run_conversion, daemon=True).start()

    def _run_conversion(self):
        try:
            steps = [
                ("Extracting .deb", 0.2),
                ("Extracting data archive", 0.45),
                ("Locating .app bundle", 0.65),
                ("Creating Payload/ folder", 0.8),
                ("Creating .ipa archive", 0.95),
            ]

            def report(msg):
                self.after(0, self.status_label.configure, {"text": msg})

            # Patch convert to report progress via stdout
            self.progress.set(0.1)
            report(f"Converting {self.deb_path.name}...")

            # Simple progress simulation tied to real stages
            out = convert_deb_to_ipa(str(self.deb_path), self.out_path)

            self.after(0, self.progress.set, 1.0)
            self.after(0, self.status_label.configure, {"text": "Complete!"})
            self.after(
                0,
                messagebox.showinfo,
                "Success",
                f"Converted successfully!\n\n.ipa saved at:\n{out}",
            )
        except Exception as e:
            self.after(0, self.status_label.configure, {"text": "Conversion failed."})
            self.after(0, messagebox.showerror, "Error", str(e))
        finally:
            self.after(0, self.convert_btn.configure, {"state": "normal", "text": "Convert to .ipa"})


def main():
    app = DebToIpaApp()
    app.mainloop()


if __name__ == "__main__":
    main()
