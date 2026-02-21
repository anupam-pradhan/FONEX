# FONEX API Documentation

API documentation for FONEX backend server integration with enterprise-level sync capabilities.

## 🆕 Latest Updates

- **Auto-Registration**: Devices automatically register on first check-in
- **Offline Support**: Sync queue system for reliable offline operation
- **Optimized Sync**: Batch processing with exponential backoff retry logic
- **Local Storage**: Device info saved locally before server sync (offline-first approach)

## Base URL

```
https://your-backend.vercel.app/api/v1/devices
```

## Authentication

Device endpoints use device hash and IMEI for identification. Admin endpoints require JWT authentication.

## Endpoints

### 1. Device Check-In (Heartbeat)

**Endpoint:** `POST /checkin`

**Description:** Device sends periodic heartbeat with status. Server responds with action commands. Supports auto-registration for new devices.

**Request Body:**
```json
{
  "device_hash": "123456",
  "imei": "123456789012345",
  "is_locked": false,
  "days_remaining": 25,
  "metadata": {
    "model": "Samsung Galaxy S21",
    "manufacturer": "Samsung",
    "android_version": 33,
    "is_device_owner": true
  },
  "timestamp": "2024-01-15T10:30:00Z",
  "is_first_registration": false
}
```

**Request Fields:**
- `device_hash` (required): Unique 6-digit device identifier
- `imei` (required): 15-digit IMEI number
- `is_locked` (required): Current lock status
- `days_remaining` (required): Days remaining before lock
- `metadata` (optional): Device hardware information
  - `model`: Device model name
  - `manufacturer`: Device manufacturer
  - `android_version`: Android version number
  - `is_device_owner`: Device Owner mode status
- `timestamp` (required): ISO 8601 timestamp
- `is_first_registration` (optional): `true` for first-time registration, `false` or omitted for subsequent check-ins

**Auto-Registration Behavior:**
- If `device_hash` or `imei` is new, the server automatically creates a device record
- PIN is auto-generated using the formula: `(device_hash * 73 + 123456) % 1000000`
- Device info is saved locally on the client before server sync
- If server sync fails, registration is queued for retry

**Response (200 OK):**
```json
{
  "action": "none",
  "days": null,
  "registered": false
}
```

**Response Fields:**
- `action` (required): Command to execute on device
- `days` (optional): Number of days (required if action is "extend")
- `registered` (optional): `true` if device was just registered, `false` otherwise

**Possible Actions:**
- `"lock"` - Lock the device immediately
- `"unlock"` - Unlock the device
- `"extend"` or `"extend_days"` - Extend EMI period (requires `days` field)
- `"paid_in_full"` or `"mark_paid_in_full"` - Mark as fully paid
- `"none"` - No action required

**Response Examples:**

**New Device Registration:**
```json
{
  "action": "none",
  "days": null,
  "registered": true,
  "message": "Device registered successfully"
}
```

**Extend Days:**
```json
{
  "action": "extend",
  "days": 30,
  "registered": false
}
```

**Error Responses:**
- `400` - Bad Request (invalid payload)
- `429` - Too Many Requests (rate limit exceeded)
- `500` - Server Error
- `503` - Service Unavailable (server overloaded)

**Client-Side Sync Behavior:**
- If check-in fails, the request is automatically queued locally
- Queued requests are retried with exponential backoff
- Sync queue is processed periodically (every 5 minutes)
- Failed syncs are tracked for diagnostics
- Works seamlessly in offline mode

---

### 2. PIN Verification (Unlock)

**Endpoint:** `POST /unlock`

**Description:** Verify PIN for device unlock.

**Request Body:**
```json
{
  "device_hash": "123456",
  "pin": "123456"
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "message": "PIN verified successfully"
}
```

**Error Response:**
```json
{
  "success": false,
  "message": "Invalid PIN"
}
```

**Rate Limiting:**
- Max 5 attempts per 15 minutes per device
- Returns `429 Too Many Requests` if exceeded

