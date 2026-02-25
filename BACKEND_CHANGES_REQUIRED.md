# 📋 BACKEND CHANGES REQUIRED - COMPLETE GUIDE

## ✅ Status: MINIMAL CHANGES NEEDED

Your FONEX app uses **Supabase** for everything. Only database table setup required.

---

## 🗄️ STEP 1: CREATE DATABASE TABLES

### **Table 1: device_commands** (REQUIRED)

This table stores lock/unlock commands from your backend to devices.

**Run in Supabase Dashboard → SQL Editor:**

```sql
CREATE TABLE IF NOT EXISTS public.device_commands (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL,
    command TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    processed_at TIMESTAMP WITH TIME ZONE,
    PRIMARY KEY (id)
);

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.device_commands;

-- Create indexes for better performance
CREATE INDEX idx_device_commands_device_id ON public.device_commands(device_id);
CREATE INDEX idx_device_commands_processed ON public.device_commands(processed);
```

**Columns:**
| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `id` | UUID | ✅ | Primary key, auto-generated |
| `device_id` | TEXT | ✅ | Device identifier (from app) |
| `command` | TEXT | ✅ | Either 'LOCK' or 'UNLOCK' |
| `created_at` | TIMESTAMP | ✅ | When command was created |
| `processed` | BOOLEAN | ❌ | Default false, app sets to true when done |
| `processed_at` | TIMESTAMP | ❌ | When app processed the command |

---

### **Table 2: devices** (OPTIONAL - for tracking)

Optional table to track device state and owner info.

```sql
CREATE TABLE IF NOT EXISTS public.devices (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL UNIQUE,
    user_id UUID,
    phone_number TEXT,
    locked BOOLEAN NOT NULL DEFAULT FALSE,
    paid_in_full BOOLEAN NOT NULL DEFAULT FALSE,
    days_remaining INT NOT NULL DEFAULT 30,
    amount_due DECIMAL(10, 2) DEFAULT 0,
    last_locked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id)
);

-- Create indexes
CREATE INDEX idx_devices_device_id ON public.devices(device_id);
CREATE INDEX idx_devices_paid_status ON public.devices(paid_in_full);
```

---

### **Table 3: device_logs** (OPTIONAL - for audit trail)

For tracking all actions on devices.

```sql
CREATE TABLE IF NOT EXISTS public.device_logs (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id)
);

CREATE INDEX idx_device_logs_device_id ON public.device_logs(device_id);
CREATE INDEX idx_device_logs_action ON public.device_logs(action);
```

---

## 🔧 STEP 2: ENABLE REALTIME

**In Supabase Dashboard:**

1. Go to **Settings → Replication**
2. Find `device_commands` under `public` schema
3. Toggle **ON** ✅

**Verify with SQL:**

```sql
-- Check Realtime is enabled
SELECT * FROM pg_publication WHERE pubname = 'supabase_realtime';
```

---

## 📤 STEP 3: HOW TO SEND COMMANDS

### **Lock a Device**

```sql
INSERT INTO public.device_commands (device_id, command)
VALUES ('device-123-abc', 'LOCK');
```

### **Unlock a Device**

```sql
INSERT INTO public.device_commands (device_id, command)
VALUES ('device-123-abc', 'UNLOCK');
```

### **From Your Backend (Node.js Example)**

```javascript
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://your-project.supabase.co',
  'your-anon-key'
);

// Lock device
await supabase
  .from('device_commands')
  .insert([
    {
      device_id: 'device-123-abc',
      command: 'LOCK'
    }
  ]);

// Unlock device
await supabase
  .from('device_commands')
  .insert([
    {
      device_id: 'device-123-abc',
      command: 'UNLOCK'
    }
  ]);
```

### **From Your Backend (Python Example)**

```python
from supabase import create_client, Client

url = "https://your-project.supabase.co"
key = "your-anon-key"
supabase: Client = create_client(url, key)

# Lock device
data = supabase.table('device_commands').insert({
    'device_id': 'device-123-abc',
    'command': 'LOCK'
}).execute()

# Unlock device
data = supabase.table('device_commands').insert({
    'device_id': 'device-123-abc',
    'command': 'UNLOCK'
}).execute()
```

### **From Your Backend (REST API)**

```bash
# Lock device
curl -X POST 'https://your-project.supabase.co/rest/v1/device_commands' \
  -H 'apikey: your-anon-key' \
  -H 'Content-Type: application/json' \
  -d '{
    "device_id": "device-123-abc",
    "command": "LOCK"
  }'

# Unlock device
curl -X POST 'https://your-project.supabase.co/rest/v1/device_commands' \
  -H 'apikey: your-anon-key' \
  -H 'Content-Type: application/json' \
  -d '{
    "device_id": "device-123-abc",
    "command": "UNLOCK"
  }'
```

---

## 🔍 STEP 4: MONITOR COMMANDS

### **View Pending Commands**

```sql
SELECT device_id, command, created_at
FROM public.device_commands
WHERE processed = FALSE
ORDER BY created_at DESC;
```

### **View Processed Commands**

```sql
SELECT device_id, command, created_at, processed_at
FROM public.device_commands
WHERE processed = TRUE
ORDER BY processed_at DESC
LIMIT 100;
```

### **View Commands for Specific Device**

```sql
SELECT device_id, command, created_at, processed, processed_at
FROM public.device_commands
WHERE device_id = 'device-123-abc'
ORDER BY created_at DESC;
```

---

## 📊 STEP 5: TRACK DEVICE STATE (OPTIONAL)

Update `devices` table after sending command:

