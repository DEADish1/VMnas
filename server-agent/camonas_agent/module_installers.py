from __future__ import annotations

import shutil
import subprocess
import os
from pathlib import Path


MODULE_ROOT = Path(os.environ.get("CAMONAS_MODULE_ROOT", "/opt/camonas/modules"))


def run_command(args: list[str]) -> None:
    subprocess.run(args, check=True, text=True, capture_output=True)


def module_dir(module_id: str) -> Path:
    path = MODULE_ROOT / module_id
    try:
        path.mkdir(parents=True, exist_ok=True)
        return path
    except PermissionError:
        fallback = Path.home() / ".camonas" / "modules" / module_id
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback


def write_manifest(module_id: str, content: str) -> None:
    (module_dir(module_id) / "manifest.txt").write_text(content, encoding="utf-8")


def apt_install(packages: list[str]) -> None:
    if not shutil.which("apt-get"):
        write_manifest("apt-unavailable", "apt-get was not available. Module install was staged only.\n")
        return
    run_command(["apt-get", "update"])
    run_command(["apt-get", "install", "-y", *packages])


def systemctl_enable(service: str) -> None:
    if shutil.which("systemctl"):
        run_command(["systemctl", "enable", "--now", service])


def write_compose_stack(module_id: str, compose: str, manifest: str) -> None:
    path = module_dir(module_id)
    (path / "compose.yml").write_text(compose, encoding="utf-8")
    write_manifest(module_id, manifest)
    docker = shutil.which("docker")
    if docker:
        try:
            run_command([docker, "compose", "-f", str(path / "compose.yml"), "up", "-d"])
        except subprocess.CalledProcessError:
            pass


def install_docker_engine() -> None:
    write_manifest(
        "docker-engine",
        "Docker Engine module\nInstalls docker.io and enables the Docker service on the Camo NAS host.\n",
    )
    apt_install(["docker.io"])
    systemctl_enable("docker")


def install_docker_compose() -> None:
    write_manifest(
        "docker-compose",
        "Docker Compose module\nInstalls Docker Compose support for Camo NAS app stacks.\n",
    )
    apt_install(["docker-compose-plugin"])


def install_portainer() -> None:
    write_compose_stack(
        "portainer",
        """services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: camonas-portainer
    restart: unless-stopped
    ports:
      - "9443:9443"
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - camonas-portainer-data:/data

volumes:
  camonas-portainer-data:
""",
        "Portainer module\nWrites a managed Compose stack and starts it when Docker Compose is available.\n",
    )


def install_openmediavault() -> None:
    path = module_dir("openmediavault")
    (path / "vm-template.json").write_text(
        """{
  "name": "OpenMediaVault NAS",
  "os_type": "linux",
  "cpu_vcpus": 4,
  "memory_gb": 8,
  "disk_gb": 64,
  "network_bridge": "vmbr0",
  "installer_url": "https://www.openmediavault.org/download.html",
  "bundled_modules": ["wireguard-local-vpn", "transmission"],
  "notes": [
    "Camo NAS treats the NAS role as the home storage, VPN, and download hub.",
    "WireGuard protects remote access to NAS and Camo NAS services.",
    "Transmission is preinstalled as the default BitTorrent client and stores downloads under /srv/camonas/downloads."
  ]
}
""",
        encoding="utf-8",
    )
    (path / "nas-services.md").write_text(
        """# Camo NAS NAS Services

The recommended NAS setup includes:

- OpenMediaVault for SMB/NFS share management.
- WireGuard for secure access back into the home server network.
- Transmission for BitTorrent downloads into `/srv/camonas/downloads`.

Keep Transmission's web UI behind the Camo NAS LAN/VPN path and change the default password before exposing it beyond the trusted home network.
""",
        encoding="utf-8",
    )
    write_manifest("openmediavault", "OpenMediaVault NAS template staged with VPN and Transmission defaults.\n")


def install_windows_guest_kit() -> None:
    path = module_dir("windows-guest-kit")
    (path / "windows-vm-defaults.json").write_text(
        """{
  "machine": "q35",
  "bios": "ovmf",
  "ostype": "win11",
  "scsihw": "virtio-scsi-single",
  "recommended_vcpus": 8,
  "recommended_memory_gb": 16,
  "virtio_iso": "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/"
}
""",
        encoding="utf-8",
    )
    write_manifest("windows-guest-kit", "Windows VM defaults and VirtIO driver source staged.\n")


