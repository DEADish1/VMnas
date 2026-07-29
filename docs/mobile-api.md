# VMnas Mobile API Contract

This contract is shared by iPhone, Android, browser, and future clients.

## Base URL

Local network:

```text
https://vmnas.local:8765
```

Remote access:

```text
https://TAILSCALE-IP:8765
```

Clients should support self-signed VMnas certificates after the user has paired locally.

## Pairing

Pairing is done on the local network or from the server installer screen.

```http
POST /pairing/pair
Content-Type: application/json

{
  "device_name": "User iPhone",
  "pin": "123456"
}
```

Response:

```json
{
  "device_name": "User iPhone",
  "token": "long-device-token"
}
```

Store the token in the platform secure store:

- iPhone: Keychain
- Android: EncryptedSharedPreferences or Android Keystore-backed storage

## Authentication

After at least one device has paired, admin endpoints require:

```http
Authorization: Bearer long-device-token
```

Clients may also send:

```http
X-VMnas-Token: long-device-token
```

## Core Endpoints

```text
GET /health
GET /pairing/status
POST /pairing/pair
POST /pairing/rotate
GET /pairing/devices
DELETE /pairing/devices/{id}
GET /host/resources
GET /host/compatibility
GET /host/disks
GET /host/gpus
GET /host/benchmark/latest
POST /host/benchmark/run
GET /presets/vms
GET /vms
POST /vms
DELETE /vms/{vmid}
POST /vms/{vmid}/start
POST /vms/{vmid}/shutdown
POST /vms/{vmid}/stop
POST /vms/{vmid}/reboot
GET /vms/{vmid}/access
GET /vms/{vmid}/snapshots
POST /vms/{vmid}/snapshots
POST /vms/{vmid}/snapshots/{name}/rollback
DELETE /vms/{vmid}/snapshots/{name}
GET /store/modules
POST /store/modules/{id}/install
GET /store/downloads
GET /isos
POST /isos/upload
GET /os-store/systems
POST /os-store/systems/{id}/download
GET /os-store/downloads
GET /remote/status
POST /remote/enable
POST /remote/disable
```

## Discovery

VMnas advertises:

- `_https._tcp` on port `8765`
- `_vmnas._tcp` on port `8765`

Mobile clients should scan mDNS/Bonjour for `_vmnas._tcp`.

## Remote Access

Remote access is provided by a server-side private VPN module, initially Tailscale. Mobile clients should use `/remote/status` to display whether remote control is ready and which URL/IP should be used.
