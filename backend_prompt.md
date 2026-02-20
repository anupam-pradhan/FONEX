# AI Prompt for FONEX Backend Generation

You are an expert Backend Engineer and Systems Architect. Your task is to build a modern, high-performance, and scalable backend for **FONEX**, an Android-based device financing and lock management system (similar to Samsung Knox or PayJoy).

The backend must be built using **modern, future-proof technologies**. Avoid deprecated or legacy patterns (e.g., no raw callback hell, no outdated libraries). Use modern Node.js/TypeScript and a robust web framework (like Next.js API Routes/Server Actions, NestJS, Fastify, or Express).

**Hosting & Database Constraints:**

- **Hosting:** The backend must be designed to be hosted on **Vercel for free**. Use edge-compatible features or serverless functions where appropriate.
- **Database:** It must use a **free tier** scalable database. Please use **Supabase (PostgreSQL)**, **Neon DB (PostgreSQL) with Prisma**, or **MongoDB Atlas Free Tier**.

## System Architecture & Requirements

### 1. Device Registration & Auto-Discovery

- The system must support **thousands of multiple devices**.
- Devices should be **auto-registered** upon their first connection.
- When a device pings the server (e.g., via the check-in endpoint), if its unique identifier (`device_hash` and/or `imei`) does not exist in the database, the server should automatically create a profile for it.
- **Auto-Generate PIN:** During registration, the backend MUST automatically generate and save the offline PIN associated with the device hash. The formula is: `(hash * 73 + 123456) % 1000000` (padded to 6 digits).
- The Payload from the device will include metadata such as `imei`, `deviceModel`, `manufacturer`, `androidVersion`, `isDeviceOwner`, `is_locked`, and `days_remaining`.

### 2. Core API Endpoints

The Flutter/Android mobile app communicates with this backend. You must implement the following core REST APIs using modern standards:

#### A. Heartbeat / Check-In API

- **Endpoint:** `POST /api/v1/devices/checkin` (or `/api/devices/checkin` for Next.js)
- **Request Payload:**
  ```json
  {
    "device_hash": "A unique 6-digit or alphanumeric device identifier",
    "imei": "123456789012345 (Optional/Required 15-digit hardware ID)",
    "is_locked": boolean,
    "days_remaining": integer,
    "metadata": {
      "model": "string",
      "manufacturer": "string",
      "android_version": integer
    } // Optional, sent on first connection or periodically
  }
  ```
- **Behavior:**
  - If `device_hash` (or `imei`) is new, auto-register the device to the database and generate its PIN limit.
  - **Offline Sync:** If a device has been offline and finally connects, it will push its latest state. The server must accept this state update seamlessly.
  - Update the device's "last seen" timestamp, current lock state, and days remaining.
  - **Paid in Full:** If the device is marked in the database as "Fully Paid", the response must permanently command the device to `unlock` and disable restrictions.
  - Return a command payload instructing the device on what to do.
- **Response Payload:**
  ```json
  {
    "action": "lock" | "unlock" | "extend" | "paid_in_full" | "none",
    "days": integer // Required if action is 'extend'
  }
  ```
  _(The `action` comes from an admin dashboard where the shop owner clicks "Lock Device", "Unlock Device", "Add 30 Days", or "Mark as Paid")_

#### B. Remote PIN Verification API

- **Endpoint:** `POST /api/v1/devices/unlock`
- **Request Payload:**
  ```json
  {
    "device_hash": "string",
    "pin": "string"
  }
  ```
- **Behavior:**
  - Verify the provided PIN against the hashed PIN stored in the database for this specific device.
  - Rate-limit this endpoint to prevent brute-force attacks (e.g., max 5 attempts per 15 minutes per device).
- **Response Payload:**
  ```json
  {
    "success": boolean,
    "message": "string"
  }
  ```

### 3. Admin Dashboard Capabilities (API Layer)

Build the API foundation for a modern React/Next.js frontend dashboard. An admin (Shop Owner) should be able to:

- List all devices with pagination, sorting, and filtering (e.g., filter by locked/unlocked, overdue).
- View a single device's status (last seen, days remaining, hardware info, IMEI, auto-generated PIN).
- Queue an action (`lock`, `unlock`, `extend_days`, `mark_paid`) for a specific device, which will be picked up on the device's next `/checkin`.
- Set or reset the remote unlock PIN for a device.

### 4. Website Frontend (Next.js Modern Dashboard)

You must also generate the code for a **Modern Frontend Dashboard** built with **Next.js (App Router)**, **React**, and **TailwindCSS**.

- **Features:**
  - A secure login system (JWT or NextAuth).
  - A beautiful, responsive summary dashboard showing total active devices, locked devices, and recent connections.
  - A comprehensive "Device List" data table with search by IMEI/Hash and quick-action buttons (Lock/Unlock/Extend 30 Days/Mark as Fully Paid).
  - A "Device Details" view showing the device's exact offline PIN, last seen time, and all hardware metadata.
- **UX/Design:** Use modern components (e.g., Shadcn UI or Radix) with dark/light mode, toast notifications, loading skeletons, and sleek transitions. It should look like a premium enterprise management tool.

### 5. Future-Proofing & Modern Standards

- **Language:** Strictly **TypeScript** with strict type checking enabled.
- **Database:** Use a mature ORM like **Prisma** (with PostgreSQL) to ensure type safety from DB to API.
- **Security:** Implement modern security headers (Helmet), Rate Limiting (Redis or memory-based), and JWT-based authentication for the Admin API routes. Device routes (`/checkin`, `/unlock`) should use a secure API Key mechanism or signature validation to prevent spoofing.
- **Architecture:** Use a Controller-Service-Repository pattern or clean architecture.
- **Real-time Readiness:** Structure the database and services so that we can easily plug in WebSockets or Server-Sent Events (SSE) in the future to push instant updates to the admin dashboard when a device comes online.
- **Validation:** Use modern validation libraries like **Zod** or `class-validator` for strict runtime payload validation.

## Your Deliverables:

1. Provide the complete **startup configuration** and necessary `package.json` dependencies.
2. Provide the **Database Schema** (e.g., `schema.prisma`).
3. Provide the core **Services and Controllers** for the Device and Admin APIs.
4. Ensure the code is production-ready, heavily commented, modular, and cleanly separated.
