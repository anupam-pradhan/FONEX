# FONEX Device Provisioner — Shop Owner Guide

## What this app does

**FONEX Provisioner** sets up a new Android phone for your FONEX device-lock program.
After setup, the phone will automatically lock after 30 days if the customer hasn't renewed.

---

## How to use (3 easy steps)

### Step 1 — Get the app ready

Place all these files in the **same folder** on your Windows PC:

```
📁  FONEX_Provisioner/
    ├── FONEX_Provisioner.exe       ← Double-click this
    ├── adb.exe                     ← Required (see below)
    ├── AdbWinApi.dll               ← Required (included with adb)
    ├── AdbWinUsbApi.dll            ← Required (included with adb)
    └── fonex.apk                   ← The FONEX app file
```

**Where to get `adb.exe`:**

1. Download: https://developer.android.com/studio/releases/platform-tools
2. Extract the ZIP
3. Copy `adb.exe`, `AdbWinApi.dll`, `AdbWinUsbApi.dll` into the same folder

---

### Step 2 — Prepare the phone

> **⚠️ The phone MUST be factory reset with NO Google account**

1. Factory reset the phone (Settings → System → Reset → Factory Reset)
2. During setup, **skip** or **Don't Add Account** — do NOT sign in to Google
3. Connect the phone to your PC via USB cable
4. Enable **USB Debugging**:
   - Settings → About Phone → Tap **Build Number** 7 times
   - Settings → Developer Options → **USB Debugging → ON**
5. On the phone, tap **Allow** when the USB permission popup appears

---

### Step 3 — Run the provisioner

1. **Double-click** `FONEX_Provisioner.exe`
2. Follow the on-screen steps — the app guides you through everything
3. When it says **"Setup Complete!"**, disconnect the USB and hand the phone to the customer

---

## If something goes wrong

| Error                  | Fix                                                     |
| ---------------------- | ------------------------------------------------------- |
| "ADB not found"        | Make sure `adb.exe` is in the same folder as the `.exe` |
| "No device connected"  | Enable USB Debugging on the phone and tap Allow         |
| "Google account found" | Factory reset the phone and skip adding Google account  |
| "Device Owner failed"  | Restart the phone, reconnect, and try again             |

---

## FAQ

**Q: How long does it take?**  
A: About 2–3 minutes per phone.

**Q: What happens after 30 days?**  
A: The phone screen shows a lock message. The customer brings it to your store, you enter the PIN, and reset the 30-day timer.

**Q: What's the default PIN?**  
A: `1234` — you can change it in the FONEX app settings after unlocking.

**Q: Can the customer bypass the lock?**  
A: No. FONEX uses Android's Device Owner mode — the lock cannot be removed without the PIN or a factory reset (which erases all data).

---

_FONEX v1.0.0 — Powered by Roy Communication_
