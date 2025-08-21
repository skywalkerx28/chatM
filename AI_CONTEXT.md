# AI Context for **Mchat**

This document briefs contributors and AI agents on what **Mchat** is, why it exists, and how it’s built. Use it to keep design, code, and discussions aligned.

---

## What is Mchat?

**Mchat** is a decentralized, campus-only messenger that works **offline** using a Bluetooth Low Energy (BLE) **mesh** (multi-hop). It requires no phone numbers or central chat servers and is restricted to verified students. Discovery is **isolated** so only Mchat devices see each other.

### Core Goals

* **Campus-only access** — Sign-up limited to institutional emails (e.g., `@mcgill.ca`, `@mail.mcgill.ca`) via AWS Cognito.
* **Isolated mesh identity** — A distinct BLE **service UUID** (and characteristic UUIDs) so Mchat peers discover **only** Mchat peers.
* **Distinct channels under a mainnet** — Course/topic rooms (e.g., `MATH-262`) plus a campus-wide **Announcements** feed.
* **Lightweight authorization** — Short-lived **membership credentials** broadcast via presence; room traffic gated by campus membership.
* **Private DMs** — End-to-end encrypted direct messages using Noise; unaffected by room gating.
* **Offline-first** — Compact binary protocol, TTL, deduplication, and conservative radio use for reliability.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                UI Layer                                 │
│                Home(General (campus-wide chat),
            Broadcast (Annoucments board), Favorites), 
                   Subchat List, Room / DM Views                          │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                          Application Services                           │
│ ProfileStore • CredentialStore • TopicManager • Presence • CampusGate   │
│ MessageRouter (mesh-first) • Delivery/Ack tracking • Notifications      │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                         Security & Identity Layer                       │
│  NoiseEncryptionService (DMs) • Device Key Mgmt • Membership Credential │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                         Protocol / Message Layer                        │
│     MchatProtocol (binary frames: room msg, presence, DM, control)      │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
┌─────────────────────────────────────────────────────────────────────────┐
│                         Bluetooth Transport Layer                       │
│                    MeshService (BLE advertise / scan / connect)         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Distinct Mesh Identity (Isolated Discovery)

**Objective:** ensure only Mchat devices discover/connect with each other.

**Implementation steps:**

1. **Mint UUIDs**

   * Generate a new BLE **service UUID** (`MCHAT_SERVICE_UUID`) and \*\*characteristic UUID(s)\`.

2. **Advertise**

   * Include `MCHAT_SERVICE_UUID` in `CBAdvertisementDataServiceUUIDsKey`.
   * Keep the local name privacy-preserving (e.g., short random peer tag or empty).

3. **Scan**

   * Filter **only** for `MCHAT_SERVICE_UUID`. Ignore discoveries that lack this UUID.

4. **Handshake tag (optional, recommended)**

   * Add an 8-byte **network tag/version** in the initial handshake payload; drop sessions with mismatched tag.

5. **Manufacturer data (optional)**

   * Add a small Mchat marker in advertisement manufacturer data to further reduce false positives.

**Result:** Mchat forms its **own** mesh; other apps and networks do not appear in the neighbor set.

---

## Identity, Auth, and Profile

* **Sign-up / Sign-in (custom UI, SRP):** AWS Cognito **User Pools** (no hosted UI).

  * **PreSignUp trigger:** allow only campus domains (e.g., `@mcgill.ca`, `@mail.mcgill.ca`).
  * **PreAuth trigger:** defense-in-depth checks (optional).
  * **PostConfirmation trigger:** create canonical, immutable **`@handle`** and `campus_id` in DynamoDB:

    * `pk = "USER#<sub>"`, `sk = "PROFILE"`, attributes: `handle`, `campus_id`, `aid`, `created_at`
    * `pk = "HANDLE#<handle>"`, `sk = "USER"`, attributes: `userId = <sub>`, `campus_id`

* **App profile fetch:**

  * **API Gateway (HTTP API) + JWT authorizer** (Issuer = pool URL, Audience = app client ID).

    * `GET /me` → `{ handle, campus_id, aid, created_at }`.

* **Membership credential issuance:**

  * Device generates or loads **Ed25519** key (32-byte public key).
  * `POST /issue` with `{ device_pub }` → returns **credential**:

    ```
    { campus_id, device_pub, iat, exp, kid }
    ```
  * Cache credential; renew \~10–20% before `exp`. (Future: COSE\_Sign1 signatures.)

---

## Campus Credential & Gating

* **JWT-based credentials:** On-demand exchange of Cognito ID tokens (containing `campus_id`) with optional device Ed25519 proof-of-possession.
* **CampusGate rules:**

  * Accept room messages only if the sender has **valid cached JWT credential** and **matching `campus_id`** extracted from `conversationId` prefix.
  * Request/cache credentials on first contact; O(1) lookups thereafter.
  * Drop room messages from unverified or mismatched campus senders.
* **DMs:** Bypass CampusGate; remain end-to-end encrypted with Noise.

---

## Subnets (Course/Topic Rooms) & Announcements

* **Deterministic room addressing:**

  * `courseId = H("DEPT|NUMBER|TERM")`
  * `sessionId = H("date|slot|building|room")`
  * `topic_code = H(campus_id) || H(courseId) || H(sessionId)` (fixed length, e.g., 16–32 bytes)

* **Private subnets (optional):**

  * Room password → derive symmetric key (Argon2id) → encrypt room payloads (AES-GCM).
  * Only devices with the password can decrypt/read.

* **Announcements:**

  * Reserved campus-wide channel surfaced on Home.
  * (Optional) write-restricted to admin handles; clients enforce display filtering.

* **Favorites:**

  * Pin most-active/joined rooms for quick access on Home.

---

## Protocol Notes (Wire Efficiency)

* **Binary framing** (no JSON on the wire).
* **Message types:** `Presence`, `RoomMessage`, `PrivateMessage`, `Announcement`, `Control`.
* **IDs & TTL:** Per-message IDs for deduplication; TTL to limit hops.
* **Padding/timing noise:** Optional obfuscation for traffic analysis resistance.
* **Size discipline:** Keep frames < MTU; support fragmentation/reassembly in MeshService.

---

## Backend Surfaces

* **GET `/me`** → returns profile; requires **ID token** in `Authorization: Bearer`.
* **POST `/issue`** → returns membership credential for presence; requires **ID token**.
* **Security:** API Gateway **JWT authorizer**; Lambdas with least-privilege IAM; DynamoDB with **PITR**.

---

## Data Flow (Sign-Up → Chat)

1. **Sign-up (SRP)** with campus email → confirm code.
2. **PostConfirmation** writes profile to DynamoDB.
3. **Sign-in** → obtain **ID token**.
4. **`/me`** → cache `{ handle, campus_id }`.
5. **Device key** → Ed25519, 32-byte pub.
6. **`/issue`** with base64(pub32) → cache **credential**.
7. **Presence** → start periodic broadcast.
8. **Join subnet** → compute `topic_code`; send/receive with CampusGate enforced.
9. **DMs** → Noise E2E; unaffected by CampusGate.

---

## Code Organization (suggested)

```
/Mchat
  /Auth
    AmplifySetup.swift
    AuthService.swift
  /Backend
    APIClient.swift            // /me, /issue
  /Membership
    MembershipCredential.swift
    MembershipCredentialManager.swift
    PresenceService.swift
    CampusGate.swift
    TopicManager.swift
  /Mesh
    MeshService.swift          // BLE advertise/scan/connect (MCHAT UUIDs)
    RelayRouter.swift          // TTL, dedup
  /Protocol
    MchatProtocol.swift        // binary encode/decode, types
    BinaryEncoding.swift
  /Security
    NoiseEncryptionService.swift
    DeviceKeys.swift
  /UI
    HomeView.swift
    RoomView.swift
    DMView.swift
