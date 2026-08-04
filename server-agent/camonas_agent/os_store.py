from __future__ import annotations

import json
import os
import threading
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .isos import IsoStore
from .models import OsDownloadResponse, OsStoreItem


OS_CATALOG: list[dict] = [
    {
        "id": "ubuntu-server-2404",
        "name": "Ubuntu Server",
        "family": "Linux",
        "summary": "Popular Linux server OS for Docker, apps, and services.",
        "details": "Good default for general Linux VMs, Docker hosts, databases, and web apps.",
        "version": "24.04 LTS",
        "size_mb": 3100,
        "tags": ["Linux", "Server", "LTS"],
        "license": "Open source",
        "download_url": "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso",
        "filename": "ubuntu-24.04.4-live-server-amd64.iso",
        "download_page": "https://ubuntu.com/download/server",
        "install_notes": ["Use the Linux preset.", "Enable OpenSSH during install if you want terminal access."],
    },
    {
        "id": "ubuntu-desktop-2404",
        "name": "Ubuntu Desktop",
        "family": "Linux",
        "summary": "Friendly desktop Linux VM.",
        "details": "Best first Linux desktop VM for browser, office, and general use.",
        "version": "24.04 LTS",
        "size_mb": 5900,
        "tags": ["Linux", "Desktop", "Beginner"],
        "license": "Open source",
        "download_url": "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso",
        "filename": "ubuntu-24.04.4-desktop-amd64.iso",
        "download_page": "https://ubuntu.com/download/desktop",
        "install_notes": ["Use 4 vCPU and 8 GB RAM or higher for a smooth desktop."],
    },
    {
        "id": "debian-netinst",
        "name": "Debian Net Installer",
        "family": "Linux",
        "summary": "Small, stable Debian installer.",
        "details": "Lean server or desktop base with long-term stability and a small ISO download.",
        "version": "Stable",
        "size_mb": 760,
        "tags": ["Linux", "Server", "Stable"],
        "license": "Open source",
        "download_url": "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.0.0-amd64-netinst.iso",
        "download_page": "https://www.debian.org/download",
        "install_notes": ["Use the Linux preset.", "The installer downloads packages during setup."],
    },
    {
        "id": "fedora-workstation",
        "name": "Fedora Workstation",
        "family": "Linux",
        "summary": "Modern GNOME desktop Linux VM.",
        "details": "Good for testing newer Linux kernels, desktop tools, and developer workflows.",
        "version": "Latest",
        "size_mb": 2400,
        "tags": ["Linux", "Desktop", "Developer"],
        "license": "Open source",
        "download_url": "",
        "download_page": "https://fedoraproject.org/workstation/download",
        "download_supported": False,
        "install_notes": ["Open the download page and upload/import the ISO after download."],
    },
    {
        "id": "arch-linux",
        "name": "Arch Linux",
        "family": "Linux",
        "summary": "Rolling Linux installer for advanced users.",
        "details": "Minimal installer for users who want full control over a Linux VM.",
        "version": "Rolling",
        "size_mb": 1200,
        "tags": ["Linux", "Advanced", "Rolling"],
        "license": "Open source",
        "download_url": "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso",
        "download_page": "https://archlinux.org/download/",
        "install_notes": ["Use the Linux preset.", "Installer is command-line driven."],
    },
    {
        "id": "linux-mint",
        "name": "Linux Mint Cinnamon",
        "family": "Linux",
        "summary": "Comfortable desktop Linux VM.",
        "details": "A familiar desktop for users coming from Windows-like layouts.",
        "version": "Latest",
        "size_mb": 2900,
        "tags": ["Linux", "Desktop", "Beginner"],
        "license": "Open source",
        "download_url": "",
        "download_page": "https://linuxmint.com/download.php",
        "download_supported": False,
        "install_notes": ["Open the download page and upload/import the ISO after download."],
    },
    {
        "id": "opensuse-leap",
        "name": "openSUSE Leap",
        "family": "Linux",
        "summary": "Stable openSUSE server or desktop installer.",
        "details": "Good for SUSE-style administration, YaST tools, and stable Linux VM testing.",
        "version": "15.6",
        "size_mb": 4300,
        "tags": ["Linux", "Stable", "SUSE"],
        "license": "Open source",
        "download_url": "https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64-Current.iso",
        "filename": "openSUSE-Leap-15.6-DVD-x86_64-Current.iso",
        "download_page": "https://get.opensuse.org/leap/",
        "install_notes": ["Use the Linux preset.", "Works as server or desktop depending packages selected."],
    },
    {
        "id": "opensuse-tumbleweed",
        "name": "openSUSE Tumbleweed",
        "family": "Linux",
        "summary": "Rolling openSUSE Linux VM.",
        "details": "Good for testing newer kernels, packages, and desktop stacks.",
        "version": "Rolling",
        "size_mb": 4700,
        "tags": ["Linux", "Rolling", "SUSE"],
        "license": "Open source",
        "download_url": "https://download.opensuse.org/tumbleweed/iso/openSUSE-Tumbleweed-DVD-x86_64-Current.iso",
        "filename": "openSUSE-Tumbleweed-DVD-x86_64-Current.iso",
        "download_page": "https://get.opensuse.org/tumbleweed/",
        "install_notes": ["Use the Linux preset.", "Rolling distro; update frequently."],
    },
    {
        "id": "rocky-linux-9",
        "name": "Rocky Linux",
        "family": "Linux",
        "summary": "Enterprise-style RHEL-compatible Linux VM.",
        "details": "Good for server labs, enterprise Linux apps, databases, and hosting.",
        "version": "9 latest",
        "size_mb": 1900,
        "tags": ["Linux", "Server", "Enterprise"],
        "license": "Open source",
        "download_url": "https://dl.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-minimal.iso",
        "filename": "Rocky-9-latest-x86_64-minimal.iso",
        "download_page": "https://rockylinux.org/download",
        "install_notes": ["Use the Linux preset.", "Minimal ISO is a clean server base."],
    },
    {
        "id": "almalinux-9",
        "name": "AlmaLinux",
        "family": "Linux",
        "summary": "Enterprise-style RHEL-compatible Linux VM.",
        "details": "Good for enterprise app testing, hosting, and long-term server workloads.",
        "version": "9 latest",
        "size_mb": 1900,
        "tags": ["Linux", "Server", "Enterprise"],
        "license": "Open source",
        "download_url": "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso",
        "filename": "AlmaLinux-9-latest-x86_64-minimal.iso",
        "download_page": "https://almalinux.org/get-almalinux/",
        "install_notes": ["Use the Linux preset.", "Minimal ISO is a clean server base."],
    },
    {
        "id": "kali-linux",
        "name": "Kali Linux",
        "family": "Linux",
        "summary": "Security testing Linux VM.",
        "details": "Use for authorized security labs and learning, isolated from production networks.",
        "version": "2026.2",
        "size_mb": 4400,
        "tags": ["Linux", "Security", "Desktop"],
        "license": "Open source",
        "download_url": "https://cdimage.kali.org/current/kali-linux-2026.2-installer-amd64.iso",
        "filename": "kali-linux-2026.2-installer-amd64.iso",
        "download_page": "https://www.kali.org/get-kali/",
        "install_notes": ["Use an isolated network for labs.", "Only test systems you own or are authorized to test."],
    },
    {
        "id": "alpine-standard",
        "name": "Alpine Linux",
        "family": "Linux",
        "summary": "Tiny Linux server VM.",
        "details": "Very small distro for containers, appliances, and lightweight services.",
        "version": "3.22 x86_64",
        "size_mb": 250,
        "tags": ["Linux", "Tiny", "Server"],
        "license": "Open source",
        "download_url": "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-standard-3.22.0-x86_64.iso",
        "filename": "alpine-standard-3.22.0-x86_64.iso",
        "download_page": "https://alpinelinux.org/downloads/",
        "install_notes": ["Use low RAM and disk settings.", "Installer is command-line focused."],
    },
    {
        "id": "bazzite-nvidia",
        "name": "Bazzite NVIDIA Desktop",
        "family": "Linux",
        "summary": "Fedora Atomic gaming desktop with NVIDIA support.",
        "details": "Good first choice for an RTX gaming VM with Steam, gaming tools, and immutable updates.",
        "version": "Stable",
        "size_mb": 7600,
        "tags": ["Linux", "Gaming", "NVIDIA"],
        "license": "Open source",
        "download_url": "https://download.bazzite.gg/bazzite-nvidia-open-stable-amd64.iso",
        "filename": "bazzite-nvidia-open-stable-amd64.iso",
        "download_page": "https://bazzite.gg/",
        "install_notes": ["Use the Linux preset with GPU passthrough for best gaming performance.", "Prefer this image for NVIDIA RTX desktops."],
    },
    {
        "id": "steamos-deck-image",
        "name": "SteamOS Deck Image",
        "family": "Linux",
        "summary": "Valve SteamOS recovery image for Steam Deck-style VM experiments.",
        "details": "Official Valve SteamOS Deck Image is distributed as a compressed .img.bz2 after accepting Valve's SteamOS EULA. Camo NAS can import the downloaded .img.bz2 and create a VM from the decompressed disk image.",
        "version": "Latest",
        "size_mb": 3000,
        "tags": ["Linux", "Gaming", "SteamOS", "IMG"],
        "license": "Valve SteamOS EULA",
        "download_page": "https://store.steampowered.com/steamos/download?ver=steamdeck",
        "download_supported": False,
        "install_notes": ["Open Valve's page, accept the EULA, then upload/import the .img.bz2 file.", "Use the Linux preset, UEFI boot, and GPU passthrough for serious gaming tests.", "This is a disk image, so Camo NAS imports it as the VM boot disk instead of attaching it as a CD-ROM installer."],
    },
    {
        "id": "bazzite-desktop",
        "name": "Bazzite Desktop",
        "family": "Linux",
        "summary": "Fedora Atomic gaming desktop for AMD/Intel graphics.",
        "details": "Gaming-ready Linux desktop for Steam, Proton, Lutris, and daily desktop use.",
        "version": "Stable",
        "size_mb": 7400,
        "tags": ["Linux", "Gaming", "Steam"],
        "license": "Open source",
        "download_url": "https://download.bazzite.gg/bazzite-stable-amd64.iso",
        "filename": "bazzite-stable-amd64.iso",
        "download_page": "https://bazzite.gg/",
        "install_notes": ["Use the Linux preset.", "Choose the NVIDIA image instead when passing through an RTX GPU."],
    },
    {
        "id": "bazzite-deck-nvidia",
        "name": "Bazzite Deck NVIDIA",
        "family": "Linux",
        "summary": "Console-style Steam Gaming Mode image with NVIDIA support.",
        "details": "Best for living-room or controller-first gaming VMs when GPU passthrough is available.",
        "version": "Stable",
        "size_mb": 7600,
        "tags": ["Linux", "Gaming", "Console"],
        "license": "Open source",
        "download_url": "https://download.bazzite.gg/bazzite-deck-nvidia-stable-amd64.iso",
        "filename": "bazzite-deck-nvidia-stable-amd64.iso",
        "download_page": "https://bazzite.gg/",
        "install_notes": ["Use GPU passthrough and the Live VM viewer for setup.", "This is the console-style Steam Gaming Mode variant."],
    },
    {
        "id": "nobara-official-nvidia",
        "name": "Nobara Official NVIDIA",
        "family": "Linux",
        "summary": "Fedora-based desktop tuned for games, streaming, and creators.",
        "details": "Nobara includes gaming fixes, codecs, WINE tooling, OBS-oriented defaults, and an NVIDIA image.",
        "version": "43",
        "size_mb": 5400,
        "tags": ["Linux", "Gaming", "NVIDIA"],
        "license": "Open source",
        "download_url": "https://nobara-images.nobaraproject.org/Nobara-43-Official-NV-2026-04-24.iso",
        "filename": "Nobara-43-Official-NV-2026-04-24.iso",
        "download_page": "https://nobaraproject.org/download.html",
        "install_notes": ["Use the Linux preset.", "Good fit for RTX passthrough and desktop gaming."],
    },
    {
        "id": "nobara-steam-htpc-nvidia",
        "name": "Nobara Steam HTPC NVIDIA",
        "family": "Linux",
        "summary": "Nobara console-style Steam image for living-room VMs.",
        "details": "Steam-focused Nobara variant for big-screen setups with NVIDIA support.",
        "version": "43",
        "size_mb": 5600,
        "tags": ["Linux", "Gaming", "HTPC"],
        "license": "Open source",
        "download_url": "https://nobara-images.nobaraproject.org/Nobara-43-Steam-HTPC-NV-2026-04-25.iso",
        "filename": "Nobara-43-Steam-HTPC-NV-2026-04-25.iso",
        "download_page": "https://nobaraproject.org/download.html",
        "install_notes": ["Use the Linux preset with more RAM for a smooth Steam session.", "Use GPU passthrough for actual gaming workloads."],
    },
    {
        "id": "cachyos-desktop",
        "name": "CachyOS Desktop",
        "family": "Linux",
        "summary": "Performance-focused Arch Linux desktop for gaming.",
        "details": "Optimized Arch-based distro with gaming-friendly kernels and desktop tooling.",
        "version": "2026.06.28",
        "size_mb": 3200,
        "tags": ["Linux", "Gaming", "Performance"],
        "license": "Open source",
        "download_url": "https://cdn77.cachyos.org/ISO/desktop/260628/cachyos-desktop-linux-260628.iso",
        "filename": "cachyos-desktop-linux-260628.iso",
        "download_page": "https://cachyos.org/download/",
        "install_notes": ["Use the Linux preset.", "Advanced users can tune CPU scheduler and kernel choices after install."],
    },
    {
        "id": "cachyos-handheld",
        "name": "CachyOS Handheld",
        "family": "Linux",
        "summary": "GameMode-like CachyOS image for handheld-style gaming.",
        "details": "Handheld-focused CachyOS image with preinstalled gaming tools and controller-first defaults.",
        "version": "2026.06.28",
        "size_mb": 3200,
        "tags": ["Linux", "Gaming", "Handheld"],
        "license": "Open source",
        "download_url": "https://cdn77.cachyos.org/ISO/handheld/260628/cachyos-handheld-linux-260628.iso",
        "filename": "cachyos-handheld-linux-260628.iso",
        "download_page": "https://cachyos.org/download/",
        "install_notes": ["Best for handheld-style or console-style experiments.", "Use desktop CachyOS for a standard VM desktop."],
    },
    {
        "id": "garuda-gaming",
        "name": "Garuda Dragonized Gaming",
        "family": "Linux",
        "summary": "Arch-based gaming desktop with gaming tools preloaded.",
        "details": "Garuda's gaming edition includes a tuned desktop, gaming utilities, and a friendly Arch-based installer.",
        "version": "Latest",
        "size_mb": 3300,
        "tags": ["Linux", "Gaming", "Arch"],
        "license": "Open source",
        "download_url": "https://iso.builds.garudalinux.org/iso/latest/garuda/dr460nized-gaming/latest.iso?sourceforge=1",
        "filename": "garuda-dr460nized-gaming-latest.iso",
        "download_page": "https://garudalinux.org/downloads",
        "install_notes": ["Use the Linux preset.", "Good for testing a preloaded gaming desktop."],
    },
    {
        "id": "chimeraos",
        "name": "ChimeraOS",
        "family": "Linux",
        "summary": "Console-like Linux gaming OS for Steam and couch gaming.",
        "details": "Use for controller-first gaming appliance experiments. Download selection is kept on the official page.",
        "version": "Latest",
        "size_mb": 2500,
        "tags": ["Linux", "Gaming", "Console"],
        "license": "Open source",
        "download_page": "https://chimeraos.org/",
        "download_supported": False,
        "install_notes": ["Open the official page and import the ISO after download.", "GPU passthrough is recommended."],
    },
    {
        "id": "holoiso",
        "name": "HoloISO",
        "family": "Linux",
        "summary": "Community SteamOS-like PC image.",
        "details": "Steam Deck-style experience for PCs. Official project downloads are release-page driven.",
        "version": "Latest",
        "size_mb": 4500,
        "tags": ["Linux", "Gaming", "SteamOS"],
        "license": "Open source",
        "download_page": "https://holoiso.com/",
        "download_supported": False,
        "install_notes": ["Open the release page and import the ISO after download.", "Community SteamOS-style images may be more experimental."],
    },
    {
        "id": "drauger-os",
        "name": "Drauger OS",
        "family": "Linux",
        "summary": "Ubuntu-based gaming desktop distro.",
        "details": "Gaming-focused Ubuntu-based distro with performance and desktop tweaks.",
        "version": "7.8",
        "size_mb": 4300,
        "tags": ["Linux", "Gaming", "Ubuntu"],
        "license": "Open source",
        "download_page": "https://draugeros.org/download",
        "download_supported": False,
        "install_notes": ["Open the official page and import the ISO after download.", "Check project notes because newer beta builds may be unstable."],
    },
    {
        "id": "batocera-linux",
        "name": "Batocera.linux",
        "family": "Linux",
        "summary": "Retro-gaming appliance OS.",
        "details": "Emulation-focused Linux distribution for retro gaming libraries and controller-first setups.",
        "version": "Latest",
        "size_mb": 3000,
        "tags": ["Linux", "Gaming", "Retro"],
        "license": "Open source",
        "download_page": "https://batocera.org/download",
        "download_supported": False,
        "install_notes": ["Use for retro-gaming appliance VMs.", "Open the official page and import the correct x86_64 image."],
    },
    {
        "id": "windows-11",
        "name": "Windows 11",
        "family": "Windows",
        "summary": "Windows desktop VM for apps, testing, and remote desktop.",
        "details": "Microsoft requires downloading Windows media from their official flow, then uploading/importing the ISO.",
        "version": "Current",
        "size_mb": 6500,
        "tags": ["Windows", "Desktop", "RDP"],
        "license": "Microsoft license required",
        "download_page": "https://www.microsoft.com/software-download/windows11",
        "download_supported": False,
        "install_notes": ["Install the Windows Guest Kit module for VirtIO drivers.", "Use the Windows preset."],
    },
    {
        "id": "windows-server",
        "name": "Windows Server",
        "family": "Windows",
        "summary": "Windows Server evaluation VM.",
        "details": "Useful for Active Directory labs, Windows services, and admin testing.",
        "version": "Evaluation",
        "size_mb": 6200,
        "tags": ["Windows", "Server", "Evaluation"],
        "license": "Microsoft evaluation/license required",
        "download_page": "https://www.microsoft.com/evalcenter/",
        "download_supported": False,
        "install_notes": ["Install the Windows Guest Kit module for VirtIO drivers.", "Use the Windows preset."],
    },
    {
        "id": "openmediavault-iso",
        "name": "OpenMediaVault",
        "family": "NAS",
        "summary": "Lightweight NAS OS for SMB/NFS shares.",
        "details": "Recommended lightweight NAS VM when you want simple file sharing sized from detected host resources.",
        "version": "Latest",
        "size_mb": 1200,
        "tags": ["NAS", "SMB", "NFS"],
        "license": "Open source",
        "download_page": "https://www.openmediavault.org/download.html",
        "download_supported": False,
        "install_notes": ["Use the NAS preset.", "Allocate 4 vCPU and 8 GB RAM by default."],
    },
    {
        "id": "truenas-scale-iso",
        "name": "TrueNAS SCALE",
        "family": "NAS",
        "summary": "Advanced ZFS NAS OS.",
        "details": "Use for a NAS VM when you want ZFS tools and advanced storage workflows.",
        "version": "Latest",
        "size_mb": 1800,
        "tags": ["NAS", "ZFS", "Advanced"],
        "license": "Open source",
        "download_page": "https://www.truenas.com/download-truenas-scale/",
        "download_supported": False,
        "install_notes": ["Use more RAM if possible.", "Best with dedicated disks or disk passthrough."],
    },
    {
        "id": "proxmox-backup-server",
        "name": "Proxmox Backup Server",
        "family": "Backup",
        "summary": "Backup appliance for VM archives.",
        "details": "Can run as a VM for testing backup workflows, though a separate physical host is better for real backup safety.",
        "version": "Latest",
        "size_mb": 1200,
        "tags": ["Backup", "Proxmox"],
        "license": "Open source",
        "download_page": "https://www.proxmox.com/en/downloads",
        "download_supported": False,
        "install_notes": ["Use a Linux/server style VM.", "Avoid storing only backups on the same physical disk."],
    },
    {
        "id": "pfsense",
        "name": "pfSense CE",
        "family": "Network",
        "summary": "Firewall/router OS for network labs.",
        "details": "Useful for VLAN, firewall, and routing lab VMs.",
        "version": "Latest",
        "size_mb": 900,
        "tags": ["Firewall", "Router", "Network"],
        "license": "Open source",
        "download_page": "https://www.pfsense.org/download/",
        "download_supported": False,
        "install_notes": ["Requires careful network bridge setup.", "Avoid replacing your real router until tested."],
    },
]


