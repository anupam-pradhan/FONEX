# FONEX - Device Control System

**FONEX** is a production-ready Android device financing and lock management system powered by Roy Communication. It automatically locks devices if EMI payments are not completed, with 100% server-side accuracy and control.

## 🚀 Features

- ✅ **Automatic Device Locking** - Locks after 30 days if EMI not paid
- ✅ **Server-Side Control** - Remotely lock/unlock, extend EMI, mark as paid
- ✅ **Factory Reset Blocking** - Prevents factory reset until EMI is paid
- ✅ **App Uninstall Prevention** - Cannot uninstall while EMI is pending
- ✅ **SIM Detection** - Locks after 7 days without SIM card
- ✅ **Wallpaper with Store Info** - Displays store name and EMI status
- ✅ **Connection Status** - Real-time server connection monitoring
- ✅ **Emergency Contacts** - Prominent support numbers on lock screen
- ✅ **Performance Optimized** - No phone hanging or lag
- ✅ **Modern UI** - Beautiful glassmorphism design

## 📋 Requirements

### For Development
- Flutter SDK 3.10.7+
- Android Studio
- Android SDK (API 21+)
- ADB Tools (for provisioning)

### For Backend
- Node.js 18+
- Database: Supabase/Neon (PostgreSQL) or MongoDB Atlas
- Hosting: Vercel (free tier)

## 🛠️ Quick Start

### 1. Configure App

Edit `lib/config.dart`:

```dart
// Update these values
static const String storeName = 'Your Store Name';
static const String supportPhone1 = '+91XXXXXXXXXX';
static const String supportPhone2 = '+91XXXXXXXXXX';
static const String serverBaseUrl = 'https://your-backend.vercel.app/api/v1/devices';
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Build App

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release
```

### 4. Provision Device

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for detailed provisioning instructions.

## 📁 Project Structure

```
FONEX/
├── lib/
│   ├── main.dart          # Main app code
│   └── config.dart        # Configuration file
├── android/
│   └── app/
│       └── src/main/
│           ├── kotlin/    # Native Android code
│           └── res/        # Resources
├── provisioner_app/        # Device provisioning tool
├── backend_prompt.md       # Backend requirements
├── SETUP_GUIDE.md          # Detailed setup guide
└── MISSING_REQUIREMENTS.md # Missing items checklist
```

## 🔧 Configuration

All configuration is in `lib/config.dart`:

- **Store Information**: Name, phone numbers, address
- **Server Settings**: Base URL, timeout, check-in interval
- **EMI Settings**: Lock period, grace period
- **Security**: PIN attempts, cooldown period

## 🌐 Backend Setup

The app requires a backend server. See `backend_prompt.md` for:

- API endpoint specifications
- Database schema requirements
- Admin dashboard requirements
- Deployment instructions

**Required Endpoints:**
- `POST /api/v1/devices/checkin` - Device heartbeat
- `POST /api/v1/devices/unlock` - PIN verification
- Admin endpoints for device management

## 📱 Device Provisioning

Devices must be provisioned using the Device Owner method:

1. Factory reset device (no Google account)
2. Enable USB Debugging
3. Run provisioner app
4. App becomes Device Owner
5. Device is ready for customer

See `provisioner_app/README.md` for detailed instructions.

## 🔒 Security Features

- **Device Owner** - Highest level of device control
- **Lock Task Mode** - Prevents app switching
- **Factory Reset Block** - Until EMI paid
- **Uninstall Block** - Until EMI paid
- **Encrypted PIN Storage** - Secure PIN management
- **Server-Side Validation** - PIN verification

## 📊 Server-Side Controls

From the admin dashboard, you can:

- **Lock Device** - Immediately lock any device
- **Unlock Device** - Remove lock remotely
- **Extend EMI** - Add days to payment period
- **Mark as Paid** - Remove all restrictions
- **View Status** - See device info, last seen, days remaining
- **Track Devices** - Monitor all devices in real-time

## 🐛 Troubleshooting

### App Won't Lock
- Verify Device Owner status
- Check server connection
- Review app logs

### Server Connection Fails
- Check server URL in config
- Verify network connectivity
- Review server logs

### Factory Reset Not Blocked
- Ensure Device Owner is active
- Check payment status
- Verify restrictions applied

See [SETUP_GUIDE.md](SETUP_GUIDE.md) for more troubleshooting.

## 📝 Missing Requirements

See [MISSING_REQUIREMENTS.md](MISSING_REQUIREMENTS.md) for:
- Backend server implementation
- Additional configuration needed
- Deployment checklist

## 🔗 Important Files

- `lib/config.dart` - **Update this first!**
- `lib/main.dart` - Main app code
- `SETUP_GUIDE.md` - Complete setup instructions
- `backend_prompt.md` - Backend requirements
- `MISSING_REQUIREMENTS.md` - What's still needed

## 📞 Support

For issues or questions:
- Check logs: `adb logcat | grep FONEX`
- Review server logs
- Check device status in admin dashboard

## 📄 License

Proprietary - Roy Communication

## 🎯 Next Steps

1. ✅ Configure `lib/config.dart`
2. ⚠️ **Deploy backend server** (see `backend_prompt.md`)
3. ✅ Build and test app
4. ✅ Provision test device
5. ✅ Deploy to production

---

**Note**: The backend server is **critical** - the app will not function properly without it. See `backend_prompt.md` for backend implementation requirements.