```

---

## Development Guidelines

* **Isolation first:** Use **Mchat UUIDs** in MeshService; scan/advertise only on those.
* **Binary over BLE:** Keep payloads tiny; avoid verbose metadata.
* **Don’t break DMs:** Noise flows remain intact; CampusGate applies only to rooms.
* **Token discipline:** Use **ID token** for API; SRP handles refresh.
* **Hash consistency:** Use the same hash/truncation across platforms for `topic_code`.
* **No secret logs:** Never log credentials, keys, or raw payloads.
* **Credential hygiene:** Renew 10–20% before `exp`; presence TTL ≤ 10–15 min.

---

## Acceptance Criteria / Smoke Tests

1. **Isolation**

   * Devices running Mchat discover/connect only with **Mchat** (not other apps).
2. **Onboarding**

   * Non-campus email → blocked at sign-up.
   * Campus email → confirm → DynamoDB rows exist:

     * `USER#<sub>/PROFILE` and `HANDLE#<handle>/USER`.
3. **API**

   * `/me` 200 with `{ handle, campus_id, aid, created_at }` using **ID token**.
   * `/issue` 200 with `{ credential: {...} }` when sent a valid 32-byte pubkey.
4. **Presence Gate**

   * Room messages from peers without valid presence or wrong `campus_id` are dropped.
5. **Rooms**

   * `topic_code` deterministic and identical across devices for the same course/session.
   * Optional room password successfully encrypts content; outsiders cannot read.
6. **DMs**

   * Noise DMs function regardless of room membership; remain E2E.

---

## Roadmap

* Replace JSON credential with **COSE\_Sign1**; verify on device against published issuer public key.
* Admin-signed **Announcements** (write-restricted).
* Optional cross-campus bridging via policy-driven gateways.
* File snippets (chunked + AEAD).
* On-device spam controls (rate limits, optional PoW for unsolicited presence).

---

## Quick Start for AI Agents

1. Respect the **layering**: Transport → Protocol → Security → Services → UI.
2. Enforce **mesh isolation**: only Mchat UUIDs in advertise/scan.
3. Keep the **wire small**: binary frames; minimal metadata.
4. **Don’t touch Noise** DMs; CampusGate is for rooms only.
5. Test **end-to-end**: onboard → `/me` → `/issue` → presence → join room → relay.

---