@dataclass
class OsStore:
    path: Path
    iso_store: IsoStore

    @classmethod
    def default(cls, iso_store: IsoStore) -> "OsStore":
        path = Path(os.environ.get("CAMONAS_OS_STORE", "/var/lib/camonas/os-downloads.json"))
        if not os.access(path.parent, os.W_OK):
            path = Path.home() / ".camonas" / "os-downloads.json"
        return cls(path=path, iso_store=iso_store)

    def systems(self) -> list[OsStoreItem]:
        state = self._state()
        return [self._with_state(item, state) for item in OS_CATALOG]

    def downloads(self) -> list[OsStoreItem]:
        return [item for item in self.systems() if item.install_state in {"downloading", "installed", "failed"}]

    def download(self, os_id: str) -> OsDownloadResponse:
        item = next((entry for entry in OS_CATALOG if entry["id"] == os_id), None)
        if item is None:
            raise ValueError("Unknown OS.")
        if not item.get("download_supported", True) or not item.get("download_url"):
            return OsDownloadResponse(
                id=os_id,
                install_state="manual",
                progress=0,
                message=f"Open the official download page: {item.get('download_page', '')}",
            )
        state = self._state()
        current = state.setdefault(os_id, {"install_state": "available", "progress": 0})
        if current["install_state"] == "installed":
            return OsDownloadResponse(id=os_id, install_state="installed", progress=100, message="ISO is already downloaded.")
        current.update({"install_state": "downloading", "progress": max(current.get("progress", 0), 1)})
        self._write_state(state)
        threading.Thread(target=self._download_iso, args=(item,), daemon=True).start()
        return OsDownloadResponse(id=os_id, install_state="downloading", progress=current["progress"], message="Download started.")

    def _download_iso(self, item: dict) -> None:
        os_id = item["id"]
        try:
            self.iso_store.path.mkdir(parents=True, exist_ok=True)
            filename = item.get("filename") or Path(item["download_url"]).name or f"{os_id}.iso"
            if not filename.lower().endswith((".iso", ".img", ".img.bz2")):
                filename = f"{os_id}.iso"
            dest = self.iso_store.path / self.iso_store._safe_name(self.iso_store._stored_filename(filename))
            request = urllib.request.Request(item["download_url"], headers={"User-Agent": "CamoNAS/0.9"})
            compressed_dest = dest.with_suffix(dest.suffix + ".bz2") if filename.lower().endswith(".img.bz2") else dest
            with urllib.request.urlopen(request, timeout=30) as response, compressed_dest.open("wb") as handle:
                total = int(response.headers.get("content-length") or 0)
                downloaded = 0
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    handle.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        progress = min(99, max(1, int(downloaded / total * 100)))
                        self._set_state(os_id, "downloading", progress)
            if filename.lower().endswith(".img.bz2"):
                self.iso_store._decompress_bz2(compressed_dest, dest)
                compressed_dest.unlink(missing_ok=True)
            self._set_state(os_id, "installed", 100, str(dest))
        except Exception:
            self._set_state(os_id, "failed", 0)

    def _with_state(self, item: dict, state: dict) -> OsStoreItem:
        os_state = state.get(item["id"], {})
        iso_path = os_state.get("iso_path", "")
        if not iso_path and os_state.get("install_state") == "installed":
            filename = item.get("filename") or Path(item.get("download_url", "")).name
            candidate = self.iso_store.path / self.iso_store._safe_name(self.iso_store._stored_filename(filename or f"{item['id']}.iso"))
            if candidate.exists():
                iso_path = str(candidate)
        return OsStoreItem(
            **item,
            install_state=os_state.get("install_state", "available"),
            progress=os_state.get("progress", 0),
            iso_path=iso_path,
        )

    def _set_state(self, os_id: str, install_state: str, progress: int, iso_path: str = "") -> None:
        state = self._state()
        current = state.get(os_id, {})
        state[os_id] = {
            "install_state": install_state,
            "progress": progress,
            "iso_path": iso_path or current.get("iso_path", ""),
        }
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
