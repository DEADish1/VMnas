from __future__ import annotations

import json
import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .module_installers import INSTALLERS
from .models import ModuleInstallResponse, StoreModule


CATALOG: list[dict] = [
    {
        "id": "security-baseline",
        "name": "Security Baseline",
        "category": "Security",
        "summary": "Firewall, SSH hardening, and update policy.",
        "details": "Applies safer defaults for SSH, firewall rules, update checks, and admin access.",
        "size_mb": 24,
        "required": True,
        "tags": ["Required", "Firewall"],
        "dependencies": [],
    },
    {
        "id": "openmediavault",
        "name": "OpenMediaVault NAS",
        "category": "NAS",
        "summary": "NAS, VPN, and download hub sized from detected host resources.",
        "details": "Downloads the OpenMediaVault installer, creates a tuned NAS VM preset from live CPU/RAM detection, enables SMB/NFS share helpers, and bundles WireGuard plus Transmission defaults for secure remote access and downloads.",
        "size_mb": 1260,
        "tags": ["Recommended", "NAS", "SMB", "VPN", "Transmission"],
        "dependencies": ["wireguard-local-vpn", "transmission"],
    },
    {
        "id": "truenas-scale",
        "name": "TrueNAS SCALE",
        "category": "NAS",
        "summary": "Advanced ZFS NAS VM template.",
        "details": "Downloads TrueNAS SCALE media and configures a VM profile for disk passthrough and higher memory allocation.",
        "size_mb": 1900,
        "tags": ["ZFS", "NAS"],
        "dependencies": [],
    },
    {
        "id": "windows-guest-kit",
        "name": "Windows Guest Kit",
        "category": "VM Tools",
        "summary": "VirtIO drivers and Windows VM defaults.",
        "details": "Stages VirtIO driver sources, Windows VM defaults, RDP shortcuts, and optional VMnas Windows setup tuning media.",
        "size_mb": 720,
        "tags": ["Windows", "Drivers"],
        "dependencies": [],
    },
    {
        "id": "linux-cloud-images",
        "name": "Linux Cloud Images",
        "category": "VM Tools",
        "summary": "Ubuntu, Debian, and Fedora VM templates.",
        "details": "Adds quick-create templates for common Linux servers with cloud-init support.",
        "size_mb": 1600,
        "tags": ["Linux", "Templates"],
        "dependencies": [],
    },
    {
        "id": "docker-engine",
        "name": "Docker Engine",
        "category": "Containers",
        "summary": "Run containers directly on VMnas.",
        "details": "Installs Docker Engine, enables the service, configures storage, and adds a guarded API bridge for the Mac client.",
        "size_mb": 180,
        "tags": ["Docker", "Containers", "Runtime"],
        "dependencies": [],
    },
    {
        "id": "docker-compose",
        "name": "Docker Compose",
        "category": "Containers",
        "summary": "Deploy multi-container apps from compose files.",
        "details": "Adds Compose support, project folders, environment-file handling, and start/stop/update controls.",
        "size_mb": 46,
        "tags": ["Compose", "Stacks"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "portainer",
        "name": "Portainer",
        "category": "Containers",
        "summary": "Web dashboard for Docker containers.",
        "details": "Deploys Portainer as a managed container and adds a launch button from the Mac client.",
        "size_mb": 320,
        "tags": ["Docker", "Dashboard"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "k3s",
        "name": "K3s Kubernetes",
        "category": "Containers",
        "summary": "Lightweight Kubernetes lab module.",
        "details": "Installs K3s for users who want Kubernetes-style app hosting without a full cluster.",
        "size_mb": 95,
        "tags": ["Kubernetes", "Lab"],
        "dependencies": [],
    },
    {
        "id": "nvidia-rtx-passthrough",
        "name": "GPU Passthrough",
        "category": "GPU",
        "summary": "VFIO setup and GPU VM assignment tools.",
        "details": "Detects AMD, NVIDIA, Intel, and other PCI display devices, checks IOMMU groups, configures VFIO support, and enables per-VM GPU assignment.",
        "size_mb": 120,
        "tags": ["GPU", "VFIO", "AMD", "NVIDIA", "Intel", "Gaming"],
        "dependencies": [],
    },
    {
        "id": "tailscale-access",
        "name": "Tailscale Remote Access",
        "category": "Network",
        "summary": "Secure access to VMnas away from home.",
        "details": "Installs Tailscale on the server and exposes safe links for Proxmox, VMnas, SSH, and selected guest services.",
        "size_mb": 48,
        "tags": ["VPN", "Remote"],
        "dependencies": [],
    },
    {
        "id": "wireguard-local-vpn",
        "name": "WireGuard Local VPN Server",
        "category": "Network",
        "summary": "Host your own VPN on the VMnas server.",
        "details": "Installs WireGuard, stages a local server configuration, enables IP forwarding notes, and creates client-profile instructions for secure access outside the home network.",
        "size_mb": 32,
        "tags": ["VPN", "WireGuard", "Local"],
        "dependencies": [],
    },
    {
        "id": "transmission",
        "name": "Transmission BitTorrent",
        "category": "NAS",
        "summary": "Preinstalled BitTorrent client for the NAS download hub.",
        "details": "Deploys Transmission with persistent config, downloads, and watch folders under /srv/vmnas. The web UI is intended for trusted LAN/VPN access and ships with change-me credentials.",
        "size_mb": 220,
        "tags": ["NAS", "Downloads", "BitTorrent", "VPN"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "monitoring",
        "name": "Monitoring Dashboard",
        "category": "Monitoring",
        "summary": "Live CPU, RAM, disk, temperature, and VM graphs.",
        "details": "Adds host and guest metric collection with clean charts for daily operations.",
        "size_mb": 240,
        "tags": ["Graphs", "Health"],
        "dependencies": [],
    },
    {
        "id": "backup-scheduler",
        "name": "Backup Scheduler",
        "category": "Backup",
        "summary": "Scheduled VM backups and retention policies.",
        "details": "Adds backup schedules, retention rules, and storage target checks for VM snapshots and archives.",
        "size_mb": 64,
        "tags": ["Snapshots", "Retention"],
        "dependencies": [],
    },
    {
        "id": "home-assistant",
        "name": "Home Assistant",
        "category": "Apps",
        "summary": "Smart home server template.",
        "details": "Deploys Home Assistant with persistent storage, restart policy, and LAN access.",
        "size_mb": 760,
        "tags": ["Smart Home", "Docker"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "jellyfin",
        "name": "Jellyfin Media Server",
        "category": "Apps",
        "summary": "Self-hosted movies, shows, and music.",
        "details": "Deploys Jellyfin with movies, TV, music, and photo folders from the VMnas media library. Intended for easy LAN or VPN streaming without subscriptions.",
        "size_mb": 520,
        "tags": ["Media", "Streaming", "Movies", "Music"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "plex",
        "name": "Plex Media Server",
        "category": "Apps",
        "summary": "Polished streaming server for movies, shows, and music.",
        "details": "Deploys Plex with media libraries, hardware-transcode notes for detected GPUs, and LAN discovery-friendly ports.",
        "size_mb": 610,
        "tags": ["Media", "Streaming", "GPU"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "emby",
        "name": "Emby Media Server",
        "category": "Apps",
        "summary": "Personal media server with broad client support.",
        "details": "Deploys Emby with persistent configuration, media folder mapping, and optional GPU acceleration notes.",
        "size_mb": 540,
        "tags": ["Media", "Streaming"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "navidrome",
        "name": "Navidrome Music Server",
        "category": "Apps",
        "summary": "Fast private music streaming.",
        "details": "Deploys Navidrome for personal music streaming from /srv/vmnas/media/music with persistent playlists, users, and scan data.",
        "size_mb": 120,
        "tags": ["Media", "Music", "Streaming"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "audiobookshelf",
        "name": "Audiobookshelf",
        "category": "Apps",
        "summary": "Audiobook and podcast streaming.",
        "details": "Deploys Audiobookshelf with audiobook, podcast, and metadata folders under the VMnas media library.",
        "size_mb": 340,
        "tags": ["Media", "Audiobooks", "Podcasts"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "ersatztv",
        "name": "ErsatzTV",
        "category": "Apps",
        "summary": "Create live-style channels from your media.",
        "details": "Deploys ErsatzTV so users can build custom streaming channels from local movies, shows, and videos stored on the NAS.",
        "size_mb": 520,
        "tags": ["Media", "Channels", "Streaming"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "arr-media-stack",
        "name": "Arr Media Automation",
        "category": "Apps",
        "summary": "Sonarr, Radarr, Prowlarr, and qBittorrent stack.",
        "details": "Stages a Compose stack for TV/movie automation with shared downloads, media folders, and VPN-ready network notes.",
        "size_mb": 980,
        "tags": ["Media", "Automation", "Compose"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "immich",
        "name": "Immich Photos",
        "category": "Apps",
        "summary": "Private phone photo and video backup.",
        "details": "Stages Immich with PostgreSQL, Redis, upload storage, and mobile backup-ready defaults.",
        "size_mb": 1300,
        "tags": ["Photos", "Backup", "Mobile"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "photoprism",
        "name": "PhotoPrism",
        "category": "Apps",
        "summary": "AI-friendly private photo library.",
        "details": "Deploys PhotoPrism with originals/import folders, persistent database storage, and LAN access.",
        "size_mb": 920,
        "tags": ["Photos", "Gallery"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "filebrowser",
        "name": "File Browser",
        "category": "NAS",
        "summary": "Simple web file manager for NAS shares.",
        "details": "Deploys File Browser against the VMnas shares folder for browser-based upload, download, rename, and delete.",
        "size_mb": 95,
        "tags": ["NAS", "Files", "Web"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "samba-shares",
        "name": "SMB Share Manager",
        "category": "NAS",
        "summary": "Windows and macOS file sharing.",
        "details": "Installs Samba and stages a default shares configuration for Time Machine-style and general LAN shares.",
        "size_mb": 82,
        "tags": ["SMB", "Shares", "Mac"],
        "dependencies": [],
    },
    {
        "id": "nfs-shares",
        "name": "NFS Share Manager",
        "category": "NAS",
        "summary": "Fast Linux and virtualization file shares.",
        "details": "Installs NFS server support and stages export templates for Linux clients and VM storage.",
        "size_mb": 56,
        "tags": ["NFS", "Shares", "Linux"],
        "dependencies": [],
    },
    {
        "id": "syncthing",
        "name": "Syncthing",
        "category": "NAS",
        "summary": "Peer-to-peer folder sync.",
        "details": "Deploys Syncthing with persistent config and a shared data folder for laptop, phone, and server sync.",
        "size_mb": 120,
        "tags": ["Sync", "Files"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "paperless-ngx",
        "name": "Paperless-ngx",
        "category": "Apps",
        "summary": "Document scanning and archive server.",
        "details": "Stages Paperless-ngx with PostgreSQL, Redis, consume/export folders, and OCR-ready storage.",
        "size_mb": 780,
        "tags": ["Documents", "OCR"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "vaultwarden",
        "name": "Vaultwarden",
        "category": "Security",
        "summary": "Lightweight private password vault.",
        "details": "Deploys Vaultwarden with persistent encrypted storage and reverse-proxy guidance for remote access.",
        "size_mb": 150,
        "tags": ["Passwords", "Security"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "nginx-proxy-manager",
        "name": "Nginx Proxy Manager",
        "category": "Network",
        "summary": "Friendly reverse proxy and certificate manager.",
        "details": "Deploys Nginx Proxy Manager for local service names, HTTPS certificates, and app routing.",
        "size_mb": 460,
        "tags": ["Proxy", "HTTPS", "Apps"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "adguard-home",
        "name": "AdGuard Home",
        "category": "Network",
        "summary": "Network-wide DNS ad blocking.",
        "details": "Deploys AdGuard Home with persistent work/config folders and DNS port mapping notes.",
        "size_mb": 180,
        "tags": ["DNS", "Privacy"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "duplicati",
        "name": "Duplicati",
        "category": "Backup",
        "summary": "Encrypted backups to cloud or another NAS.",
        "details": "Deploys Duplicati with access to VMnas share folders and encrypted backup target configuration.",
        "size_mb": 260,
        "tags": ["Backup", "Encrypted"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "restic-backups",
        "name": "Restic Backup Tools",
        "category": "Backup",
        "summary": "Fast encrypted snapshot backups.",
        "details": "Installs Restic and stages scripts for encrypted backups of VM configs, shares, and module data.",
        "size_mb": 42,
        "tags": ["Backup", "CLI", "Encrypted"],
        "dependencies": [],
    },
    {
        "id": "nextcloud",
        "name": "Nextcloud",
        "category": "Apps",
        "summary": "Private cloud files, sync, and sharing.",
        "details": "Deploys Nextcloud with a database, persistent storage, and reverse-proxy-ready settings.",
        "size_mb": 850,
        "tags": ["Cloud", "Files"],
        "dependencies": ["docker-engine", "docker-compose"],
    },
    {
        "id": "minecraft-server",
        "name": "Minecraft Server",
        "category": "Apps",
        "summary": "Game server template with backups.",
        "details": "Creates a managed Minecraft server container with memory controls, scheduled backups, and console access.",
        "size_mb": 420,
        "tags": ["Game Server", "Java"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "postgres",
        "name": "PostgreSQL",
        "category": "Developer",
        "summary": "Managed database for local apps.",
        "details": "Deploys PostgreSQL with persistent volumes, backup hooks, and local network access controls.",
        "size_mb": 390,
        "tags": ["Database", "Dev"],
        "dependencies": ["docker-engine"],
    },
    {
        "id": "code-server",
        "name": "Code Server",
        "category": "Developer",
        "summary": "Browser-based VS Code on VMnas.",
        "details": "Runs a secure code-server instance for editing files and projects hosted on the server.",
        "size_mb": 610,
        "tags": ["IDE", "Remote"],
        "dependencies": ["docker-engine"],
    },
]


@dataclass
class ModuleStore:
    path: Path

    @classmethod
    def default(cls) -> "ModuleStore":
        path = Path(os.environ.get("VMNAS_MODULE_STORE", "/var/lib/vmnas/modules.json"))
        if not os.access(path.parent, os.W_OK):
            path = Path.home() / ".vmnas" / "modules.json"
        return cls(path=path)

    def modules(self) -> list[StoreModule]:
        state = self._state()
        return [self._module_with_state(item, state) for item in CATALOG]

    def downloads(self) -> list[StoreModule]:
        return [module for module in self.modules() if module.install_state in {"downloading", "installed", "failed"}]

    def install(self, module_id: str) -> ModuleInstallResponse:
        module_ids = {item["id"] for item in CATALOG}
        if module_id not in module_ids:
            raise ValueError("Unknown module.")
        state = self._state()
        current = state.setdefault(module_id, {"install_state": "available", "progress": 0})
        if current["install_state"] == "installed":
            return ModuleInstallResponse(id=module_id, install_state="installed", progress=100)
        current.update({"install_state": "downloading", "progress": max(current.get("progress", 0), 1)})
        self._write_state(state)
        threading.Thread(target=self._install_with_dependencies, args=(module_id,), daemon=True).start()
        return ModuleInstallResponse(id=module_id, install_state="downloading", progress=current["progress"])

    def _module_with_state(self, item: dict, state: dict) -> StoreModule:
        module_state = state.get(item["id"], {})
        return StoreModule(
            **item,
            install_state=module_state.get("install_state", "available"),
            progress=module_state.get("progress", 0),
        )

    def _install_with_dependencies(self, module_id: str) -> None:
        catalog = {item["id"]: item for item in CATALOG}
        installed: set[str] = set()

        def install_one(selected_id: str) -> None:
            if selected_id in installed:
                return
            installed.add(selected_id)
            for dependency_id in catalog.get(selected_id, {}).get("dependencies", []):
                install_one(dependency_id)
            self._simulate_install(selected_id)

        install_one(module_id)

    def _simulate_install(self, module_id: str) -> None:
        try:
            for progress in (10, 25, 45):
                self._set_module_state(module_id, "downloading", progress)
                time.sleep(0.25)
            installer = INSTALLERS.get(module_id)
            if installer:
                self._set_module_state(module_id, "downloading", 70)
                installer()
            else:
                self._set_module_state(module_id, "downloading", 70)
                time.sleep(0.5)
            self._set_module_state(module_id, "installed", 100)
        except Exception:
            self._set_module_state(module_id, "failed", 0)

    def _set_module_state(self, module_id: str, install_state: str, progress: int) -> None:
        state = self._state()
        state[module_id] = {"install_state": install_state, "progress": progress}
        self._write_state(state)

    def _state(self) -> dict:
        if not self.path.exists():
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._write_state({})
        return json.loads(self.path.read_text(encoding="utf-8"))

    def _write_state(self, state: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(state, indent=2), encoding="utf-8")
        try:
            self.path.chmod(0o600)
        except PermissionError:
            pass
