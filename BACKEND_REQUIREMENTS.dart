// =============================================================================
// BACKEND REQUIREMENTS DOCUMENTATION
// =============================================================================
// Changes needed on your backend to support 100% accurate lock/unlock
// =============================================================================

/*
CRITICAL BACKEND CHANGES REQUIRED:

==================================================================================
1. FIREBASE SETUP (For Push Notifications & Background Commands)
==================================================================================

Your backend needs to:

a) Initialize Firebase Admin SDK in your backend:
   - Add firebase-admin package to your backend project
   - Download service account key from Firebase Console
   - Initialize: admin.initializeApp(...)

b) Create API endpoint to send push notifications:

   POST /api/device/send-command
   Body: {
     "device_id": "xxxxxx",
     "command": "LOCK" | "UNLOCK",
     "reason": "Due amount not paid"
   }
   
   Backend should:
   - Get FCM token from devices table (device_id -> fcm_token mapping)
   - Send notification via Firebase Cloud Messaging:
     
     const message = {
       data: {
         command: "LOCK",
         timestamp: new Date().toISOString()
       },
       notification: {
         title: "Device Lock Notice",
         body: "Payment due - Device will be locked"
       },
       android: {
         priority: "high",
         notification: {
           channelId: "device_commands"
         }
       }
     };
     
     admin.messaging().sendToTopic(`device_${deviceId}`, message);

c) Create Realtime Database structure in Firebase Console:

   /commands/{deviceId}/{commandId}
   {
     "id": "cmd_xxxxx",
     "command": "LOCK" | "UNLOCK",
     "timestamp": "2026-02-25T12:00:00Z",
     "processed": false,
     "processed_at": null
   }

==================================================================================
2. DEVICE REGISTRATION WITH FCM TOKEN
==================================================================================

When app starts, it gets FCM token and sends to backend:

   POST /api/device/register
   Body: {
     "device_id": "device_hash_xxxxx",
     "device_hash": "device_hash_xxxxx",
     "fcm_token": "Firebase_FCM_Token_Here",
     "account_email": "user@example.com",
     "account_type": "workspace" | "personal",
     "timestamp": "2026-02-25T12:00:00Z"
   }

Backend should:
- Save device_id -> fcm_token mapping in database
- Update FCM token on re-registration (tokens can change)
- Store account_type to know if personal (features limited) or workspace

Database table structure:

   devices table:
   - device_id (primary key)
   - device_hash
   - fcm_token (for push notifications)
   - account_email
   - account_type (workspace | personal)
   - status (active | locked | paid_in_full)
   - payment_due_date
   - remaining_days
   - created_at
   - updated_at

==================================================================================
3. SEND LOCK COMMAND FROM DASHBOARD
==================================================================================

When admin/backend wants to lock device:

   a) Send via Firebase:
      - Topic: "device_{device_id}"
      - Data: { command: "LOCK", timestamp, reason }
   
   b) Update Realtime Database:
      - Path: /commands/{device_id}/{unique_cmd_id}
      - Value: { command: "LOCK", timestamp, processed: false }

   c) Also send HTTP webhook to app (fallback):
      - Device will check server on 5-minute interval
      - If Realtime/FCM fails, HTTP check-in will catch it

==================================================================================
4. SEND UNLOCK COMMAND FROM DASHBOARD
==================================================================================

Similar to LOCK:
- Send FCM notification with command: "UNLOCK"
- Update Realtime Database
- Reset EMI timer on server side

==================================================================================
5. FIREBASE CONSOLE SETUP STEPS
==================================================================================

1. Go to Firebase Console: https://console.firebase.google.com
2. Create or select your FONEX project
3. Enable Realtime Database:
   - Realtime Database → Create Database
   - Start in test mode (or production with custom rules)
4. Enable Cloud Messaging:
   - Cloud Messaging → Already enabled by default
5. Download service account key:
   - Project Settings → Service Accounts → Generate new private key
6. Initialize in your backend with this JSON key

==================================================================================
6. FIREBASE RULES (Security)
==================================================================================

Realtime Database Rules:
{
  "rules": {
    "commands": {
      "$deviceId": {
        ".read": "root.child('devices').child($deviceId).exists()",
        ".write": "root.child('admin').child(auth.uid).exists()"
      },
      "devices": {
        "$deviceId": {
          ".read": "$deviceId === root.child('devices').child($deviceId).child('owner_uid').val()",
          ".write": "$deviceId === root.child('devices').child($deviceId).child('owner_uid').val()"
        }
      }
    }
  }
}

==================================================================================
7. API ENDPOINTS YOUR BACKEND NEEDS
==================================================================================

POST /api/device/register-fcm
  - Register device with FCM token for push notifications
  - Called on app startup
  
POST /api/device/send-command
  - Send LOCK/UNLOCK command to device
  - Called from admin dashboard
  
GET /api/device/status/{device_id}
  - Get current device status
  
POST /api/device/sync-state
  - Sync device state back to server
  - Called every 5 minutes

POST /api/device/unlock
  - Unlock device (payment received)
  - Reset due date
  
POST /api/device/extend-due
  - Extend due date by X days
  
POST /api/device/mark-paid
  - Mark device as fully paid in full
  - Remove all restrictions

==================================================================================
8. CORE FEATURES FOR ACCOUNT TYPES
==================================================================================

WORKSPACE ACCOUNT (workspace@company.com):
✅ Lock device after due date
✅ Unlock when payment received
✅ Extend due date
✅ Mark as paid in full
✅ Real-time lock/unlock commands
✅ Full analytics

PERSONAL ACCOUNT (user@gmail.com):
✅ View device status (read-only)
✅ View due date
❌ Lock feature DISABLED
❌ Unlock feature DISABLED
❌ Cannot execute critical commands
❌ Limited to monitoring only

Backend should enforce this:
- Check account_type in database
- Reject lock/unlock commands for personal accounts
- Only allow these commands for workspace accounts

==================================================================================
9. TESTING YOUR SETUP
==================================================================================

Test with these commands:

curl -X POST http://your-backend.com/api/device/send-command \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test_device_123",
    "command": "LOCK",
    "reason": "Testing lock command"
  }'

Then check:
1. Device app receives FCM notification
2. Device state updates in app
3. Device lock actually engages on device
4. Realtime Database shows processed: true

==================================================================================
10. PRODUCTION CHECKLIST
==================================================================================

☐ Firebase project created and configured
☐ Realtime Database created with proper rules
☐ Cloud Messaging enabled
☐ Service account key generated
☐ All API endpoints implemented
☐ FCM token registration working
☐ Lock/unlock commands executing on device
☐ Account type restrictions enforced
☐ Device status syncing to server
☐ Due date calculations accurate on server
☐ Error logging and monitoring in place
☐ Tested on real device (not just emulator)

==================================================================================
*/