---

### 3. List Devices (Admin)

**Endpoint:** `GET /devices`

**Description:** Get list of all devices (admin only).

**Headers:**
```
Authorization: Bearer <JWT_TOKEN>
```

**Query Parameters:**
- `page` - Page number (default: 1)
- `limit` - Items per page (default: 20)
- `status` - Filter by status: `locked`, `unlocked`, `paid`
- `search` - Search by IMEI or device_hash

**Response (200 OK):**
```json
{
  "devices": [
    {
      "id": "device_id",
      "device_hash": "123456",
      "imei": "123456789012345",
      "is_locked": false,
      "days_remaining": 25,
      "is_paid_in_full": false,
      "last_seen": "2024-01-15T10:30:00Z",
      "metadata": {
        "model": "Samsung Galaxy S21",
        "manufacturer": "Samsung",
        "android_version": 33,
        "is_device_owner": true
      },
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2024-01-15T10:30:00Z"
    }
  ],
  "total": 100,
  "page": 1,
  "limit": 20
}
```

---

### 4. Get Device Details (Admin)

**Endpoint:** `GET /devices/:id`

**Description:** Get detailed information about a specific device.

**Headers:**
```
Authorization: Bearer <JWT_TOKEN>
```

**Response (200 OK):**
```json
{
  "id": "device_id",
  "device_hash": "123456",
  "imei": "123456789012345",
  "pin": "789012",
  "is_locked": false,
  "days_remaining": 25,
  "is_paid_in_full": false,
  "last_seen": "2024-01-15T10:30:00Z",
  "metadata": {
    "model": "Samsung Galaxy S21",
    "manufacturer": "Samsung",
    "android_version": 33,
    "is_device_owner": true
  },
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-15T10:30:00Z",
  "registration_date": "2024-01-01T00:00:00Z"
}
```

**Response Fields:**
- `pin`: Auto-generated PIN using formula `(device_hash * 73 + 123456) % 1000000`
- `registration_date`: When device was first registered (same as `created_at` for new devices)

---

### 5. Device Action (Admin)

**Endpoint:** `POST /devices/:id/action`

**Description:** Queue an action for a device (executed on next check-in).

**Headers:**
```
Authorization: Bearer <JWT_TOKEN>
```

**Request Body:**
```json
{
  "action": "lock",
  "days": null
}
```

**Actions:**
- `"lock"` - Lock device
- `"unlock"` - Unlock device
- `"extend"` - Extend EMI (requires `days`)
- `"mark_paid"` - Mark as paid in full

**Response (200 OK):**
```json
{
  "success": true,
  "message": "Action queued successfully",
  "action": "lock"
}
```

---

## PIN Generation

The backend automatically generates PINs using this formula:

```javascript
const pin = ((parseInt(device_hash) * 73 + 123456) % 1000000).toString().padStart(6, '0');
```

Example:
- Device hash: `123456`
- PIN: `((123456 * 73 + 123456) % 1000000) = 789012`

## Error Codes

| Code | Description | Client Behavior |
|------|-------------|----------------|
| 200 | Success | Process response and update local state |
| 201 | Created | Device registered successfully |
| 400 | Bad Request | Log error, do not retry |
| 401 | Unauthorized | Log error, do not retry |
| 404 | Not Found | Log error, do not retry |
| 429 | Too Many Requests | Queue for retry with backoff |
| 500 | Server Error | Queue for retry with exponential backoff |
| 503 | Service Unavailable | Queue for retry with exponential backoff |

## Rate Limiting

- **Check-in**: No hard limit (but recommended max 1 per 5 minutes per device)
  - Client implements automatic retry with exponential backoff
  - Failed requests are queued locally and retried when network is available
- **Unlock**: 5 attempts per 15 minutes per device
- **Admin endpoints**: 100 requests per minute per user

## Sync Queue & Offline Support

