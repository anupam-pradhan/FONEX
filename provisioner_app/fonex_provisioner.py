"""
FONEX Device Provisioner — Windows Desktop App
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

# ─── FONEX Brand Colors ────────────────────────────────────────────────────────
BG         = "#06080F"
SURFACE    = "#0E1219"
CARD       = "#141B27"
BORDER     = "#1E2A3A"
ACCENT     = "#3B82F6"
ACCENT_LT  = "#60A5FA"
ACCENT_DK  = "#1D4ED8"
PURPLE     = "#8B5CF6"
CYAN       = "#22D3EE"
GREEN      = "#22C55E"
RED        = "#EF4444"
ORANGE     = "#F59E0B"
TEXT       = "#F1F5F9"
TEXT_SEC   = "#94A3B8"
TEXT_MUTED = "#475569"

# ─── Runtime base directory ──────────────────────────────────────────────────
def _runtime_dir() -> str:
    """Returns the directory where bundled files are extracted at runtime."""
    # PyInstaller separates logic depending on --onefile vs --onedir
    if getattr(sys, "frozen", False):
        if hasattr(sys, "_MEIPASS"):  # --onefile flag puts things here
            return sys._MEIPASS
        else: # --onedir puts things right next to the executable
            return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

# ─── ADB Path ─────────────────────────────────────────────────────────────────
def get_adb_path() -> str:
    """Find ADB — checks bundled dir first, then exe folder, then PATH."""
    base_dir = _runtime_dir()
    adb_name = "adb.exe" if sys.platform == "win32" else "adb"
    
    candidates = [
        os.path.join(base_dir, "_internal", "platform-tools", adb_name), # ← PyInstaller 6 onedir
        os.path.join(base_dir, "platform-tools", adb_name),              # ← older PyInstaller onedir
        os.path.join(base_dir, "_internal", adb_name),                   
        os.path.join(base_dir, adb_name),                                
        "platform-tools/" + adb_name,                                    # ← relative CWD fallback
        adb_name,                                                        # ← system PATH
    ]
    for c in candidates:
        if not os.path.exists(c) and c != adb_name:
             continue
        try:
            r = subprocess.run([c, "version"], capture_output=True, timeout=5)
            if r.returncode == 0:
                print(f"DEBUG: Found ADB at >> {c}")
                return c
        except Exception:
            continue
    return ""

# ─── APK Path ─────────────────────────────────────────────────────────────────
def get_bundled_apk() -> str:
    """Find bundled APK — checks runtime dir first."""
    base_dir = _runtime_dir()

    candidates = [
        os.path.join(base_dir, "_internal", "fonex.apk"),      # ← PyInstaller 6 onedir
        os.path.join(base_dir, "fonex.apk"),                   # ← next to EXE
        "fonex.apk",                                           # ← relative CWD
        os.path.normpath(os.path.join(base_dir, "..", "build", "app", "outputs", "flutter-apk", "app-release.apk")) 
    ]

    for p in candidates:
        if os.path.exists(p):
            print(f"DEBUG: Found APK at >> {p}")
            return p

    return ""

# ─── App Config ───────────────────────────────────────────────────────────────
PACKAGE      = "com.roycommunication.fonex"
RECEIVER     = ".MyDeviceAdminReceiver"
ACTIVITY     = ".MainActivity"
IS_BUNDLED   = getattr(sys, "frozen", False)   # True when running as .exe
TOTAL_STEPS  = 7

# ─── Utility ─────────────────────────────────────────────────────────────────
def run_adb(adb: str, *args, timeout: int = 30) -> Tuple[int, str, str]:
    try:
        r = subprocess.run(
            [adb, *args],
            capture_output=True, text=True, timeout=timeout
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
        self.geometry("700x580")
        self.minsize(700, 580)
        self.resizable(True, True)
        self.configure(fg_color=BG)

        # Center window
        self.update_idletasks()
        x = (self.winfo_screenwidth()  - 700) // 2
        y = (self.winfo_screenheight() - 580) // 2
        self.geometry(f"+{x}+{y}")

        # State
        self.current_step  = 0  # 0 = welcome
        self.adb_path      = ""
        self.apk_path      = ""
        self._device_poll  = None
        self._device_found = False

        self._build_ui()
        self._show_step_welcome()

    # ─── UI Shell ────────────────────────────────────────────────────────────
    def _build_ui(self):
        # Top banner
        banner = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=64)
        banner.pack(fill="x")
        banner.pack_propagate(False)

        logo_lbl = ctk.CTkLabel(
            banner,
            text="F",
            font=ctk.CTkFont("Arial", 28, "bold"),
            text_color=TEXT,
            fg_color=ACCENT,
            corner_radius=20,
            width=40,
            height=40,
        )
        logo_lbl.place(x=18, rely=0.5, anchor="w")

        title_lbl = ctk.CTkLabel(
            banner,
            text="FONEX  Device Provisioner",
            font=ctk.CTkFont("Arial", 18, "bold"),
            text_color=TEXT,
        )
        title_lbl.place(x=70, rely=0.5, anchor="w")

        sub_lbl = ctk.CTkLabel(
            banner,
            text="Powered by Roy Communication",
            font=ctk.CTkFont("Arial", 11),
            text_color=TEXT_SEC,
        )
        sub_lbl.place(relx=1.0, x=-18, rely=0.5, anchor="e")

        # Step indicator bar
        self.step_bar_frame = ctk.CTkFrame(self, fg_color=CARD, corner_radius=0, height=52)
        self.step_bar_frame.pack(fill="x")
        self.step_bar_frame.pack_propagate(False)

        self.step_labels: list[ctk.CTkLabel] = []
        steps_meta = [
            "Welcome", "ADB Check", "Connect Phone",
            "APK Setup", "Installing", "Device Owner", "Done"
        ]
        for i, name in enumerate(steps_meta):
            col = ctk.CTkFrame(self.step_bar_frame, fg_color="transparent")
            col.pack(side="left", expand=True, fill="both")

            num = ctk.CTkLabel(
                col,
                text=str(i + 1),
                font=ctk.CTkFont("Arial", 11, "bold"),
                text_color=TEXT_MUTED,
                fg_color="transparent",
                width=22,
                height=22,
                corner_radius=11,
            )
            num.pack(pady=(6, 0))

            lbl = ctk.CTkLabel(
                col,
                text=name,
                font=ctk.CTkFont("Arial", 9),
                text_color=TEXT_MUTED,
            )
            lbl.pack()
            self.step_labels.append((num, lbl))

        # Separator
        sep = ctk.CTkFrame(self, fg_color=BORDER, height=1, corner_radius=0)
        sep.pack(fill="x")

        # Content area
        self.content = ctk.CTkFrame(self, fg_color=BG, corner_radius=0)
        self.content.pack(fill="both", expand=True, padx=0, pady=0)

        # Bottom bar
        self.bottom = ctk.CTkFrame(self, fg_color=SURFACE, corner_radius=0, height=68)
        self.bottom.pack(fill="x", side="bottom")
        self.bottom.pack_propagate(False)

        self.btn_back = ctk.CTkButton(
            self.bottom, text="← Back",
            width=110, height=40,
            fg_color="transparent", border_color=BORDER, border_width=1,
            text_color=TEXT_SEC, hover_color=CARD,
            command=self._go_back,
            font=ctk.CTkFont("Arial", 13),
        )
        self.btn_back.place(x=18, rely=0.5, anchor="w")

        self.btn_next = ctk.CTkButton(
            self.bottom, text="Start  →",
            width=160, height=40,
            fg_color=ACCENT, hover_color=ACCENT_DK,
            text_color=TEXT,
            command=self._go_next,
            font=ctk.CTkFont("Arial", 13, "bold"),
        )
        self.btn_next.place(relx=1.0, x=-18, rely=0.5, anchor="e")

    # ─── Step indicator sync ─────────────────────────────────────────────────
    def _update_step_bar(self, active: int):
        for i, (num, lbl) in enumerate(self.step_labels):
            if i < active:
                num.configure(text="✓", text_color=GREEN, fg_color="#0F2E1A")
                lbl.configure(text_color=GREEN)
            elif i == active:
                num.configure(text=str(i + 1), text_color=TEXT, fg_color=ACCENT)
                lbl.configure(text_color=ACCENT_LT)
            else:
                num.configure(text=str(i + 1), text_color=TEXT_MUTED, fg_color="transparent")
                lbl.configure(text_color=TEXT_MUTED)

    # ─── Clear content ────────────────────────────────────────────────────────
    def _clear(self):
        for w in self.content.winfo_children():
            w.destroy()

    # ─── Navigation ──────────────────────────────────────────────────────────
    def _go_next(self):
        self._cancel_poll()
        step_map = {
            0: self._show_step_adb,
            1: self._start_step_device,
            2: self._show_step_apk,   # auto-skipped when APK is bundled
            3: self._start_step_install,
            4: self._start_step_owner,
            5: self._show_step_done,
        }
        if self.current_step in step_map:
            step_map[self.current_step]()

    def _go_back(self):
        self._cancel_poll()
        # When bundled, skip APK step on back navigation too
        step_map = {
            1: self._show_step_welcome,
            2: self._show_step_adb,
            3: self._start_step_device if IS_BUNDLED else self._show_step_apk,
            4: self._show_step_apk if not IS_BUNDLED else self._start_step_device,
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
            fg_color=next_color,
            hover_color=ACCENT_DK if next_color == ACCENT else next_color,
        )

    # =========================================================================
    # STEP 0 — Welcome
    # =========================================================================
    def _show_step_welcome(self):
        self.current_step = 0
        self._clear()
        self._update_step_bar(0)
        self._set_nav(back=False, next_text="Start  →")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        # Big logo
        logo = ctk.CTkLabel(
            outer, text="F",
            font=ctk.CTkFont("Arial", 64, "bold"),
            text_color=TEXT,
            fg_color=ACCENT, corner_radius=40,
            width=100, height=100,
        )
        logo.pack(pady=(0, 20))

        ctk.CTkLabel(
            outer, text="FONEX Device Provisioner",
            font=ctk.CTkFont("Arial", 26, "bold"),
            text_color=TEXT,
        ).pack()

        ctk.CTkLabel(
            outer, text="Powered by Roy Communication",
            font=ctk.CTkFont("Arial", 13),
            text_color=TEXT_SEC,
        ).pack(pady=(4, 24))

        # Info card
        card = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=14,
                            border_width=1, border_color=BORDER)
        card.pack(fill="x", ipadx=18, ipady=14, padx=20)

        steps_info = [
            ("🔧", "ADB Tools",    "Automatically verified — no setup needed"),
            ("📱", "Connect Phone", "Plug in via USB and follow the prompts"),
            ("📦", "Install App",   "FONEX APK installed automatically"),
            ("🔒", "Lock Device",   "Sets Device Owner to protect the phone"),
        ]
        for emoji, title, desc in steps_info:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=5, padx=10)
            ctk.CTkLabel(row, text=emoji, font=ctk.CTkFont("Arial", 18),
                         width=32, text_color=TEXT).pack(side="left")
            col = ctk.CTkFrame(row, fg_color="transparent")
            col.pack(side="left", padx=10)
            ctk.CTkLabel(col, text=title, font=ctk.CTkFont("Arial", 13, "bold"),
                         text_color=TEXT, anchor="w").pack(anchor="w")
            ctk.CTkLabel(col, text=desc, font=ctk.CTkFont("Arial", 11),
                         text_color=TEXT_SEC, anchor="w").pack(anchor="w")

        ctk.CTkLabel(
            outer, text="This will take about 2–3 minutes. Click Start when ready.",
            font=ctk.CTkFont("Arial", 11),
            text_color=TEXT_MUTED,
        ).pack(pady=(18, 0))

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

        ctk.CTkLabel(outer, text="🔧  Checking ADB Tools",
                     font=ctk.CTkFont("Arial", 22, "bold"), text_color=TEXT).pack(pady=(0, 6))
        ctk.CTkLabel(outer, text="ADB (Android Debug Bridge) is required to talk to the phone.",
                     font=ctk.CTkFont("Arial", 12), text_color=TEXT_SEC).pack()

        self._adb_status_lbl = ctk.CTkLabel(
            outer, text="🔍  Searching for ADB…",
            font=ctk.CTkFont("Arial", 13, "bold"),
            text_color=ORANGE,
        )
        self._adb_status_lbl.pack(pady=22)

        self._adb_card = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=14,
                                       border_width=1, border_color=BORDER, width=480)
        self._adb_card.pack(padx=20, fill="x", ipady=10, ipadx=14)
        self._adb_card_inner = ctk.CTkFrame(self._adb_card, fg_color="transparent")
        self._adb_card_inner.pack(fill="x", padx=14, pady=8)

        self.after(400, self._do_adb_check)

    def _do_adb_check(self):
        adb = get_adb_path()
        self.adb_path = adb

        for w in self._adb_card_inner.winfo_children():
            w.destroy()

        if adb:
            rc, out, _ = run_adb(adb, "version")
            ver = out.split("\n")[0] if out else "unknown"
            self._adb_status_lbl.configure(text="✅  ADB found — all good!", text_color=GREEN)
            ctk.CTkLabel(self._adb_card_inner, text=f"  ✓  {ver}",
                         font=ctk.CTkFont("Arial", 12), text_color=GREEN,
                         anchor="w").pack(anchor="w")
            ctk.CTkLabel(self._adb_card_inner, text=f"  Path: {adb}",
                         font=ctk.CTkFont("Arial", 11), text_color=TEXT_MUTED,
                         anchor="w").pack(anchor="w")
            self._set_nav(back=True, next_=True, next_text="Next  →")
        else:
            self._adb_status_lbl.configure(text="❌  ADB not found", text_color=RED)
            ctk.CTkLabel(self._adb_card_inner,
                         text="ADB was not found on this computer.",
                         font=ctk.CTkFont("Arial", 12, "bold"),
                         text_color=RED, anchor="w").pack(anchor="w", pady=(4, 2))
            ctk.CTkLabel(self._adb_card_inner,
                         text="To fix: Place adb.exe in the same folder as this app\n"
                              "OR install Android Platform Tools and add to PATH.",
                         font=ctk.CTkFont("Arial", 11),
                         text_color=TEXT_SEC, anchor="w", justify="left").pack(anchor="w")

            dl_btn = ctk.CTkButton(
                self._adb_card_inner,
                text="📥  Download Platform Tools (opens browser)",
                fg_color="transparent", border_color=ACCENT, border_width=1,
                text_color=ACCENT_LT, hover_color=CARD,
                command=lambda: webbrowser.open(
                    "https://developer.android.com/studio/releases/platform-tools"),
            )
            dl_btn.pack(anchor="w", pady=(10, 2))

            retry_btn = ctk.CTkButton(
                self._adb_card_inner, text="🔄  Retry",
                fg_color=ACCENT, hover_color=ACCENT_DK, text_color=TEXT,
                command=self._show_step_adb,
            )
            retry_btn.pack(anchor="w", pady=(6, 2))
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
        self._device_manufacturer = ""

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="📱  Connect the Phone",
                     font=ctk.CTkFont("Arial", 22, "bold"), text_color=TEXT).pack(pady=(0, 6))

        # Instructions card
        card = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=14,
                             border_width=1, border_color=BORDER)
        card.pack(fill="x", ipadx=14, ipady=10, padx=20)

        steps_list = [
            ("1", "Connect the phone to this computer via USB cable."),
            ("2", "On the phone: go to  Settings → About Phone"),
            ("3", "Tap  'Build Number'  7 times quickly to enable Developer Options."),
            ("4", "Go to  Settings → Developer Options → Enable USB Debugging."),
            ("5", "A popup appears on the phone — tap  'Allow'."),
        ]
        for num, txt in steps_list:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=3, padx=12)
            ctk.CTkLabel(row, text=num,
                         font=ctk.CTkFont("Arial", 11, "bold"),
                         fg_color=ACCENT, corner_radius=10,
                         width=22, height=22, text_color=TEXT).pack(side="left")
            ctk.CTkLabel(row, text=f"   {txt}",
                         font=ctk.CTkFont("Arial", 12), text_color=TEXT_SEC,
                         anchor="w", justify="left", wraplength=400).pack(side="left", anchor="w")

        # Status indicator
        self._device_status_lbl = ctk.CTkLabel(
            outer,
            text="⏳  Waiting for device…",
            font=ctk.CTkFont("Arial", 14, "bold"),
            text_color=ORANGE,
        )
        self._device_status_lbl.pack(pady=20)

        self._device_sub_lbl = ctk.CTkLabel(
            outer,
            text="Checking every 2 seconds…",
            font=ctk.CTkFont("Arial", 11),
            text_color=TEXT_MUTED,
        )
        self._device_sub_lbl.pack()

        # Start polling
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
                # Get device manufacturer for special handling
                brand = ""
                rc_prop, out_prop, _ = run_adb(self.adb_path, "-s", serial, "shell", "getprop", "ro.product.manufacturer")
                if rc_prop == 0 and out_prop:
                    brand = out_prop.strip().lower()
                self.after(0, lambda: self._on_device_found(serial, brand))
            elif unauthorized:
                self.after(0, lambda: self._device_status_lbl.configure(
                    text="⚠️  Phone connected but not authorized",
                    text_color=ORANGE))
                self.after(0, lambda: self._device_sub_lbl.configure(
                    text="Please tap 'Allow' on the phone's USB Debugging prompt."))
                self._device_poll = self.after(2500, self._poll_device)
            else:
                self._device_poll = self.after(2500, self._poll_device)

        threading.Thread(target=check, daemon=True).start()

    def _on_device_found(self, serial: str, brand: str):
        self._device_found = True
        self._device_manufacturer = brand
        self._cancel_poll()

        status_text = f"✅  Phone connected!  ({serial})"
        if brand:
             status_text += f" [{brand.capitalize()}]"

        self._device_status_lbl.configure(text=status_text, text_color=GREEN)

        if brand in ["xiaomi", "redmi", "poco"]:
            self._device_sub_lbl.configure(
                text="⚠️ XIAOMI DETECTED: You MUST enable 'USB debugging (Security settings)' in Developer Options, or setup will fail.",
                text_color=ORANGE,
                font=ctk.CTkFont("Arial", 12, "bold"))
        elif brand in ["vivo", "iqoo"]:
             self._device_sub_lbl.configure(
                text="⚠️ VIVO DETECTED: Ensure 'USB Data Tracking' or similar security options don't block app installation.",
                text_color=ORANGE)
        elif brand in ["oppo", "realme"]:
            self._device_sub_lbl.configure(
                text="⚠️ OPPO DETECTED: Ensure you are signed into the OEM account if required for USB app installation.",
                text_color=ORANGE)
        else:
            self._device_sub_lbl.configure(
                text="Great — the phone is ready. Click Next to continue.",
                text_color=TEXT_SEC)

        self._set_nav(back=True, next_=True, next_text="Next  →")

    # =========================================================================
    # STEP 3 — APK Setup
    # When bundled as EXE, this step auto-detects and skips to install.
    # =========================================================================
    def _show_step_apk(self):
        self.current_step = 3

        # Auto-detect bundled or nearby APK
        auto_apk = get_bundled_apk()

        # If running as bundled EXE and APK found — skip this screen entirely
        if IS_BUNDLED and auto_apk:
            self.apk_path = auto_apk
            self._start_step_install()
            return

        self._clear()
        self._update_step_bar(3)

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="📦  FONEX APK",
                     font=ctk.CTkFont("Arial", 22, "bold"), text_color=TEXT).pack(pady=(0, 6))
        ctk.CTkLabel(outer, text="The FONEX app file (.apk) will be installed on the phone.",
                     font=ctk.CTkFont("Arial", 12), text_color=TEXT_SEC).pack(pady=(0, 16))

        status_text = "✅  APK found:" if auto_apk else "⚠️  APK not found — please select it manually."
        status_color = GREEN if auto_apk else ORANGE
        self._apk_status_lbl = ctk.CTkLabel(
            outer, text=status_text,
            font=ctk.CTkFont("Arial", 13, "bold"),
            text_color=status_color,
        )
        self._apk_status_lbl.pack(pady=(0, 8))

        # Path display card
        path_card = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=10,
                                  border_width=1, border_color=BORDER)
        path_card.pack(fill="x", padx=20, ipady=6, ipadx=10)
        self._apk_path_lbl = ctk.CTkLabel(
            path_card,
            text=auto_apk if auto_apk else "No APK found — use Browse below",
            font=ctk.CTkFont("Arial", 11),
            text_color=TEXT_SEC if auto_apk else TEXT_MUTED,
            wraplength=450, anchor="w",
        )
        self._apk_path_lbl.pack(padx=10, pady=6, anchor="w")

        # Browse button
        ctk.CTkButton(
            outer, text="📂  Browse for APK file…",
            fg_color="transparent", border_color=BORDER, border_width=1,
            text_color=TEXT_SEC, hover_color=CARD,
            command=self._browse_apk,
        ).pack(pady=(14, 0))

        self.apk_path = auto_apk
        self._set_nav(back=True, next_=bool(auto_apk), next_text="Install  →", next_color=ACCENT)

    def _browse_apk(self):
        path = filedialog.askopenfilename(
            title="Select FONEX APK",
            filetypes=[("Android APK", "*.apk"), ("All Files", "*.*")],
        )
        if path:
            self.apk_path = path
            self._apk_path_lbl.configure(text=path, text_color=TEXT_SEC)
            self._apk_status_lbl.configure(text="✅  APK selected:", text_color=GREEN)
            self._set_nav(back=True, next_=True, next_text="Install  →", next_color=ACCENT)

    # =========================================================================
    # STEP 4 — Install APK
    # =========================================================================
    def _start_step_install(self):
        self.current_step = 4
        self._clear()
        self._update_step_bar(4)
        self._set_nav(back=False, next_=False, next_text="Installing…")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="⬇️  Installing FONEX",
                     font=ctk.CTkFont("Arial", 22, "bold"), text_color=TEXT).pack(pady=(0, 8))

        self._install_status = ctk.CTkLabel(
            outer, text="Preparing installation…",
            font=ctk.CTkFont("Arial", 13), text_color=ORANGE,
        )
        self._install_status.pack(pady=(0, 12))

        self._install_bar = ctk.CTkProgressBar(outer, width=480, mode="indeterminate",
                                                progress_color=ACCENT, fg_color=BORDER)
        self._install_bar.pack()
        self._install_bar.start()

        # Log output
        log_frame = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=10,
                                  border_width=1, border_color=BORDER)
        log_frame.pack(fill="x", padx=20, pady=14, ipady=8, ipadx=8)

        self._log_box = ctk.CTkTextbox(log_frame, height=140, width=480,
                                        fg_color="transparent",
                                        text_color=TEXT_SEC,
                                        font=ctk.CTkFont("Courier New", 11))
        self._log_box.pack(padx=6, pady=4)
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
        self._log("→ Starting adb install…")
        rc, out, err = run_adb(self.adb_path, "install", "-r", self.apk_path, timeout=120)
        combined = out + (" " + err if err else "")

        if rc == 0 or "Success" in combined:
            self._log("✓ FONEX installed successfully!")
            self.after(0, self._install_success)
        else:
            msg = err or out or "Unknown error"
            self._log(f"✗ Installation failed: {msg}")
            self.after(0, lambda: self._install_error(msg))

    def _install_success(self):
        self._install_bar.stop()
        self._install_bar.configure(mode="determinate")
        self._install_bar.set(1.0)
        self._install_status.configure(
            text="✅  FONEX installed successfully!", text_color=GREEN)
        self._set_nav(back=False, next_=True, next_text="Next  →", next_color=ACCENT)

    def _install_error(self, msg: str):
        self._install_bar.stop()
        self._install_status.configure(text="❌  Installation failed", text_color=RED)
        self._log(f"\nWhat to do:\n"
                  f"• Make sure the phone is connected and USB Debugging is ON.\n"
                  f"• Unplug and replug the USB cable, then retry.")
        self._set_nav(back=True, next_=False)

    # =========================================================================
    # STEP 5 — Set Device Owner
    # =========================================================================
    def _start_step_owner(self):
        self.current_step = 5
        self._clear()
        self._update_step_bar(5)
        self._set_nav(back=False, next_=False, next_text="Working…")

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(outer, text="🔒  Setting Device Owner",
                     font=ctk.CTkFont("Arial", 22, "bold"), text_color=TEXT).pack(pady=(0, 8))
        ctk.CTkLabel(outer, text="This gives FONEX control to lock the device after the payment period.",
                     font=ctk.CTkFont("Arial", 12), text_color=TEXT_SEC,
                     wraplength=460).pack()

        self._owner_status = ctk.CTkLabel(
            outer, text="Configuring device…",
            font=ctk.CTkFont("Arial", 13, "bold"), text_color=ORANGE,
        )
        self._owner_status.pack(pady=16)

        self._owner_bar = ctk.CTkProgressBar(outer, width=480, mode="indeterminate",
                                              progress_color=ACCENT, fg_color=BORDER)
        self._owner_bar.pack()
        self._owner_bar.start()

        log_frame = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=10,
                                  border_width=1, border_color=BORDER)
        log_frame.pack(fill="x", padx=20, pady=14, ipady=8, ipadx=8)
        self._owner_log = ctk.CTkTextbox(log_frame, height=130, width=480,
                                          fg_color="transparent",
                                          text_color=TEXT_SEC,
                                          font=ctk.CTkFont("Courier New", 11))
        self._owner_log.pack(padx=6, pady=4)
        self._owner_log.configure(state="disabled")

        threading.Thread(target=self._do_set_owner, daemon=True).start()

    def _owner_log_append(self, text: str):
        self.after(0, lambda: self._do_owner_log_append(f"{text}\n"))

    def _do_owner_log_append(self, text: str):
        self._owner_log.configure(state="normal")
        self._owner_log.insert("end", text)
        self._owner_log.see("end")
        self._owner_log.configure(state="disabled")

    def _do_set_owner(self):
        component = f"{PACKAGE}/{RECEIVER}"
        self._owner_log_append(f"→ Running: dpm set-device-owner {component}")
        rc, out, err = run_adb(self.adb_path, "shell", "dpm", "set-device-owner", component)
        combined = (out + " " + err).strip()

        if "Success" in combined or "success" in combined:
            self._owner_log_append("✓ Device Owner set successfully!")
            self.after(0, self._owner_success)
        elif "already" in combined.lower():
            self._owner_log_append("✓ Device Owner was already set — all good!")
            self.after(0, self._owner_success)
        elif "account" in combined.lower() or "user" in combined.lower():
            self._owner_log_append("✗ Error: Google accounts found on phone.")
            self.after(0, lambda: self._owner_error_accounts(combined))
        else:
            self._owner_log_append(f"✗ Error: {combined}")
            self.after(0, lambda: self._owner_error_generic(combined))

    def _owner_success(self):
        self._owner_bar.stop()
        self._owner_bar.configure(mode="determinate")
        self._owner_bar.set(1.0)
        self._owner_status.configure(text="✅  Device Owner set!", text_color=GREEN)
        self._set_nav(back=False, next_=True, next_text="Finish  →", next_color=GREEN)

    def _owner_error_accounts(self, msg: str):
        self._owner_bar.stop()
        self._owner_status.configure(text="❌  Google Account Found on Phone", text_color=RED)
        self._do_owner_log_append(
            "\n⚠️  The phone has a Google account logged in.\n"
            "    Device Owner CANNOT be set if any account exists.\n\n"
            "How to fix:\n"
            "  1. On the phone: Settings → System → Reset\n"
            "     → Erase All Data (Factory Reset)\n"
            "  2. During first setup, SKIP adding a Google account.\n"
            "  3. Come back to this app and start again.\n"
        )
        self._set_nav(back=True, next_=False)

    def _owner_error_generic(self, msg: str):
        self._owner_bar.stop()
        self._owner_status.configure(text="❌  Failed to set Device Owner", text_color=RED)
        self._do_owner_log_append(
            "\nWhat to do:\n"
            "  • Make sure the phone is freshly set up (no Google account).\n"
            "  • Try unplugging and replugging the USB cable.\n"
            "  • Restart the phone and try again.\n"
        )
        self._set_nav(back=True, next_=False)

    # =========================================================================
    # STEP 6 — Done / Success
    # =========================================================================
    def _show_step_done(self):
        self.current_step = 6
        self._clear()
        self._update_step_bar(6)
        self._set_nav(back=False, next_=False)

        # Hide bottom buttons for done screen
        self.bottom.pack_forget()

        outer = ctk.CTkFrame(self.content, fg_color="transparent")
        outer.place(relx=0.5, rely=0.5, anchor="center")

        # Big success icon
        ctk.CTkLabel(
            outer, text="✅",
            font=ctk.CTkFont("Arial", 72),
            text_color=GREEN,
        ).pack(pady=(0, 12))

        ctk.CTkLabel(
            outer, text="Setup Complete!",
            font=ctk.CTkFont("Arial", 28, "bold"),
            text_color=TEXT,
        ).pack()

        ctk.CTkLabel(
            outer, text="The phone is now protected by FONEX.",
            font=ctk.CTkFont("Arial", 14),
            text_color=TEXT_SEC,
        ).pack(pady=(6, 24))

        # Action cards
        card = ctk.CTkFrame(outer, fg_color=CARD, corner_radius=14,
                             border_width=1, border_color=BORDER)
        card.pack(fill="x", padx=20, ipadx=18, ipady=18)

        actions = [
            ("🔌", "Disconnect the USB cable from the phone."),
            ("📱", "Hand the device to the customer."),
            ("📅", "The device will lock automatically after 30 days."),
            ("🏪", "Customer visits your store to renew (unlocks with PIN)."),
        ]
        for emoji, text in actions:
            row = ctk.CTkFrame(card, fg_color="transparent")
            row.pack(fill="x", pady=5, padx=12)
            ctk.CTkLabel(row, text=emoji, font=ctk.CTkFont("Arial", 16),
                         width=28, text_color=TEXT).pack(side="left")
            ctk.CTkLabel(row, text=f"  {text}",
                         font=ctk.CTkFont("Arial", 12),
                         text_color=TEXT_SEC, anchor="w").pack(side="left", anchor="w")

        # Button row
        btn_row = ctk.CTkFrame(outer, fg_color="transparent")
        btn_row.pack(pady=24)

        # Launch app button
        launch_btn = ctk.CTkButton(
            btn_row, text="▶  Launch App on Device",
            fg_color=ACCENT, hover_color=ACCENT_DK, text_color=TEXT,
            width=210, height=44,
            font=ctk.CTkFont("Arial", 13, "bold"),
            command=self._launch_app,
        )
        launch_btn.pack(side="left", padx=8)

        # Provision another
        another_btn = ctk.CTkButton(
            btn_row, text="📱  Provision Another Device",
            fg_color="transparent", border_color=BORDER, border_width=1,
            text_color=TEXT_SEC, hover_color=CARD,
            width=210, height=44,
            font=ctk.CTkFont("Arial", 13),
            command=self._restart,
        )
        another_btn.pack(side="left", padx=8)

        ctk.CTkLabel(
            outer, text="Roy Communication • FONEX v1.0.0",
            font=ctk.CTkFont("Arial", 10),
            text_color=TEXT_MUTED,
        ).pack()

    def _launch_app(self):
        component = f"{PACKAGE}/{ACTIVITY}"
        run_adb(self.adb_path, "shell", "am", "start", "-n", component)
        messagebox.showinfo("FONEX", "App launched on the device! ✓")

    def _restart(self):
        self.bottom.pack(fill="x", side="bottom")
        self._show_step_welcome()

# ─── Entry ────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app = FonexProvisioner()
    app.mainloop()
