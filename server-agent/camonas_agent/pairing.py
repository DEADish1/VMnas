from __future__ import annotations

import json
import os
import secrets
import hmac
from dataclasses import dataclass
from pathlib import Path


@dataclass
class PairingStore:
    path: Path

    @classmethod
    def default(cls) -> "PairingStore":
        path = Path(os.environ.get("CAMONAS_PAIRING_STORE", "/var/lib/camonas/pairing.json"))
        if not os.access(path.parent, os.W_OK):
            path = Path.home() / ".camonas" / "pairing.json"
        return cls(path=path)

    def ensure(self) -> dict:
        if self.path.exists():
            data = self._read()
            changed = self._ensure_device_ids(data)
            if changed:
                self._write(data)
            return data
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            "pin": secrets.randbelow(900000) + 100000,
            "devices": [],
        }
        self._write(data)
        return data

    def status(self) -> dict:
        data = self.ensure()
        pin = str(data["pin"])
        return {
            "enabled": True,
            "pin_hint": f"ends in {pin[-2:]}",
            "paired_devices": len(data.get("devices", [])),
        }

    def pair(self, device_name: str, pin: str) -> str:
        data = self.ensure()
        if str(data["pin"]) != pin.strip():
            raise ValueError("Pairing PIN is incorrect.")
        token = secrets.token_urlsafe(32)
        devices = data.setdefault("devices", [])
        devices.append({"id": secrets.token_hex(8), "name": device_name, "token": token})
        data["pin"] = secrets.randbelow(900000) + 100000
        self._write(data)
        return token

    def has_paired_devices(self) -> bool:
        data = self.ensure()
        return bool(data.get("devices", []))

    def validate_token(self, token: str) -> bool:
        if not token:
            return False
        data = self.ensure()
        for device in data.get("devices", []):
            stored = str(device.get("token") or "")
            if stored and hmac.compare_digest(stored, token):
                return True
        return False

    def rotate_pin(self) -> str:
        data = self.ensure()
        data["pin"] = secrets.randbelow(900000) + 100000
        self._write(data)
        return str(data["pin"])

    def devices(self) -> list[dict]:
        data = self.ensure()
        return [{"id": device["id"], "name": device.get("name", "Unknown device")} for device in data.get("devices", [])]

    def revoke_device(self, device_id: str) -> bool:
        data = self.ensure()
        before = len(data.get("devices", []))
        data["devices"] = [device for device in data.get("devices", []) if device.get("id") != device_id]
        changed = len(data["devices"]) != before
        if changed:
            self._write(data)
        return changed

    def _ensure_device_ids(self, data: dict) -> bool:
        changed = False
        for device in data.get("devices", []):
            if not device.get("id"):
                device["id"] = secrets.token_hex(8)
                changed = True
        return changed

    def _read(self) -> dict:
        return json.loads(self.path.read_text(encoding="utf-8"))

    def _write(self, data: dict) -> None:
        self.path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        try:
            self.path.chmod(0o600)
        except PermissionError:
            pass