def install_linux_cloud_images() -> None:
    path = module_dir("linux-cloud-images")
    (path / "images.json").write_text(
        """[
  {"name": "Debian", "url": "https://cloud.debian.org/images/cloud/"},
  {"name": "Ubuntu", "url": "https://cloud-images.ubuntu.com/"},
  {"name": "Fedora", "url": "https://alt.fedoraproject.org/cloud/"}
]
""",
        encoding="utf-8",
    )
    write_manifest("linux-cloud-images", "Linux cloud image sources staged.\n")


def install_tailscale_access() -> None:
    path = module_dir("tailscale-access")
    (path / "install-notes.txt").write_text(
        "Tailscale remote access module.\nOfficial installer: https://tailscale.com/install.sh\n",
        encoding="utf-8",
    )
    write_manifest("tailscale-access", "Tailscale remote access module staged.\n")
    apt_install(["tailscale"])
    systemctl_enable("tailscaled")


def install_wireguard_local_vpn() -> None:
    path = module_dir("wireguard-local-vpn")
    (path / "wg0.conf.example").write_text(
        """[Interface]
Address = 10.44.0.1/24
ListenPort = 51820
PrivateKey = SERVER_PRIVATE_KEY

# Add one block per paired client after generating client keys.
# [Peer]
# PublicKey = CLIENT_PUBLIC_KEY
# AllowedIPs = 10.44.0.2/32
""",
        encoding="utf-8",
    )
    (path / "client-template.conf").write_text(
        """[Interface]
Address = 10.44.0.2/32
PrivateKey = CLIENT_PRIVATE_KEY
DNS = 10.44.0.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = YOUR_HOME_PUBLIC_IP_OR_DDNS:51820
AllowedIPs = 10.44.0.0/24
PersistentKeepalive = 25
""",
        encoding="utf-8",
    )
    (path / "setup-notes.txt").write_text(
        """WireGuard Local VPN Server

1. Forward UDP 51820 from the home router to the Camo NAS server.
2. Generate server and client keys with wg genkey and wg pubkey.
3. Copy wg0.conf.example to /etc/wireguard/wg0.conf and fill in keys.
4. Add one peer per paired Mac, iPhone, Android, or Windows client.
5. Enable with: systemctl enable --now wg-quick@wg0

Keep WireGuard client profiles private. Anyone with a client private key can attempt to join the VPN.
""",
        encoding="utf-8",
    )
    write_manifest("wireguard-local-vpn", "WireGuard local VPN server staged with server and client templates.\n")
    apt_install(["wireguard", "qrencode"])


def install_transmission() -> None:
    write_compose_stack(
        "transmission",
        """services:
  transmission:
    image: lscr.io/linuxserver/transmission:latest
    container_name: camonas-transmission
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - USER=camonas
      - PASS=camonas-change-me
      - WHITELIST=127.0.0.1,10.*.*.*,172.16.*.*,172.17.*.*,172.18.*.*,172.19.*.*,172.20.*.*,172.21.*.*,172.22.*.*,172.23.*.*,172.24.*.*,172.25.*.*,172.26.*.*,172.27.*.*,172.28.*.*,172.29.*.*,172.30.*.*,172.31.*.*,192.168.*.*
    ports:
      - "9091:9091"
      - "51413:51413"
      - "51413:51413/udp"
    volumes:
      - /srv/camonas/apps/transmission/config:/config
      - /srv/camonas/downloads:/downloads
      - /srv/camonas/watch:/watch
""",
        """Transmission module
Managed Transmission BitTorrent Compose stack staged with downloads in /srv/camonas/downloads.
Default web UI: http://SERVER-IP:9091
Default credentials: camonas / camonas-change-me
Change the password before enabling remote access. Prefer access through WireGuard or Tailscale instead of exposing port 9091 to the public Internet.
""",
    )


def install_monitoring() -> None:
    write_manifest("monitoring", "Monitoring module installs prometheus-node-exporter when available.\n")
    apt_install(["prometheus-node-exporter"])
    systemctl_enable("prometheus-node-exporter")


def install_backup_scheduler() -> None:
    path = module_dir("backup-scheduler")
    (path / "backup-policy.json").write_text(
        """{
  "enabled": true,
  "schedule": "daily",
  "retention": {
    "daily": 7,
    "weekly": 4,
    "monthly": 3
  },
  "mode": "snapshot"
}
""",
        encoding="utf-8",
    )
    write_manifest("backup-scheduler", "Default VM backup policy staged.\n")


