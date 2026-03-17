# FONEX Private Signing Note

## Keystore

- Keystore file: `/Users/anupampradhan/fonex-release.jks`
- Alias: `fonex`
- Store password: `Fonex@123`
- Key password: `Fonex@123`

## Android key.properties

```properties
storeFile=/Users/anupampradhan/fonex-release.jks
storePassword=Fonex@123
keyAlias=fonex
keyPassword=Fonex@123
```

## Build + Install Commands

```bash
flutter clean
flutter pub get
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

```

## Device Owner Commands

```bash
adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver
adb shell dpm list-owners



```

## run apk export apk

# 1) Build signed release APK

flutter build apk --release

# 2) Install release APK

adb install -r build/app/outputs/flutter-apk/app-release.apk

# 3) Set Device Owner (phone must be factory-reset + no Google account)

adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver

# 4) Verify owner

adb shell dpm list-owners

# 5) Launch app

adb shell am start -n com.roycommunication.fonex/.MainActivity

## Important

- This file contains sensitive secrets.
- Keep this file local only and never commit it to git.
