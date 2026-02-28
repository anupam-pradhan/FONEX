# FONEX

Android Device Owner lock-control app for financed devices.

FONEX runs as a Device Owner app, applies lock policies locally, syncs with backend check-ins, listens to Supabase Realtime commands (`LOCK`/`UNLOCK`), and sends command ACKs to backend.

## What It Does

- Enforces EMI-based device protection with Device Owner policies.
- Locks/unlocks locally and remotely.
- Blocks sensitive actions while unpaid (factory reset, uninstall, etc.).
- Uses backend check-in + Supabase Realtime for command/control.
- Retries failed check-ins and ACKs when offline.
- Provides support tools: logs export, recovery actions, anti-kill assistant, reminder settings.

## Key Features

- Device Owner policy enforcement via `DevicePolicyManager`
- Lock Task mode + immersive lock UI
- Realtime command listener with strict device-id/hash matching
- ACK delivery with retries, offline queue, diagnostics
- Offline sync queue for check-in payloads
- SIM-absent lock grace logic
- Local bilingual (BN/EN) reminder engine
- Foreground keep-alive service + WorkManager watchdog
- Recovery actions screen:
  - Reconnect realtime
  - Resync state
  - Clear stale lock flag
  - 30-minute support unlock window (PIN protected)
- Audit log export (app logs + realtime diagnostics + queue status)
- Anti-kill setup assistant (OEM guidance)
- Google account create/add shortcuts and backup status/settings shortcuts

## Architecture

### Flutter layer

- [`lib/main.dart`](lib/main.dart)
  - UI, timers, lock flow, server check-in flow, realtime command handling
- [`lib/config.dart`](lib/config.dart)
  - Runtime configuration constants
- [`lib/services/realtime_command_service.dart`](lib/services/realtime_command_service.dart)
  - Supabase realtime subscription, command filtering, ACK logic, reconnect logic, ACK queue
- [`lib/services/sync_service.dart`](lib/services/sync_service.dart)
  - Check-in API client, retry queue processing
- [`lib/services/device_state_manager.dart`](lib/services/device_state_manager.dart)
  - State sync wrapper for native lock/paid state
- [`lib/services/app_logger.dart`](lib/services/app_logger.dart)
  - In-app bounded log buffer
- [`lib/services/crash_reporter.dart`](lib/services/crash_reporter.dart)
  - Local crash/non-fatal capture

### Native Android layer

- [`MainActivity.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/MainActivity.kt)
  - MethodChannel bridge, wallpaper generation, notification helpers, settings intents
- [`DeviceLockManager.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/DeviceLockManager.kt)
  - Device Owner restriction/lock policy engine
- [`BootReceiver.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/BootReceiver.kt)
  - Boot/package-replaced restoration
- [`KeepAliveService.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/KeepAliveService.kt)
  - Foreground keep-alive service