The client implements an enterprise-level sync system:

### Features:
- **Automatic Queue Management**: Failed syncs are queued locally
- **Batch Processing**: Multiple queued items processed efficiently
- **Exponential Backoff**: Smart retry logic prevents server overload
- **Offline Support**: Works seamlessly without network connection
- **Auto-Retry**: Queued items automatically retried when network is available

### Sync Queue Behavior:
1. If check-in fails (network error, server error), request is queued
2. Queue is processed every 5 minutes automatically
3. Items are retried up to 3 times with exponential backoff
4. After max retries, item is removed from queue (logged for diagnostics)
5. Queue size is limited to 100 items to prevent storage bloat

### First-Time Registration Flow:
1. Device info is saved locally immediately (offline-first approach)
2. Registration request is sent to server
3. If successful, `registered: true` flag is set
4. If failed, registration is queued for retry
5. Device can function normally even if initial sync fails

## Client-Side Implementation

### Sync Service Features

The Flutter client implements an enterprise-level sync service with the following capabilities:

#### Auto-Save Registration
- Device info is saved locally **before** server sync
- Works offline - registration persists even if server is unavailable
- Automatic retry when network becomes available

#### Sync Queue Management
- Failed syncs automatically queued locally
- Queue processed every 5 minutes
- Batch processing for efficiency
- Maximum 100 items in queue (oldest removed if exceeded)

#### Retry Logic
- Exponential backoff: 2s, 4s, 8s delays
- Maximum 3 retries per item
- Automatic removal after max retries (logged for diagnostics)

#### Offline Support
- All operations work offline
- State changes queued for sync
- Automatic sync when network available
- No data loss during offline periods

### Local Storage

Device registration info is stored locally using SharedPreferences:
- Device hash
- IMEI
- Device metadata
- Registration timestamp
- Last sync timestamp
- Sync queue
- Failed sync history

## Backend Implementation Requirements

### Auto-Registration Handling

When a device sends a check-in with a new `device_hash` or `imei`:

1. **Create Device Record**: Automatically create a new device entry in database
2. **Generate PIN**: Use formula `(device_hash * 73 + 123456) % 1000000` (padded to 6 digits)
3. **Store Metadata**: Save device metadata (model, manufacturer, Android version, etc.)
4. **Set Initial State**: 
   - `is_locked`: false
   - `days_remaining`: 30 (or configured default)
   - `is_paid_in_full`: false
5. **Return Response**: Include `registered: true` in response

### Database Schema Recommendations

```sql
CREATE TABLE devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_hash VARCHAR(6) UNIQUE NOT NULL,
  imei VARCHAR(15) UNIQUE NOT NULL,
  pin VARCHAR(6) NOT NULL,
  is_locked BOOLEAN DEFAULT false,
  days_remaining INTEGER DEFAULT 30,
  is_paid_in_full BOOLEAN DEFAULT false,
  metadata JSONB,
  last_seen TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_device_hash ON devices(device_hash);
CREATE INDEX idx_imei ON devices(imei);
CREATE INDEX idx_last_seen ON devices(last_seen);
```

### Handling Offline Sync

When a device that was offline comes back online:

1. Device sends check-in with current state
2. Server should accept the state update seamlessly
3. Update `last_seen` timestamp
4. If state differs significantly, log for review
5. Return appropriate action command

### Error Handling

- **400 Bad Request**: Invalid payload format or missing required fields
- **429 Too Many Requests**: Rate limit exceeded (client will retry)
- **500 Server Error**: Internal server error (client will retry with backoff)
- **503 Service Unavailable**: Server overloaded (client will retry)

All errors should be handled gracefully - client will queue and retry automatically.

## Webhooks (Future)

Future implementation may include webhooks for:
- Device registered (first-time)
- Device locked
- Device unlocked
- Payment received
- Device offline for extended period
- Sync queue processed

---

For complete backend implementation details, see `backend_prompt.md`.
