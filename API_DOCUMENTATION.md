# FONEX API Documentation

API documentation for FONEX backend server integration.

## Base URL

```
https://your-backend.vercel.app/api/v1/devices
```

## Authentication

Device endpoints use device hash and IMEI for identification. Admin endpoints require JWT authentication.

## Endpoints

### 1. Device Check-In (Heartbeat)

**Endpoint:** `POST /checkin`

**Description:** Device sends periodic heartbeat with status. Server responds with action commands.

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
    "android_version": 33
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Response (200 OK):**
```json
{
  "action": "none",
  "days": null
}
```

**Possible Actions:**
- `"lock"` - Lock the device immediately
- `"unlock"` - Unlock the device
- `"extend"` or `"extend_days"` - Extend EMI period (requires `days` field)
- `"paid_in_full"` or `"mark_paid_in_full"` - Mark as fully paid
- `"none"` - No action required

**Response with Extend:**
```json
{
  "action": "extend",
  "days": 30
}
```

**Error Responses:**
- `400` - Bad Request (invalid payload)
- `500` - Server Error

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
      "last_seen": "2024-01-15T10:30:00Z",
      "metadata": {
        "model": "Samsung Galaxy S21",
        "manufacturer": "Samsung",
        "android_version": 33
      },
      "created_at": "2024-01-01T00:00:00Z"
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
  "pin": "789012", // Auto-generated PIN
  "is_locked": false,
  "days_remaining": 25,
  "is_paid_in_full": false,
  "last_seen": "2024-01-15T10:30:00Z",
  "metadata": {
    "model": "Samsung Galaxy S21",
    "manufacturer": "Samsung",
    "android_version": 33
  },
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-15T10:30:00Z"
}
```

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

| Code | Description |
|------|-------------|
| 200 | Success |
| 400 | Bad Request |
| 401 | Unauthorized |
| 404 | Not Found |
| 429 | Too Many Requests |
| 500 | Server Error |

## Rate Limiting

- Check-in: No limit (but recommended max 1 per 5 minutes)
- Unlock: 5 attempts per 15 minutes per device
- Admin endpoints: 100 requests per minute per user

## Webhooks (Future)

Future implementation may include webhooks for:
- Device locked
- Device unlocked
- Payment received
- Device offline for extended period

---

For backend implementation, see `backend_prompt.md`.
