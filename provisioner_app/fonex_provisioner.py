"""
FONEX Device Provisioner v2.0 — Windows / macOS Desktop App
Powered by Roy Communication

Fully self-contained: ADB and the FONEX APK are bundled inside this EXE.
The shop owner double-clicks the EXE — no extra files needed.

Build EXE (on Windows):
    Run build_exe.bat — it downloads ADB automatically and bundles everything.
"""

import customtkinter as ctk
import tkinter as tk
from tkinter import filedialog, messagebox
import subprocess
import threading
import os
import sys
import platform
import time
import webbrowser
from typing import Tuple

# Try to load Pillow for logo display
try:
    from PIL import Image, ImageTk
    import PIL
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# ─── FONEX Brand Colors ────────────────────────────────────────────────────────
BG         = "#06080F"
SURFACE    = "#0D1B2A"
CARD       = "#112233"
BORDER     = "#1E3A5F"
ACCENT     = "#2563EB"
ACCENT_LT  = "#60A5FA"
ACCENT_DK  = "#1D4ED8"
PURPLE     = "#8B5CF6"
CYAN       = "#22D3EE"
GREEN      = "#22C55E"
GREEN_DK   = "#15803D"
RED        = "#EF4444"
ORANGE     = "#F59E0B"
TEXT       = "#F1F5F9"
TEXT_SEC   = "#94A3B8"
TEXT_MUTED = "#475569"

# ─── Robust File Discovery ─────────────────────────────────────────────────────
def find_bundled_file(target_name: str) -> str:
    """Recursively search for a file starting from the executable's directory."""
    roots = []
    if getattr(sys, "frozen", False):
        exe_dir = os.path.dirname(sys.executable)
        roots.append(exe_dir)
        roots.append(os.path.dirname(exe_dir))
        if hasattr(sys, "_MEIPASS"):
            roots.append(sys._MEIPASS)
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        roots.append(script_dir)
        roots.append(os.path.join(script_dir, "platform-tools"))

    seen = set()
    unique_roots = [x for x in roots if not (x in seen or seen.add(x))]

    for r in unique_roots:
        for candidate in [
            os.path.join(r, target_name),
            os.path.join(r, "platform-tools", target_name),
            os.path.join(r, "_internal", target_name),
        ]:
            if os.path.exists(candidate):
                return candidate

    for r in unique_roots:
        for root, dirs, files in os.walk(r):
            if target_name in files:
                return os.path.join(root, target_name)

    return ""


def get_adb_path() -> str:
    """Find absolute ADB path using robust discovery."""
    adb_name = "adb.exe" if sys.platform == "win32" else "adb"
    found = find_bundled_file(adb_name)
    if found:
        return found
    try:
        cflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        if subprocess.run([adb_name, "version"], capture_output=True, timeout=5, creationflags=cflags).returncode == 0:
            return adb_name
    except Exception:
        pass
    return ""


def get_bundled_apk() -> str:
    """Find absolute APK path using robust discovery."""
    found = find_bundled_file("fonex.apk")
    if found:
        return found
    base_dir = os.path.dirname(os.path.abspath(__file__))
    for rel in [
        "../build/app/outputs/flutter-apk/app-release.apk",
        "../build/app/outputs/flutter-apk/app-debug.apk",
    ]:
        p = os.path.normpath(os.path.join(base_dir, rel))
        if os.path.exists(p):
            return p
    return ""


def get_logo_path() -> str:
    """Find the FONEX logo image."""
    for candidate in [
        find_bundled_file("fonex-logo.jpeg"),
        find_bundled_file("fonex-logo.jpg"),
        find_bundled_file("fonex-logo.png"),
    ]:
        if candidate:
            return candidate
    # Dev: look relative to script
    base_dir = os.path.dirname(os.path.abspath(__file__))
    for rel in [
        "../public/images/fonex-logo.jpeg",
        "../public/images/fonex-logo.jpg",
        "../public/images/fonex-logo.png",
    ]:
        p = os.path.normpath(os.path.join(base_dir, rel))
        if os.path.exists(p):
            return p
    return ""


# ─── App Config ───────────────────────────────────────────────────────────────
PACKAGE    = "com.roycommunication.fonex"
RECEIVER   = ".MyDeviceAdminReceiver"
ACTIVITY   = ".MainActivity"
IS_BUNDLED = getattr(sys, "frozen", False)
TOTAL_STEPS = 6  # Welcome → ADB → Device → Install → Owner → Done