def install_plex() -> None:
    write_compose_stack(
        "plex",
        """services:
  plex:
    image: lscr.io/linuxserver/plex:latest
    container_name: camonas-plex
    network_mode: host
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - VERSION=docker
    volumes:
      - /srv/camonas/apps/plex/config:/config
      - /srv/camonas/media/tv:/tv
      - /srv/camonas/media/movies:/movies
      - /srv/camonas/media/music:/music
""",
        "Plex module\nManaged Plex Compose stack staged with /srv/camonas/media library mappings.\n",
    )


def install_jellyfin() -> None:
    write_compose_stack(
        "jellyfin",
        """services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: camonas-jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    volumes:
      - /srv/camonas/apps/jellyfin/config:/config
      - /srv/camonas/apps/jellyfin/cache:/cache
      - /srv/camonas/media:/media
      - /srv/camonas/photos:/photos
""",
        "Jellyfin module\nManaged Jellyfin Compose stack staged with Camo NAS media and photo library mappings.\n",
    )


def install_emby() -> None:
    write_compose_stack(
        "emby",
        """services:
  emby:
    image: lscr.io/linuxserver/emby:latest
    container_name: camonas-emby
    restart: unless-stopped
    ports:
      - "8097:8096"
      - "8921:8920"
    volumes:
      - /srv/camonas/apps/emby/config:/config
      - /srv/camonas/media:/media
""",
        "Emby module\nManaged Emby Compose stack staged with /srv/camonas/media mapping.\n",
    )


def install_navidrome() -> None:
    write_compose_stack(
        "navidrome",
        """services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: camonas-navidrome
    restart: unless-stopped
    ports:
      - "4533:4533"
    environment:
      - ND_SCANSCHEDULE=1h
      - ND_LOGLEVEL=info
      - ND_SESSIONTIMEOUT=24h
      - ND_BASEURL=
    volumes:
      - /srv/camonas/apps/navidrome/data:/data
      - /srv/camonas/media/music:/music:ro
""",
        "Navidrome module\nManaged private music streaming stack staged for /srv/camonas/media/music.\n",
    )


def install_audiobookshelf() -> None:
    write_compose_stack(
        "audiobookshelf",
        """services:
  audiobookshelf:
    image: ghcr.io/advplyr/audiobookshelf:latest
    container_name: camonas-audiobookshelf
    restart: unless-stopped
    ports:
      - "13378:80"
    volumes:
      - /srv/camonas/media/audiobooks:/audiobooks
      - /srv/camonas/media/podcasts:/podcasts
      - /srv/camonas/apps/audiobookshelf/config:/config
      - /srv/camonas/apps/audiobookshelf/metadata:/metadata
""",
        "Audiobookshelf module\nManaged audiobook and podcast streaming stack staged under the Camo NAS media library.\n",
    )


def install_ersatztv() -> None:
    write_compose_stack(
        "ersatztv",
        """services:
  ersatztv:
    image: jasongdove/ersatztv:latest
    container_name: camonas-ersatztv
    restart: unless-stopped
    ports:
      - "8409:8409"
    volumes:
      - /srv/camonas/apps/ersatztv/config:/root/.local/share/ersatztv
      - /srv/camonas/media:/media:ro
""",
        "ErsatzTV module\nManaged custom channel streaming stack staged against the Camo NAS media library.\n",
    )


def install_arr_media_stack() -> None:
    write_compose_stack(
        "arr-media-stack",
        """services:
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: camonas-prowlarr
    restart: unless-stopped
    ports:
      - "9696:9696"
    volumes:
      - /srv/camonas/apps/prowlarr/config:/config
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: camonas-sonarr
    restart: unless-stopped
    ports:
      - "8989:8989"
    volumes:
      - /srv/camonas/apps/sonarr/config:/config
      - /srv/camonas/media/tv:/tv
      - /srv/camonas/downloads:/downloads
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: camonas-radarr
    restart: unless-stopped
    ports:
      - "7878:7878"
    volumes:
      - /srv/camonas/apps/radarr/config:/config
      - /srv/camonas/media/movies:/movies
      - /srv/camonas/downloads:/downloads
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: camonas-qbittorrent
    restart: unless-stopped
    ports:
      - "8081:8080"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - /srv/camonas/apps/qbittorrent/config:/config
      - /srv/camonas/downloads:/downloads
""",
        "Arr media automation module\nSonarr, Radarr, Prowlarr, and qBittorrent Compose stack staged.\n",
    )