```sql
-- When device should be LOCKED
UPDATE public.devices
SET locked = TRUE, last_locked_at = NOW()
WHERE device_id = 'device-123-abc';

-- When device should be UNLOCKED
UPDATE public.devices
SET locked = FALSE
WHERE device_id = 'device-123-abc';

-- Mark device as paid
UPDATE public.devices
SET paid_in_full = TRUE, days_remaining = NULL
WHERE device_id = 'device-123-abc';

-- Mark device as unpaid with X days remaining
UPDATE public.devices
SET paid_in_full = FALSE, days_remaining = 30
WHERE device_id = 'device-123-abc';
```

---

## 🔐 STEP 6: SET UP ROW LEVEL SECURITY (RLS)

Optional but recommended for production:

```sql
-- Enable RLS on device_commands
ALTER TABLE public.device_commands ENABLE ROW LEVEL SECURITY;

-- Allow anyone to insert (for your backend)
CREATE POLICY "Allow insert on device_commands"
  ON public.device_commands
  FOR INSERT
  WITH CHECK (true);

-- Allow anyone to read
CREATE POLICY "Allow read on device_commands"
  ON public.device_commands
  FOR SELECT
  USING (true);

-- Allow update (for app to mark as processed)
CREATE POLICY "Allow update on device_commands"
  ON public.device_commands
  FOR UPDATE
  WITH CHECK (true);
```

---

## 🧪 STEP 7: TEST THE INTEGRATION

### **Test 1: Basic Insert**

```sql
INSERT INTO public.device_commands (device_id, command)
VALUES ('test-device', 'LOCK')
RETURNING id, device_id, command, created_at;
```

Expected: ✅ Row inserted

### **Test 2: App Processes Command**

With app running:

```sql
-- Insert command
INSERT INTO public.device_commands (device_id, command)
VALUES ('your-device-id', 'LOCK');

-- Wait 5-10 seconds
-- Check if app marked it as processed
SELECT device_id, command, processed, processed_at
FROM public.device_commands
WHERE device_id = 'your-device-id'
AND command = 'LOCK';
```

Expected: ✅ `processed = TRUE` and `processed_at` has timestamp

### **Test 3: Realtime Verification**

Keep this open in one tab:

```sql
SELECT COUNT(*) as total_commands,
       COUNT(*) FILTER (WHERE processed = TRUE) as processed,
       COUNT(*) FILTER (WHERE processed = FALSE) as pending
FROM public.device_commands;
```

In another tab, insert:

```sql
INSERT INTO public.device_commands (device_id, command)
VALUES ('realtime-test', 'UNLOCK');
```

Expected: ✅ Count updates automatically (Realtime working)

---

## 📋 API ENDPOINTS (If Using REST)

### **Insert Command**

```
POST https://your-project.supabase.co/rest/v1/device_commands
Content-Type: application/json
Authorization: Bearer your-anon-key

{
  "device_id": "device-123",
  "command": "LOCK"
}
```

### **Get Pending Commands**

```
GET https://your-project.supabase.co/rest/v1/device_commands?processed=eq.false
Authorization: Bearer your-anon-key
```

### **Update Command Status**

```
PATCH https://your-project.supabase.co/rest/v1/device_commands?id=eq.{id}
Content-Type: application/json
Authorization: Bearer your-anon-key

{
  "processed": true,
  "processed_at": "2026-02-25T10:30:00Z"
}
```

---

## 🚀 STEP 8: DEPLOY CHECKLIST

- [ ] Created `device_commands` table
- [ ] Enabled Realtime for `device_commands`
- [ ] Created indexes for performance
- [ ] Tested INSERT works
- [ ] Tested app processes commands (gets marked as processed)
- [ ] Tested with real device ID
- [ ] Created `devices` table (optional)
- [ ] Tested REST API (if using)
- [ ] Set up RLS (if needed)
- [ ] Verified Realtime is instant

---

## ⚠️ IMPORTANT NOTES

✅ **Supabase handles everything:**
- Realtime messaging
- Database storage
- No additional servers needed

✅ **App automatically:**
- Listens for commands
- Executes lock/unlock
- Marks commands as processed
- Reconnects if connection drops

✅ **Your backend only needs to:**
- INSERT commands into `device_commands`
- Optionally UPDATE `devices` table for state tracking

❌ **Don't forget:**
- Enable Realtime on `device_commands` table
- Use correct device IDs
- Commands must be exactly 'LOCK' or 'UNLOCK' (case-sensitive)

---

## 🔗 CONFIGURATION IN FONEX APP

In `lib/config.dart`:

```dart
// Your Supabase credentials (already set)
static const String supabaseUrl = 'https://itwyfrwkhohdrgpboagf.supabase.co';
static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIs...';
```

No changes needed! App will use these to connect to `device_commands` table.

---

## 📞 TROUBLESHOOTING

### **Commands not being processed**
1. Check app logs: `flutter logs | grep SupabaseCommandListener`
2. Verify Realtime enabled in Supabase Dashboard
3. Verify device_id matches exactly
4. Check app has internet connection

### **Realtime not working**
1. Go to Supabase Settings → Replication
2. Ensure `device_commands` is enabled
3. Restart app

### **"Table does not exist" error**
1. Run CREATE TABLE SQL from Step 1
2. Verify table in Supabase Dashboard

---

## ✅ SUMMARY

**That's it!** Your backend only needs:

1. ✅ CREATE `device_commands` table
2. ✅ ENABLE Realtime
3. ✅ INSERT commands when needed
4. ✅ Let app handle everything else

**Zero additional code needed. Zero extra servers needed. Zero API endpoints to build.**

Everything else is already in the FONEX app! 🎉