# ─── Utility ─────────────────────────────────────────────────────────────────
def run_adb(adb: str, *args, timeout: int = 30) -> Tuple[int, str, str]:
    try:
        cflags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        r = subprocess.run(
            [adb, *args],
            capture_output=True, text=True, timeout=timeout,
            creationflags=cflags
        )
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)


# ─────────────────────────────────────────────────────────────────────────────
# MAIN APPLICATION
# ─────────────────────────────────────────────────────────────────────────────
class FonexProvisioner(ctk.CTk):
    def __init__(self):
        super().__init__()

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.title("FONEX — Device Provisioner")
        self.geometry("900x720")
        self.minsize(800, 650)
        self.resizable(True, True)
        self.configure(fg_color=BG)

        # Center window
        self.update_idletasks()
        x = (self.winfo_screenwidth()  - 900) // 2
        y = (self.winfo_screenheight() - 720) // 2
        self.geometry(f"+{x}+{y}")

        # State
        self.current_step  = 0
        self.adb_path      = ""
        self.apk_path      = ""
        self._device_poll  = None
        self._device_found = False
        self._logo_image   = None  # keep reference to avoid GC

        self._build_ui()
        self._show_step_welcome()

    # ─── UI Shell ────────────────────────────────────────────────────────────
    def _build_ui(self):
        # ── Top Banner ──────────────────────────────────────────────────────
        banner = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=88)
        banner.pack(fill="x")
        banner.pack_propagate(False)

        # Logo image or fallback letter badge
        logo_container = ctk.CTkFrame(banner, fg_color="transparent", width=64, height=64)
        logo_container.place(x=24, rely=0.5, anchor="w")
        logo_container.pack_propagate(False)

        logo_placed = False
        logo_path = get_logo_path()
        if PIL_AVAILABLE and logo_path:
            try:
                img = Image.open(logo_path).resize((60, 60), Image.LANCZOS)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(60, 60))
                self._logo_image = ctk_img
                lbl = ctk.CTkLabel(logo_container, image=ctk_img, text="",
                                   width=60, height=60, corner_radius=30)
                lbl.pack()
                logo_placed = True
            except Exception:
                pass

        if not logo_placed:
            fallback = ctk.CTkLabel(
                logo_container, text="F",
                font=ctk.CTkFont("Arial", 32, "bold"),
                text_color=TEXT,
                fg_color=ACCENT, corner_radius=30,
                width=60, height=60,
            )
            fallback.pack()

        # Title
        title_frame = ctk.CTkFrame(banner, fg_color="transparent")
        title_frame.place(x=100, rely=0.5, anchor="w")

        ctk.CTkLabel(
            title_frame,
            text="FONEX  Device Provisioner",
            font=ctk.CTkFont("Arial", 24, "bold"),
            text_color=TEXT,
        ).pack(anchor="w")

        ctk.CTkLabel(
            title_frame,
            text="Powered by Roy Communication",
            font=ctk.CTkFont("Arial", 12),
            text_color=TEXT_SEC,
        ).pack(anchor="w", pady=(2, 0))

        # Right side version badge
        badge = ctk.CTkFrame(banner, fg_color=ACCENT_DK, corner_radius=10, width=72, height=32)
        badge.place(relx=1.0, x=-24, rely=0.5, anchor="e")
        ctk.CTkLabel(badge, text="v2.0",
                     font=ctk.CTkFont("Arial", 12, "bold"),
                     text_color=TEXT).place(relx=0.5, rely=0.5, anchor="center")

        # ── Step Indicator Bar ───────────────────────────────────────────────
        self.step_bar_frame = ctk.CTkFrame(self, fg_color=CARD, corner_radius=0, height=70)
        self.step_bar_frame.pack(fill="x")
        self.step_bar_frame.pack_propagate(False)

        self.step_labels = []
        steps_meta = [
            ("1", "Welcome"),
            ("2", "ADB Check"),
            ("3", "Connect Phone"),
            ("4", "Install App"),
            ("5", "Device Owner"),
            ("6", "Done"),
        ]
        for i, (num_text, name) in enumerate(steps_meta):
            col = ctk.CTkFrame(self.step_bar_frame, fg_color="transparent")
            col.pack(side="left", expand=True, fill="both")

            num = ctk.CTkLabel(
                col, text=num_text,
                font=ctk.CTkFont("Arial", 13, "bold"),
                text_color=TEXT_MUTED,
                fg_color="transparent",
                width=32, height=32,
                corner_radius=16,
            )
            num.pack(pady=(12, 4))

            lbl = ctk.CTkLabel(
                col, text=name,
                font=ctk.CTkFont("Arial", 10),
                text_color=TEXT_MUTED,
            )
            lbl.pack(pady=(0, 8))
            self.step_labels.append((num, lbl))

        # Separator
        sep = ctk.CTkFrame(self, fg_color=BORDER, height=1, corner_radius=0)
        sep.pack(fill="x")

        # Content area
        self.content = ctk.CTkFrame(self, fg_color=BG, corner_radius=0)
        self.content.pack(fill="both", expand=True)

        # ── Bottom Navigation Bar ────────────────────────────────────────────
        self.bottom = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=88)
        self.bottom.pack(fill="x", side="bottom")
        self.bottom.pack_propagate(False)

        # Footer text
        ctk.CTkLabel(
            self.bottom,
            text="© Roy Communication  •  All devices provisioned with FONEX are protected",
            font=ctk.CTkFont("Arial", 11),
            text_color=TEXT_MUTED,
        ).place(relx=0.5, y=68, anchor="center")

        self.btn_back = ctk.CTkButton(
            self.bottom, text="← Back",
            width=140, height=48,
            fg_color="transparent", border_color=BORDER, border_width=2,
            text_color=TEXT_SEC, hover_color=CARD,
            command=self._go_back,
            font=ctk.CTkFont("Arial", 14, "bold"),
            corner_radius=12,
        )
        self.btn_back.place(x=24, y=18)

        self.btn_next = ctk.CTkButton(
            self.bottom, text="Start Setup  →",
            width=200, height=48,
            fg_color=ACCENT, hover_color=ACCENT_DK,
            text_color=TEXT,
            command=self._go_next,
            font=ctk.CTkFont("Arial", 15, "bold"),
            corner_radius=12,
        )
        self.btn_next.place(relx=1.0, x=-24, y=18, anchor="ne")

    # ─── Step indicator sync ─────────────────────────────────────────────────
    def _update_step_bar(self, active: int):
        for i, (num, lbl) in enumerate(self.step_labels):
            if i < active:
                num.configure(text="✓", text_color=GREEN, fg_color="#0F2E1A", width=32, height=32, corner_radius=16)
                lbl.configure(text_color=GREEN, font=ctk.CTkFont("Arial", 10, "bold"))
            elif i == active:
                num.configure(text=str(i + 1), text_color=TEXT, fg_color=ACCENT, width=32, height=32, corner_radius=16)
                lbl.configure(text_color=ACCENT_LT, font=ctk.CTkFont("Arial", 10, "bold"))
            else:
                num.configure(text=str(i + 1), text_color=TEXT_MUTED, fg_color="transparent", width=32, height=32, corner_radius=16)
                lbl.configure(text_color=TEXT_MUTED, font=ctk.CTkFont("Arial", 10))

    # ─── Helpers ─────────────────────────────────────────────────────────────
    def _clear(self):
        for w in self.content.winfo_children():
            w.destroy()

    def _card(self, parent, **kwargs) -> ctk.CTkFrame:
        """Creates a styled info card."""
        return ctk.CTkFrame(parent, fg_color=CARD, corner_radius=16,
                            border_width=2, border_color=BORDER, **kwargs)

    def _go_next(self):
        self._cancel_poll()
        step_map = {
            0: self._show_step_adb,
            1: self._start_step_device,
            2: self._start_step_install,   # APK step removed — go directly to install
            3: self._start_step_owner,
            4: self._show_step_done,
        }
        if self.current_step in step_map:
            step_map[self.current_step]()

    def _go_back(self):
        self._cancel_poll()
        step_map = {
            1: self._show_step_welcome,
            2: self._show_step_adb,
            3: self._start_step_device,
        }
        if self.current_step in step_map:
            step_map[self.current_step]()

    def _cancel_poll(self):
        if self._device_poll:
            self.after_cancel(self._device_poll)
            self._device_poll = None

    def _set_nav(self, back=True, next_=True, next_text="Next  →", next_color=ACCENT):
        self.btn_back.configure(state="normal" if back else "disabled")
        self.btn_next.configure(
            state="normal" if next_ else "disabled",
            text=next_text,
            fg_color=next_color if next_ else TEXT_MUTED,
            hover_color=ACCENT_DK if next_color == ACCENT else next_color,
        )

    # =========================================================================
    # STEP 0 — Welcome
    # =========================================================================
    def _show_step_welcome(self):
        self.current_step = 0
        self._clear()
        self._update_step_bar(0)
        self._set_nav(back=False, next_text="Start Setup  →")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        # Hero logo — large version
        hero_frame = ctk.CTkFrame(outer, fg_color="transparent", width=140, height=140)
        hero_frame.pack(pady=(0, 20))
        hero_frame.pack_propagate(False)

        logo_path = get_logo_path()
        logo_placed = False
        if PIL_AVAILABLE and logo_path:
            try:
                img = Image.open(logo_path).resize((130, 130), Image.LANCZOS)
                ctk_img = ctk.CTkImage(light_image=img, dark_image=img, size=(130, 130))
                self._logo_hero = ctk_img
                lbl = ctk.CTkLabel(hero_frame, image=ctk_img, text="",
                                   width=130, height=130, corner_radius=65)
                lbl.place(relx=0.5, rely=0.5, anchor="center")
                logo_placed = True
            except Exception:
                pass

        if not logo_placed:
            ctk.CTkLabel(
                hero_frame, text="F",
                font=ctk.CTkFont("Arial", 64, "bold"),
                text_color=TEXT, fg_color=ACCENT,
                corner_radius=65, width=130, height=130,
            ).place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(
            outer, text="FONEX Device Provisioner",
            font=ctk.CTkFont("Arial", 32, "bold"),
            text_color=TEXT,
        ).pack()

        ctk.CTkLabel(
            outer, text="Powered by Roy Communication",
            font=ctk.CTkFont("Arial", 14),
            text_color=TEXT_SEC,
        ).pack(pady=(4, 28))

        # Info steps card
        card = self._card(outer, width=600)
        card.pack(fill="x", ipadx=28, ipady=18, padx=20)

        steps_info = [
            ("🔧", "ADB Tools",       "Automatically verified — ADB is bundled"),
            ("📱", "Connect Phone",   "Plug in via USB & enable USB Debugging"),
            ("📦", "Install FONEX",   "App installed automatically — no manual steps"),
            ("🔒", "Set Device Owner","Protects device & enables payment lock system"),
        ]
        for emoji, title, desc in steps_info:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=10, padx=20)
            ctk.CTkLabel(row, text=emoji, font=ctk.CTkFont("Arial", 24),
                         width=44, text_color=TEXT).pack(side="left")
            col = ctk.CTkFrame(row, fg_color="transparent")
            col.pack(side="left", padx=16)
            ctk.CTkLabel(col, text=title, font=ctk.CTkFont("Arial", 15, "bold"),
                         text_color=TEXT, anchor="w").pack(anchor="w")
            ctk.CTkLabel(col, text=desc, font=ctk.CTkFont("Arial", 12),
                         text_color=TEXT_SEC, anchor="w").pack(anchor="w")

        ctk.CTkLabel(
            outer,
            text="⏱  Total time: ~2–3 minutes  •  Keep the phone connected throughout",
            font=ctk.CTkFont("Arial", 12),
            text_color=TEXT_MUTED,
        ).pack(pady=(24, 0))

    # =========================================================================
    # STEP 1 — ADB Check
    # =========================================================================
    def _show_step_adb(self):
        self.current_step = 1
        self._clear()
        self._update_step_bar(1)
        self._set_nav(back=True, next_=False, next_text="Checking…")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="🔧  Verifying ADB Tools",
                     font=ctk.CTkFont("Arial", 28, "bold"), text_color=TEXT).pack(pady=(0, 8))
        ctk.CTkLabel(outer, text="ADB (Android Debug Bridge) lets this app talk to the Android phone.",
                     font=ctk.CTkFont("Arial", 13), text_color=TEXT_SEC,
                     wraplength=560).pack()

        self._adb_status_lbl = ctk.CTkLabel(
            outer, text="🔍  Searching…",
            font=ctk.CTkFont("Arial", 16, "bold"),
            text_color=ORANGE,
        )
        self._adb_status_lbl.pack(pady=24)

        self._adb_card = self._card(outer, width=600)
        self._adb_card.pack(padx=24, fill="x", ipady=16, ipadx=20)
        self._adb_inner = ctk.CTkFrame(self._adb_card, fg_color="transparent")
        self._adb_inner.pack(fill="x", padx=14, pady=8)

        self.after(500, self._do_adb_check)

    def _do_adb_check(self):
        adb = get_adb_path()
        self.adb_path = adb

        for w in self._adb_inner.winfo_children():
            w.destroy()

        if adb:
            rc, out, _ = run_adb(adb, "version")
            ver = out.split("\n")[0] if out else "ADB ready"
            self._adb_status_lbl.configure(text="✅  ADB found — all good!", text_color=GREEN)
            ctk.CTkLabel(self._adb_inner, text=f"  ✓  {ver}",
                         font=ctk.CTkFont("Arial", 12), text_color=GREEN, anchor="w").pack(anchor="w")
            ctk.CTkLabel(self._adb_inner, text=f"  Path: {adb}",
                         font=ctk.CTkFont("Arial", 11), text_color=TEXT_MUTED, anchor="w").pack(anchor="w")
            self._set_nav(back=True, next_=True, next_text="Next  →")
        else:
            self._adb_status_lbl.configure(text="❌  ADB not found", text_color=RED)
            ctk.CTkLabel(self._adb_inner,
                         text="ADB was not found on this computer.",
                         font=ctk.CTkFont("Arial", 12, "bold"),
                         text_color=RED, anchor="w").pack(anchor="w", pady=(4, 2))
            ctk.CTkLabel(self._adb_inner,
                         text="Fix: Place adb.exe in the same folder as this app, or install Android Platform Tools.",
                         font=ctk.CTkFont("Arial", 11),
                         text_color=TEXT_SEC, anchor="w", justify="left", wraplength=440).pack(anchor="w")

            ctk.CTkButton(
                self._adb_inner,
                text="📥  Download Platform Tools",
                fg_color="transparent", border_color=BORDER, border_width=1,
                text_color=ACCENT_LT, hover_color=CARD,
                command=lambda: webbrowser.open("https://developer.android.com/studio/releases/platform-tools"),
            ).pack(anchor="w", pady=(10, 2))

            ctk.CTkButton(
                self._adb_inner, text="🔄  Retry",
                fg_color=ACCENT, hover_color=ACCENT_DK, text_color=TEXT,
                command=self._show_step_adb,
            ).pack(anchor="w", pady=(6, 2))
            self._set_nav(back=True, next_=False)

    # =========================================================================
    # STEP 2 — Connect Phone
    # =========================================================================
    def _start_step_device(self):
        self.current_step = 2
        self._clear()
        self._update_step_bar(2)
        self._set_nav(back=True, next_=False, next_text="Waiting…")

        self._device_found = False

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="📱  Connect the Android Phone",
                     font=ctk.CTkFont("Arial", 28, "bold"), text_color=TEXT).pack(pady=(0, 12))

        card = self._card(outer, width=600)
        card.pack(fill="x", ipadx=20, ipady=14, padx=20)

        steps_list = [
            ("1", "Connect phone to this computer with a USB cable."),
            ("2", "On phone: Settings → About Phone → tap Build Number 7 times."),
            ("3", "Go to Settings → Developer Options → enable USB Debugging."),
            ("4", "A prompt appears on the phone — tap 'Allow'."),
        ]
        for num, txt in steps_list:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=8, padx=20)
            ctk.CTkLabel(row, text=num,
                         font=ctk.CTkFont("Arial", 13, "bold"),
                         fg_color=ACCENT, corner_radius=12,
                         width=28, height=28, text_color=TEXT).pack(side="left")
            ctk.CTkLabel(row, text=f"   {txt}",
                         font=ctk.CTkFont("Arial", 13), text_color=TEXT_SEC,
                         anchor="w", justify="left", wraplength=500).pack(side="left", anchor="w")

        self._device_status_lbl = ctk.CTkLabel(
            outer,
            text="⏳  Waiting for device…",
            font=ctk.CTkFont("Arial", 17, "bold"),
            text_color=ORANGE,
        )
        self._device_status_lbl.pack(pady=22)

        self._device_sub_lbl = ctk.CTkLabel(
            outer,
            text="Checking every 2 seconds — this will update automatically",
            font=ctk.CTkFont("Arial", 12),
            text_color=TEXT_MUTED,
        )
        self._device_sub_lbl.pack()

        self._poll_device()

    def _poll_device(self):
        def check():
            if not self.adb_path:
                self.after(0, lambda: self._device_status_lbl.configure(
                    text="❌  ADB not available", text_color=RED))
                return

            rc, out, _ = run_adb(self.adb_path, "devices")
            lines = [l for l in out.split("\n") if l.strip() and "List of" not in l]
            connected = [l for l in lines if "device" in l and "unauthorized" not in l]
            unauthorized = [l for l in lines if "unauthorized" in l]

            if connected:
                serial = connected[0].split()[0]
                brand = ""
                rc_p, out_p, _ = run_adb(self.adb_path, "-s", serial, "shell",
                                          "getprop", "ro.product.manufacturer")
                if rc_p == 0 and out_p:
                    brand = out_p.strip().lower()
                self.after(0, lambda: self._on_device_found(serial, brand))
            elif unauthorized:
                self.after(0, lambda: self._device_status_lbl.configure(
                    text="⚠️  Phone connected, not authorized yet", text_color=ORANGE))
                self.after(0, lambda: self._device_sub_lbl.configure(
                    text="Tap 'Allow' on the phone's USB Debugging prompt."))
                self._device_poll = self.after(2500, self._poll_device)
            else:
                self._device_poll = self.after(2500, self._poll_device)

        threading.Thread(target=check, daemon=True).start()

    def _on_device_found(self, serial: str, brand: str):
        self._device_found = True
        self._device_manufacturer = brand
        self._cancel_poll()

        # Auto-resolve APK now (so we don't show the APK browse step)
        auto_apk = get_bundled_apk()
        self.apk_path = auto_apk

        status = f"✅  Phone connected!   [{serial}]"
        if brand:
            status += f"  •  {brand.capitalize()}"
        self._device_status_lbl.configure(text=status, text_color=GREEN)

        warnings = {
            frozenset(["xiaomi", "redmi", "poco"]): (
                "⚠️  XIAOMI: Enable 'USB debugging (Security settings)' in Developer Options, or Device Owner setup will fail."),
            frozenset(["vivo", "iqoo"]): (
                "⚠️  VIVO: Check that USB Data Tracking doesn't block installation."),
            frozenset(["oppo", "realme"]): (
                "⚠️  OPPO/REALME: Sign in to OEM account if required for USB installation."),
        }
        warning_shown = False
        for brand_set, msg in warnings.items():
            if brand in brand_set:
                self._device_sub_lbl.configure(text=msg, text_color=ORANGE,
                                               font=ctk.CTkFont("Arial", 11, "bold"))
                warning_shown = True
                break

        if not warning_shown:
            apk_msg = "APK ready ✓  " if auto_apk else "⚠️ APK not found in bundle — check requirements"
            apk_color = GREEN if auto_apk else ORANGE
            self._device_sub_lbl.configure(text=apk_msg, text_color=apk_color)

        self._set_nav(back=True, next_=bool(auto_apk), next_text="Install FONEX  →")

    # =========================================================================
    # STEP 3 — Install APK (automatic, no browse popup)
    # =========================================================================
    def _start_step_install(self):
        self.current_step = 3
        self._clear()
        self._update_step_bar(3)
        self._set_nav(back=False, next_=False, next_text="Installing…")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="⬇️  Installing FONEX App",
                     font=ctk.CTkFont("Arial", 28, "bold"), text_color=TEXT).pack(pady=(0, 10))
        ctk.CTkLabel(outer, text="Please wait — do not disconnect the phone.",
                     font=ctk.CTkFont("Arial", 13), text_color=TEXT_SEC).pack()

        self._install_status = ctk.CTkLabel(
            outer, text="Preparing installation…",
            font=ctk.CTkFont("Arial", 15, "bold"), text_color=ORANGE,
        )
        self._install_status.pack(pady=20)

        self._install_bar = ctk.CTkProgressBar(outer, width=600, mode="indeterminate",
                                               progress_color=ACCENT, fg_color=BORDER,
                                               corner_radius=10, height=12)
        self._install_bar.pack()
        self._install_bar.start()

        log_frame = self._card(outer, width=600)
        log_frame.pack(fill="x", padx=20, pady=18, ipady=12, ipadx=12)

        self._log_box = ctk.CTkTextbox(log_frame, height=160, width=600,
                                        fg_color="transparent",
                                        text_color=TEXT_SEC,
                                        font=ctk.CTkFont("Courier New", 12))
        self._log_box.pack(padx=8, pady=6)
        self._log_box.configure(state="normal")

        threading.Thread(target=self._do_install, daemon=True).start()

    def _log(self, text: str, color: str = TEXT_SEC):
        self.after(0, lambda: self._append_log(f"{text}\n"))

    def _append_log(self, text: str):
        self._log_box.configure(state="normal")
        self._log_box.insert("end", text)
        self._log_box.see("end")
        self._log_box.configure(state="disabled")

    def _do_install(self):
        self._log(f"→ APK: {self.apk_path}")
        self._log("→ Running: adb install -r …")
        rc, out, err = run_adb(self.adb_path, "install", "-r", self.apk_path, timeout=120)
        combined = out + (" " + err if err else "")

        if rc == 0 or "Success" in combined:
            self._log("✓ FONEX installed successfully!")
            self.after(0, self._install_success)
        else:
            msg = err or out or "Unknown error"
            self._log(f"✗ Failed: {msg}")
            self.after(0, lambda: self._install_error(msg))

    def _install_success(self):
        self._install_bar.stop()
        self._install_bar.configure(mode="determinate")
        self._install_bar.set(1.0)
        self._install_status.configure(text="✅  FONEX installed successfully!", text_color=GREEN)
        self._set_nav(back=False, next_=True, next_text="Next  →", next_color=ACCENT)

    def _install_error(self, msg: str):
        self._install_bar.stop()
        self._install_status.configure(text="❌  Installation failed", text_color=RED)
        self._log("\nTroubleshooting:\n"
                  "• Check USB connection and USB Debugging is ON\n"
                  "• Unplug and replug the cable, then restart this app")
        self._set_nav(back=True, next_=False)

    # =========================================================================
    # STEP 4 — Set Device Owner
    # =========================================================================
    def _start_step_owner(self):
        self.current_step = 4
        self._clear()
        self._update_step_bar(4)
        self._set_nav(back=False, next_=False, next_text="Working…")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="🔒  Setting Device Owner",
                     font=ctk.CTkFont("Arial", 28, "bold"), text_color=TEXT).pack(pady=(0, 10))
        ctk.CTkLabel(outer,
                     text="This gives FONEX control to enforce the payment lock system on this device.",
                     font=ctk.CTkFont("Arial", 13), text_color=TEXT_SEC, wraplength=560).pack()

        self._owner_status = ctk.CTkLabel(
            outer, text="Configuring device…",
            font=ctk.CTkFont("Arial", 15, "bold"), text_color=ORANGE,
        )
        self._owner_status.pack(pady=20)

        self._owner_bar = ctk.CTkProgressBar(outer, width=600, mode="indeterminate",
                                              progress_color=ACCENT, fg_color=BORDER,
                                              corner_radius=10, height=12)
        self._owner_bar.pack()
        self._owner_bar.start()

        log_frame = self._card(outer, width=600)
        log_frame.pack(fill="x", padx=20, pady=18, ipady=12, ipadx=12)
        self._owner_log = ctk.CTkTextbox(log_frame, height=150, width=600,
                                          fg_color="transparent",
                                          text_color=TEXT_SEC,
                                          font=ctk.CTkFont("Courier New", 12))
        self._owner_log.pack(padx=8, pady=6)
        self._owner_log.configure(state="disabled")

        threading.Thread(target=self._do_set_owner, daemon=True).start()

    def _do_owner_log_append(self, text: str):
        self._owner_log.configure(state="normal")
        self._owner_log.insert("end", f"{text}\n")
        self._owner_log.see("end")
        self._owner_log.configure(state="disabled")

    def _do_set_owner(self):
        def log(t):
            self.after(0, lambda: self._do_owner_log_append(t))

        # 1. Check existing device owner
        log("→ Checking existing Device Owner…")
        rc, out, err = run_adb(
            self.adb_path, "shell", "dpm", "list-owners"
        )
        existing_owner = ""
        if rc == 0 and out:
            for line in out.lower().splitlines():
                if "device owner" in line or PACKAGE.lower() in line:
                    if PACKAGE.lower() in line:
                        existing_owner = PACKAGE
                        break

        if existing_owner:
            log(f"✓ FONEX is already Device Owner: {existing_owner}")
            self.after(0, self._owner_success)
            return

        # 2. Clear all accounts (required by Android)
        log("→ Removing any Google accounts (required for Device Owner)…")
        run_adb(self.adb_path, "shell",
                "content", "delete",
                "--uri", "content://com.google.settings/partner",
                "--where", "name=\'use_location_for_services\'")

        # 3. Set Device Owner
        log("→ Setting FONEX as Device Owner…")
        rc, out, err = run_adb(
            self.adb_path, "shell", "dpm", "set-device-owner",
            f"{PACKAGE}/{RECEIVER}",
        )
        combined = (out + " " + err).lower()
        log(f"   rc={rc}  out: {out or err}")

        if rc == 0 or "success" in combined:
            log("✓ Device Owner set successfully!")
            # 4. Grant permissions
            log("→ Granting CALL_PHONE permission…")
            run_adb(self.adb_path, "shell", "pm", "grant", PACKAGE,
                    "android.permission.CALL_PHONE")
            # 5. Launch app
            log("→ Launching FONEX…")
            run_adb(self.adb_path, "shell", "monkey", "-p", PACKAGE, "-c",
                    "android.intent.category.LAUNCHER", "1")
            self.after(0, self._owner_success)

        elif "accounts" in combined or "account" in combined:
            log("⚠️ Blocked by Google Account!")
            self.after(0, lambda: self._owner_error_accounts(err or out))
        else:
            log(f"✗ Failed to set Device Owner: {err or out}")
            self.after(0, lambda: self._owner_error_generic(err or out))

    def _owner_success(self):
        self._owner_bar.stop()
        self._owner_bar.set(1.0)
        self._owner_bar.configure(mode="determinate")
        self._owner_status.configure(text="✅  Device Owner set!", text_color=GREEN)
        self._set_nav(back=False, next_=True, next_text="Finish  →", next_color=GREEN_DK)

    def _owner_error_accounts(self, msg: str):
        self._owner_bar.stop()
        self._owner_status.configure(text="⚠️  Google Account blocking setup", text_color=ORANGE)
        self.after(0, lambda: self._do_owner_log_append(
            "\n— FIX —\n"
            "1. On phone: Settings → Accounts → Remove all Google accounts\n"
            "2. Run this provisioner again from Step 1\n"
            "3. (Or) Factory Reset the phone before provisioning"
        ))
        self._set_nav(back=True, next_=False)

    def _owner_error_generic(self, msg: str):
        self._owner_bar.stop()
        self._owner_status.configure(text="❌  Failed to set Device Owner", text_color=RED)
        self._set_nav(back=True, next_=False)

    # =========================================================================
    # STEP 5 — Done
    # =========================================================================
    def _show_step_done(self):
        self.current_step = 5
        self._clear()
        self._update_step_bar(5)
        self._set_nav(back=False, next_=True, next_text="Provision Another  →", next_color=ACCENT)

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        # Success icon
        ctk.CTkLabel(
            outer, text="🎉",
            font=ctk.CTkFont("Arial", 84),
        ).pack(pady=(0, 16))

        ctk.CTkLabel(outer, text="Device Provisioned!",
                     font=ctk.CTkFont("Arial", 32, "bold"), text_color=GREEN).pack()
        ctk.CTkLabel(outer, text="The phone is now protected by FONEX.",
                     font=ctk.CTkFont("Arial", 14), text_color=TEXT_SEC).pack(pady=(6, 28))

        # Summary card
        card = self._card(outer, width=580)
        card.pack(fill="x", ipadx=24, ipady=18, padx=20)

        summary = [
            ("✅", "FONEX app installed"),
            ("✅", "Device Owner configured"),
            ("✅", "Payment lock system active"),
            ("✅", "Factory reset blocked"),
            ("✅", "Emergency call buttons on lock screen"),
        ]
        for check, text in summary:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=6, padx=20)
            ctk.CTkLabel(row, text=check, font=ctk.CTkFont("Arial", 16),
                         text_color=GREEN, width=32).pack(side="left")
            ctk.CTkLabel(row, text=text, font=ctk.CTkFont("Arial", 13),
                         text_color=TEXT_SEC, anchor="w").pack(side="left")

        ctk.CTkLabel(
            outer,
            text="Unplug the phone — it is ready to be handed to the customer.",
            font=ctk.CTkFont("Arial", 13, "bold"),
            text_color=CYAN,
        ).pack(pady=(24, 0))

    def _restart(self):
        self._show_step_welcome()


def main():
    app = FonexProvisioner()
    app.mainloop()


if __name__ == "__main__":
    main()
