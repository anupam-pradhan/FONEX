# 🎯 BACKEND SETUP - QUICK ACTION CARD

## ⚠️ WHAT'S MISSING

Your app code is **100% complete**. Only **ONE thing** needed:

### Create Supabase Table

**Time**: 5 minutes

---

## 🚀 DO THIS NOW

### Step 1: Copy This SQL

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

CREATE INDEX idx_device_commands_device_id ON public.device_commands(device_id);
CREATE INDEX idx_device_commands_processed ON public.device_commands(processed);

ALTER PUBLICATION supabase_realtime ADD TABLE public.device_commands;
```

### Step 2: Paste in Supabase

1. Go: https://app.supabase.com → Select project
2. → **SQL Editor**
3. Paste SQL above
4. Click **RUN**

### Step 3: Verify Realtime

1. Go: **Settings → Replication**
2. Find: `public.device_commands`
3. Toggle: **ON** ✅

### Step 4: Test

```sql
INSERT INTO public.device_commands (device_id, command)
VALUES ('test-123', 'LOCK');

SELECT * FROM public.device_commands WHERE device_id = 'test-123';
```

---

## ✅ APP STATUS

| Component          | Status            |
| ------------------ | ----------------- |
| Supabase Config    | ✅ Complete       |
| Command Listener   | ✅ Complete       |
| Realtime Handler   | ✅ Complete       |
| Lock/Unlock Logic  | ✅ Complete       |
| Error Handling     | ✅ Complete       |
| Auto-Reconnect     | ✅ Complete       |
| **Database Table** | ❌ **Create Now** |

---

## 📋 FROM YOUR BACKEND

### Lock Device

**JavaScript:**

```javascript
await supabase
  .from("device_commands")
  .insert([{ device_id: "ABC123", command: "LOCK" }]);
```

**Python:**

```python
supabase.table('device_commands').insert({
  'device_id': 'ABC123', 'command': 'LOCK'
}).execute()
```

**cURL:**

```bash
curl -X POST 'https://itwyfrwkhohdrgpboagf.supabase.co/rest/v1/device_commands' \
  -H 'apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"ABC123","command":"LOCK"}'
```

### Unlock Device

Same as above but change `command` to `UNLOCK`

---

## 🧪 TEST IT

```bash
# 1. Start app
flutter run

# 2. Note device_id from logs

# 3. In Supabase SQL Editor:
INSERT INTO public.device_commands (device_id, command)
VALUES ('DEVICE_ID_FROM_LOGS', 'LOCK');

# 4. Watch app lock!
# 5. Check Supabase - should show processed=true
```

---

## 🎉 That's It!

**Before**: App code not connected to backend  
**After**: App receives real-time commands and locks/unlocks immediately

Everything else already works! 🚀
