from __future__ import annotations

import json
import shutil
import subprocess

from .models import RemoteAccessStatus
from .module_installers import INSTALLERS


class RemoteAccess:
    def status(self) -> RemoteAccessStatus:
        tailscale = shutil.which("tailscale")
        if not tailscale:
            return RemoteAccessStatus(
                installed=False,
                running=False,
                authenticated=False,
                message="Install the Tailscale Remote Access module to control VMnas away from home.",
            )

        completed = subprocess.run(
            [tailscale, "status", "--json"],
            check=False,
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            return RemoteAccessStatus(
                installed=True,
                running=False,
                authenticated=False,
                message="Tailscale is installed but not connected. Enable remote access to sign in.",
            )

        try:
            payload = json.loads(completed.stdout or "{}")
        except json.JSONDecodeError:
            payload = {}
        self_info = payload.get("Self") or {}
        ips = self_info.get("TailscaleIPs") or []
        remote_ip = ips[0] if ips else ""
        hostname = self_info.get("HostName") or ""
        return RemoteAccessStatus(
            installed=True,
            running=True,
            authenticated=bool(remote_ip),
            hostname=hostname,
            remote_ip=remote_ip,
            admin_url=f"http://{remote_ip}:8765" if remote_ip else "",
            message="Remote access is ready." if remote_ip else "Tailscale is running but not authenticated.",
        )

    def enable(self) -> RemoteAccessStatus:
        if not shutil.which("tailscale"):
            installer = INSTALLERS.get("tailscale-access")
            if installer:
                installer()
        tailscale = shutil.which("tailscale")
        if tailscale:
            subprocess.run(["systemctl", "enable", "--now", "tailscaled"], check=False, text=True, capture_output=True)
            subprocess.run([tailscale, "up", "--ssh"], check=False, text=True, capture_output=True)
        return self.status()

    def disable(self) -> RemoteAccessStatus:
        tailscale = shutil.which("tailscale")
        if tailscale:
            subprocess.run([tailscale, "down"], check=False, text=True, capture_output=True)
        return self.status()