- [`KeepAliveWatchdogWorker.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/KeepAliveWatchdogWorker.kt)
  - 15-min watchdog to revive keep-alive service
- [`ProvisioningActivity.kt`](android/app/src/main/kotlin/com/roycommunication/fonex/ProvisioningActivity.kt)
  - Managed provisioning callbacks

## Command and ACK Flow

1. App checks in to backend (`POST {serverBaseUrl}/checkin`).
2. Backend returns status/action (`lock`, `unlock`, `extend`, `paid`, `none`) and payment fields.
3. App subscribes to Supabase `public.device_commands` insert events.
4. App only accepts commands with exact `device_id` or `device_hash` match.
5. On `LOCK`/`UNLOCK`:
   - Execute native lock/unlock
   - Log execution result
   - Send ACK to backend endpoint (`/api/device-ack`)
6. If ACK fails:
   - Retry with exponential backoff
   - Store pending ACK locally
   - Retry later automatically

## Backend Contract (Current App Behavior)

### Check-in

- Endpoint: `POST {FonexConfig.serverBaseUrl}/checkin`
- Typical request fields:
  - `device_hash`
  - `device_id`
  - `imei`
  - `battery`
  - `last_seen`
  - `is_locked`

Typical response fields used by app:

- Payment/status:
  - `is_paid_in_full` or `paid_in_full` or `payment_status`
  - `is_locked` / `locked` / `status`
- Tenure and remaining:
  - `days` / `tenure`
  - `days_remaining`
- Realtime identity:
  - `device_id` or `id`
- Action:
  - `action`: `lock`, `unlock`, `extend`, `extend_days`, `paid_in_full`, `paid`, `none`

### Realtime commands

- Supabase table: `public.device_commands`
- Event: `INSERT`
- Fields parsed:
  - `id` (or `command_id` / `commandId`)
  - `command` (`LOCK` / `UNLOCK`)
  - `device_id`
  - `device_hash`

### ACK

- Endpoint: `POST /api/device-ack` (host derived from `serverBaseUrl`)
- Header: `x-device-secret: <DEVICE_SECRET>`
- Payload sent:
  - `commandId`
  - `device_id`
  - `command`
  - `status: executed`
  - `executed_at` (UTC ISO)

## Device Owner Provisioning

Device Owner must be set on a fresh/factory-reset device (no accounts) for full policy control.

### Option A: Script

Use:

```bash
./provision_device.sh
```

Script installs APK and runs:

```bash
adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver
```

### Option B: Manual

1. Build/install app.
2. On clean device with USB debugging enabled:

```bash
adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver
```

3. Verify:

```bash
adb shell dpm list-owners
```

## Build and Run

### Prerequisites

- Flutter SDK compatible with `sdk: ^3.10.7`
- Android SDK + ADB
- Java 17 (project compile settings use Java 17)

### Install deps

```bash
flutter pub get
```

### Run

```bash
flutter run
```

### Debug APK

```bash
flutter build apk --debug
```

### Release APK

```bash
flutter build apk --release
```

Output path:

- `build/app/outputs/flutter-apk/app-release.apk`

## Configuration

Edit [`lib/config.dart`](lib/config.dart):

- `serverBaseUrl`
- `storeName`
- `supportPhone1`, `supportPhone2`
- lock windows and app constants

Also pass runtime defines in production:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `DEVICE_SECRET`

Example:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key \
  --dart-define=DEVICE_SECRET=your_device_secret
```

## Important Production Notes

1. Release signing is currently debug keystore in Gradle. Replace before store release.
2. `lib/config.dart` contains fallback defaults for Supabase key and device secret. Override with `--dart-define` for production.
3. This app is Android-specific (native Device Owner APIs).
4. Foreground keep-alive notification is expected behavior.

## Debugging

### Live logs

```bash
adb logcat | grep -Ei "I flutter|Realtime|LOCK execution|UNLOCK execution|Sending ACK|ACK response|ACK success|ACK failed|DeviceLockManager"
```

### Common checks

- Device owner state:

```bash
adb shell dpm list-owners
```

- Launch app:

```bash
adb shell am start -n com.roycommunication.fonex/.MainActivity
```

### In-app diagnostics

- Settings -> Background Health Monitor
- Settings -> Recovery Actions
- Settings -> Export Audit Log
- Debug Terminal screen (in-app logs and runtime stats)

## Tests and Quality

### Analyze

```bash
flutter analyze
```

### Tests

```bash
flutter test -r compact
```

Current tests are in:

- [`test/services/reminder_settings_test.dart`](test/services/reminder_settings_test.dart)
- [`test/services/app_logger_test.dart`](test/services/app_logger_test.dart)
- [`test/services/realtime_models_test.dart`](test/services/realtime_models_test.dart)

## Repo Structure

```text
FONEX/
├── lib/
│   ├── main.dart
│   ├── config.dart
│   └── services/
├── android/app/src/main/kotlin/com/roycommunication/fonex/
├── provision_device.sh
├── build_and_deploy.sh
├── check_device_hash.sh
├── provisioner_app/
└── test/
```

## Legacy Note

[`lib/services/supabase_command_listener.dart`](lib/services/supabase_command_listener.dart) is a legacy listener and is not used by current command flow. Current flow uses `RealtimeCommandService`.

## License

Proprietary internal project.