def install_immich() -> None:
    write_compose_stack(
        "immich",
        """services:
  immich-server:
    image: ghcr.io/immich-app/immich-server:release
    container_name: camonas-immich
    restart: unless-stopped
    ports:
      - "2283:2283"
    environment:
      - DB_HOSTNAME=immich-postgres
      - DB_USERNAME=immich
      - DB_PASSWORD=camonas-change-me
      - DB_DATABASE_NAME=immich
      - REDIS_HOSTNAME=immich-redis
    volumes:
      - /srv/camonas/photos/immich:/usr/src/app/upload
  immich-redis:
    image: redis:7-alpine
    container_name: camonas-immich-redis
    restart: unless-stopped
  immich-postgres:
    image: tensorchord/pgvecto-rs:pg14-v0.2.0
    container_name: camonas-immich-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=immich
      - POSTGRES_PASSWORD=camonas-change-me
      - POSTGRES_DB=immich
    volumes:
      - /srv/camonas/apps/immich/postgres:/var/lib/postgresql/data
""",
        "Immich module\nPhoto backup Compose stack staged. Change the default database password before remote exposure.\n",
    )


def install_photoprism() -> None:
    write_compose_stack(
        "photoprism",
        """services:
  photoprism:
    image: photoprism/photoprism:latest
    container_name: camonas-photoprism
    restart: unless-stopped
    ports:
      - "2342:2342"
    environment:
      - PHOTOPRISM_ADMIN_PASSWORD=camonas-change-me
    volumes:
      - /srv/camonas/photos:/photoprism/originals
      - /srv/camonas/apps/photoprism/storage:/photoprism/storage
""",
        "PhotoPrism module\nPhoto library Compose stack staged. Change the default admin password before use.\n",
    )


def install_filebrowser() -> None:
    write_compose_stack(
        "filebrowser",
        """services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: camonas-filebrowser
    restart: unless-stopped
    ports:
      - "8082:80"
    volumes:
      - /srv/camonas/shares:/srv
      - /srv/camonas/apps/filebrowser/database:/database
      - /srv/camonas/apps/filebrowser/config:/config
""",
        "File Browser module\nWeb file manager Compose stack staged for /srv/camonas/shares.\n",
    )


def install_samba_shares() -> None:
    path = module_dir("samba-shares")
    (path / "smb.conf").write_text(
        """[camonas]
   path = /srv/camonas/shares
   browseable = yes
   writable = yes
   guest ok = no
   create mask = 0664
   directory mask = 0775
""",
        encoding="utf-8",
    )
    write_manifest("samba-shares", "SMB share manager staged. Install applies Samba when apt-get is available.\n")
    apt_install(["samba"])
    systemctl_enable("smbd")


def install_nfs_shares() -> None:
    path = module_dir("nfs-shares")
    (path / "exports").write_text(
        "/srv/camonas/shares  *(rw,sync,no_subtree_check)\n",
        encoding="utf-8",
    )
    write_manifest("nfs-shares", "NFS share manager staged. Install applies nfs-kernel-server when apt-get is available.\n")
    apt_install(["nfs-kernel-server"])
    systemctl_enable("nfs-server")


def install_syncthing() -> None:
    write_compose_stack(
        "syncthing",
        """services:
  syncthing:
    image: syncthing/syncthing:latest
    container_name: camonas-syncthing
    restart: unless-stopped
    ports:
      - "8384:8384"
      - "22000:22000/tcp"
      - "22000:22000/udp"
      - "21027:21027/udp"
    volumes:
      - /srv/camonas/apps/syncthing/config:/var/syncthing/config
      - /srv/camonas/sync:/var/syncthing
""",
        "Syncthing module\nPeer-to-peer sync Compose stack staged for /srv/camonas/sync.\n",
    )


