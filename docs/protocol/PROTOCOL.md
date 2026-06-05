# Maccy Sync Protocol v1

Source of truth for the wire protocol shared by the Mac app (`Maccy/Sync/`) and
the Android app (`mobile/android/`). Both sides MUST implement this identically.

## Roles & connection

- **Mac = server.** Listens on a TCP port, advertises it via Bonjour/mDNS
  service type `_maccysync._tcp` (TXT records: `id`, `name`, `pv`=protocolVersion).
- **Android = client.** Discovers the service via `NsdManager`, connects.
- One **persistent, full-duplex** TLS connection carries everything in both
  directions.
- Default port: `53121` (server may pick another; clients use the discovered/QR
  port).

## Security: TLS 1.3 + mutual cert-pinning

- Each device owns a long-lived **self-signed identity certificate** (ECDSA
  P-256). Mac stores the private key in the Keychain; Android in the Keystore.
- The **identity** of a device is the SHA-256 hash of its certificate's
  SubjectPublicKeyInfo (SPKI), base64-encoded — the **pin** (a.k.a. `fp`).
- The TLS connection uses **both** certs (client + server auth). The CA chain is
  ignored; trust is decided purely by SPKI-pin matching:
  - **Client (Android) → server (Mac):** always require the server cert pin to
    equal the expected Mac pin (from the QR during pairing, or the stored pin
    afterward).
  - **Server (Mac) → client (Android):**
    - *Pairing mode:* accept any client cert, but **capture** its pin.
    - *Normal mode:* require the client cert pin to be one of the stored,
      previously-paired device pins.

### Pairing (QR + one-time token)

1. Mac generates (once) its identity cert. To pair, it generates a random
   **one-time token** (32 bytes), enters *pairing mode*, and displays a QR.
2. **QR payload** — UTF-8 JSON:
   ```json
   {
     "v": 1,
     "host": "192.168.1.20",
     "hosts": ["192.168.1.20", "10.0.0.5"],
     "port": 53121,
     "fp": "<base64 SHA-256 of Mac cert SPKI>",
     "token": "<base64 32 random bytes>",
     "name": "Roy's Mac",
     "deviceId": "<mac uuid>"
   }
   ```
   `host` is the primary address; `hosts` lists all candidate LAN IPs (try in
   order). `port` is the listening port.
3. Phone scans, connects via TLS, and validates the Mac server cert pin == `fp`.
   (If it mismatches → abort: possible MITM.)
4. Phone sends `pairRequest` (below) carrying the `token`, its own `deviceId`,
   `name`, and its cert pin `fp`.
5. Mac verifies the token matches the active pairing token. On success it stores
   the phone's `{deviceId, name, pin}`, replies `pairAccepted`, exits pairing
   mode, and invalidates the token. On mismatch → `pairRejected` and close.
6. Both sides now hold the other's pin persistently → future connections use
   pin-only mutual trust and skip straight to `hello` + `historySync`.

## Framing

A stream of **frames**. Each frame:

```
[ 4 bytes  | big-endian uint32 length N of the rest of the frame ]
[ 1 byte   | kind ]
[ N-1 bytes| payload ]
```

- `kind = 0x01` — **Control**: payload is UTF-8 JSON (a message object, below).
- `kind = 0x02` — **Content chunk** (binary): payload is
  ```
  [ 16 bytes | itemId as raw UUID bytes ]
  [ 4 bytes  | seq, big-endian uint32, starting at 0 ]
  [ 1 byte   | flags: bit0 = last chunk ]
  [ rest     | raw content bytes for this chunk ]
  ```

Max frame length: **17 MB** (`0x01100000`); receivers MUST reject larger.
Chunk size for content: **64 KiB** of payload bytes per chunk.

## Control messages (`kind = 0x01`, JSON)

Every control message has a string field `t` (type). Unknown `t` → ignore.

### Handshake

```json
{ "t": "hello", "deviceId": "<uuid>", "name": "Roy's Mac",
  "platform": "macos" | "android", "protocolVersion": 1 }
```
Sent by **both** sides immediately after the TLS connection is up (normal mode).
A side MUST NOT send history/clips before it has sent and received `hello`.

### Pairing

```json
{ "t": "pairRequest", "token": "<base64>", "deviceId": "<uuid>",
  "name": "Roy's Phone", "fp": "<base64 phone SPKI pin>" }

{ "t": "pairAccepted", "deviceId": "<uuid>", "name": "Roy's Mac" }
{ "t": "pairRejected", "reason": "<string>" }
```

### History & clips

```json
{ "t": "historySync", "items": [ <ItemMeta>, ... ] }
{ "t": "clipAdded", "item": <ItemMeta> }
```
On connect (after `hello` both ways), each side sends one `historySync` with its
most recent items (default **50**, newest first). Each new local copy → one
`clipAdded`.

**ItemMeta**:
```json
{
  "id": "<uuid>",
  "kind": "text" | "image" | "file",
  "createdAt": 1733356800000,        // unix millis
  "size": 12345,                     // total content bytes
  "mime": "text/plain",              // best-effort
  "preview": "first line / caption", // short human label, always present
  "text": "full text or null",       // text kind only, present iff size <= INLINE_TEXT_CAP
  "filename": "photo.png or null",   // file/image kind
  "thumb": "<base64 PNG or null>"    // image kind, <= THUMB_CAP bytes
}
```

### Lazy content fetch

When a receiver needs full bytes it does not already have (large text, full-res
image, file), it requests them:

```json
{ "t": "contentRequest", "id": "<uuid>" }
```
The owner replies with a `contentBegin`, then one or more **content-chunk**
frames (`kind 0x02`) with the same `id`, `seq` 0..n, last chunk flagged:
```json
{ "t": "contentBegin", "id": "<uuid>", "kind": "image"|"file"|"text",
  "size": 12345, "mime": "image/png", "filename": "photo.png or null" }
```
On error (unknown id, too large, read failure):
```json
{ "t": "contentError", "id": "<uuid>", "reason": "<string>" }
```
The receiver reassembles chunks in `seq` order until the `last` flag.

### Keepalive

```json
{ "t": "ping" }
{ "t": "pong" }
```
Each side sends `ping` every **20 s** of idle; expects `pong`. No traffic for
**60 s** → consider the connection dead and reconnect.

## Constants

| Name | Value |
|------|-------|
| `PROTOCOL_VERSION` | `1` |
| Bonjour type | `_maccysync._tcp` |
| Default port | `53121` |
| `INLINE_TEXT_CAP` | `16384` bytes (16 KiB) — text at/under ships inline in ItemMeta |
| `THUMB_CAP` | `65536` bytes (64 KiB) — image thumbnail max |
| `CHUNK_SIZE` | `65536` bytes (64 KiB) |
| `MAX_FRAME` | `17825792` bytes (17 MiB) |
| `MAX_CONTENT` | `16777216` bytes (16 MiB) — content over this → `contentError "too_large"` |
| `HISTORY_SYNC_COUNT` | `50` |
| `PING_INTERVAL` | `20 s` |
| `DEAD_TIMEOUT` | `60 s` |

## Notes

- All UUIDs are lowercase canonical (`8-4-4-4-12`). The 16-byte content-chunk
  itemId is the raw big-endian bytes of that UUID.
- `createdAt` is unix epoch **milliseconds**.
- Text `kind` items at/under `INLINE_TEXT_CAP` need no `contentRequest`.
- A device de-dupes remote items by `id`. Re-receiving a known `id` updates
  ordering, not content.
- v1 is single-peer per side (one Mac ↔ one phone). The protocol does not
  prevent more, but UIs assume one paired peer.