def install_paperless_ngx() -> None:
    write_compose_stack(
        "paperless-ngx",
        """services:
  paperless:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: camonas-paperless
    restart: unless-stopped
    ports:
      - "8001:8000"
    environment:
      - PAPERLESS_REDIS=redis://paperless-redis:6379
      - PAPERLESS_DBHOST=paperless-postgres
      - PAPERLESS_DBUSER=paperless
      - PAPERLESS_DBPASS=camonas-change-me
    volumes:
      - /srv/camonas/apps/paperless/data:/usr/src/paperless/data
      - /srv/camonas/documents/media:/usr/src/paperless/media
      - /srv/camonas/documents/export:/usr/src/paperless/export
      - /srv/camonas/documents/consume:/usr/src/paperless/consume
  paperless-redis:
    image: redis:7-alpine
    restart: unless-stopped
  paperless-postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      - POSTGRES_USER=paperless
      - POSTGRES_PASSWORD=camonas-change-me
      - POSTGRES_DB=paperless
    volumes:
      - /srv/camonas/apps/paperless/postgres:/var/lib/postgresql/data
""",
        "Paperless-ngx module\nDocument archive Compose stack staged. Change default database password before use.\n",
    )


def install_vaultwarden() -> None:
    write_compose_stack(
        "vaultwarden",
        """services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: camonas-vaultwarden
    restart: unless-stopped
    ports:
      - "8083:80"
    volumes:
      - /srv/camonas/apps/vaultwarden/data:/data
""",
        "Vaultwarden module\nPrivate password vault Compose stack staged. Use HTTPS before remote access.\n",
    )


def install_nginx_proxy_manager() -> None:
    write_compose_stack(
        "nginx-proxy-manager",
        """services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: camonas-nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - /srv/camonas/apps/nginx-proxy-manager/data:/data
      - /srv/camonas/apps/nginx-proxy-manager/letsencrypt:/etc/letsencrypt
""",
        "Nginx Proxy Manager module\nReverse proxy Compose stack staged for service routing and certificates.\n",
    )


def install_adguard_home() -> None:
    write_compose_stack(
        "adguard-home",
        """services:
  adguard:
    image: adguard/adguardhome:latest
    container_name: camonas-adguard
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000"
    volumes:
      - /srv/camonas/apps/adguard/work:/opt/adguardhome/work
      - /srv/camonas/apps/adguard/conf:/opt/adguardhome/conf
""",
        "AdGuard Home module\nDNS filtering Compose stack staged. Confirm no other DNS service is using port 53.\n",
    )


def install_duplicati() -> None:
    write_compose_stack(
        "duplicati",
        """services:
  duplicati:
    image: lscr.io/linuxserver/duplicati:latest
    container_name: camonas-duplicati
    restart: unless-stopped
    ports:
      - "8200:8200"
    volumes:
      - /srv/camonas/apps/duplicati/config:/config
      - /srv/camonas/backups:/backups
      - /srv/camonas/shares:/source
""",
        "Duplicati module\nEncrypted backup Compose stack staged for Camo NAS shares.\n",
    )


def install_restic_backups() -> None:
    path = module_dir("restic-backups")
    (path / "backup-example.sh").write_text(
        """#!/usr/bin/env bash
set -euo pipefail
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/srv/camonas/backups/restic}"
restic backup /etc/pve /srv/camonas/shares /opt/camonas/modules
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
""",
        encoding="utf-8",
    )
    write_manifest("restic-backups", "Restic backup scripts staged. Configure RESTIC_REPOSITORY and password before scheduling.\n")
    apt_install(["restic"])


INSTALLERS = {
    "docker-engine": install_docker_engine,
    "docker-compose": install_docker_compose,
    "portainer": install_portainer,
    "openmediavault": install_openmediavault,
    "windows-guest-kit": install_windows_guest_kit,
    "linux-cloud-images": install_linux_cloud_images,
    "tailscale-access": install_tailscale_access,
    "wireguard-local-vpn": install_wireguard_local_vpn,
    "transmission": install_transmission,
    "monitoring": install_monitoring,
    "backup-scheduler": install_backup_scheduler,
    "plex": install_plex,
    "jellyfin": install_jellyfin,
    "emby": install_emby,
    "navidrome": install_navidrome,
    "audiobookshelf": install_audiobookshelf,
    "ersatztv": install_ersatztv,
    "arr-media-stack": install_arr_media_stack,
    "immich": install_immich,
    "photoprism": install_photoprism,
    "filebrowser": install_filebrowser,
    "samba-shares": install_samba_shares,
    "nfs-shares": install_nfs_shares,
    "syncthing": install_syncthing,
    "paperless-ngx": install_paperless_ngx,
    "vaultwarden": install_vaultwarden,
    "nginx-proxy-manager": install_nginx_proxy_manager,
    "adguard-home": install_adguard_home,
    "duplicati": install_duplicati,
    "restic-backups": install_restic_backups,
}
