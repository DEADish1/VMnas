# VMnas

VMnas is a plan for turning a desktop-class machine into a small virtualization server with a web UI for creating VMs, assigning CPU/RAM/storage, and running a NAS role. The default NAS setup is also the home VPN and download hub, with WireGuard and Transmission included.

This repository now contains the first implementation skeleton:

- `server-os/`: custom VMnas server ISO builder
- `server-agent/`: FastAPI management agent installed onto the server
- `mac-client/`: native SwiftUI Mac admin client
- `windows-client/`: native WPF Windows installer-USB client

See `ROADMAP.md` for the versioned checklist from `0.5` to `1.0`.

## Recommended Direction

Use the desktop-class machine as the production host and install Proxmox VE. This is the fastest and smoothest path because Proxmox already provides the hypervisor, web UI, VM console access, storage management, snapshots, backups, users, permissions, and API.

The current MacBook can be used for planning, UI prototyping, remote administration, and daily VM access through the Proxmox web UI, SSH, RDP, SPICE, noVNC, or a VPN such as Tailscale.

## Production Host Requirements

- CPU with AMD-V/SVM or Intel VT-x enabled in BIOS
- IOMMU enabled in BIOS if passing through disks, GPUs, or controllers
- Enough RAM for the VMs you plan to run; VMnas detects total/available RAM and sizes presets from the host
- SSD/NVMe boot disk for the hypervisor; only the selected boot disk is repartitioned during install
- Separate storage disks for NAS data when possible; VMnas leaves non-selected disks untouched until the user explicitly assigns or formats them
- Wired Ethernet, ideally 2.5 GbE or faster
- UPS strongly recommended for NAS workloads

## GPU Passthrough Notes

Desktop virtualization hosts are a strong fit for VMnas, especially if the motherboard exposes clean IOMMU groups.

For Windows gaming, SteamOS, CUDA, rendering, AI, or GPU-heavy workloads inside a VM, use PCIe GPU passthrough:

- Enable SVM/AMD-V in BIOS.
- Enable IOMMU in BIOS.
- Prefer a second GPU or integrated graphics for the host if available. A good desktop layout is AMD or integrated graphics for VMnas/Proxmox display duties and an NVIDIA/AMD dedicated GPU assigned to gaming VMs.
- Pass a dedicated GPU through to one VM at a time. VMnas detects AMD, NVIDIA, Intel, and other PCI display controllers and lets the user choose the exact GPU when creating a VM.
- Bind the passthrough GPU to `vfio-pci` on the host so Proxmox/Linux does not claim it.
- Use OVMF/UEFI and machine type `q35` for the passthrough VM.
- Expect the GPU to be unavailable to the host while assigned to a VM.

If the CPU does not have integrated graphics and the dedicated GPU is the only GPU, passthrough is still possible, but setup is more delicate because the host and guest compete for the same display device.

## NAS VM Resource Target

The requested default is calculated from about one quarter of the detected host processor and RAM, then shown as concrete values the user can adjust.

Example on a 12-core, 64 GB host:

- NAS VM CPU: 3 vCPU
- NAS VM RAM: 16 GB
- Remaining host/VM pool: 9 CPU cores and 48 GB RAM, minus hypervisor overhead

VMnas calculates this from detected logical CPU threads and installed RAM instead of assuming a fixed host size.

## Resource Slider Model

The first version can use Proxmox directly. A later VMnas web UI can wrap the Proxmox API and expose:

- CPU slider: vCPU count from 1 to host maximum, capped by policy
- RAM slider: VM memory in GB, with a reserved amount kept for the host
- Disk size slider: virtual disk size or selected physical disk passthrough
- Network mode selector: bridged, NAT, isolated
- OS selector: Linux ISO, Windows ISO, NAS template
- Advanced toggles: autostart, snapshots, balloon memory, disk cache mode
- GPU selector: none, virtual display, or detected GPU passthrough

The backend should translate slider values into Proxmox VM settings through the Proxmox API.

## Build Options

### Selected Option: Install Proxmox VE

Best if the goal is a working server quickly and smoothly.

- Full web UI already exists
- Runs Windows and Linux with KVM
- Supports containers, VM templates, snapshots, bridges, storage pools, permissions, and backups
- NAS VM can be TrueNAS, OpenMediaVault, or Debian + Samba/NFS
- Accessible from the Mac through a browser at `https://SERVER-IP:8006`
- Supports console access from the browser with noVNC
- Supports remote desktop workflows through RDP, SSH, and SPICE depending on guest OS

### Option B: Custom VMnas Controller

Best as a second phase after Proxmox is running.

Suggested stack if building the custom UI:

- Host OS / hypervisor: Proxmox VE
- VM API: Proxmox API
- Backend: FastAPI or Go
- Frontend: React/Vite
- Auth: local admin first, later users/roles
- Storage: Proxmox-managed ZFS or LVM-thin
- Networking: Proxmox-managed Linux bridge

MVP features:

1. Detect host CPU/RAM/disk/network capacity.
2. Upload or register ISO images.
3. Create VM from a form with CPU/RAM sliders.
4. Start, stop, reboot, delete VM.
5. Open VM console through noVNC/SPICE.
6. Create NAS VM preset.
7. Show live resource usage.

## Live System Test

The Mac client includes a `System Test` screen with `Live Mode` and a server benchmark. It continuously refreshes detected hardware and reports what the connected server is suitable for:

- NAS VM
- Linux VMs
- Windows VMs
- Multiple VMs
- Containers
- GPU passthrough
- Secure remote access

The test uses live connected-server data from `/host/resources`, `/host/disks`, `/host/gpus`, and `/host/compatibility`; it does not assume a fixed CPU, RAM, storage layout, or GPU.

After server software is installed, VMnas runs a first-boot benchmark and saves the result. Users can run it again from the Mac client. The benchmark checks short CPU, memory, and disk samples, then recommends conservative limits for simultaneous VMs, Windows VMs, Linux VMs, containers, NAS use, and GPU passthrough.

## NAS VM Notes

For real data safety, avoid stacking too many storage layers. The cleanest NAS VM setup is:

- Pass through a whole disk controller or whole disks when possible.
- Avoid putting important ZFS pools inside a normal virtual disk file unless this is only a lab.
- Give the NAS enough RAM.
- Keep backups separate from the NAS VM.

## Installer Storage Layout

The server installer only modifies the selected VMnas boot/server drive. It creates a 1 GB EFI partition, a right-sized VMnas OS partition with update overhead, and formats the remaining boot-drive space as `VMNAS-DATA` mounted at `/var/lib/vmnas/data`. The default OS partition is 96 GB, with a 64 GB fallback for smaller supported drives. Other disks are detected but not reformatted by the installer.

## Practical First Milestone

Install Proxmox VE on the server desktop, then create:

- One Linux VM
- One Windows VM
- One NAS VM
- A resource policy where NAS defaults to detected vCPU and GB RAM values, adjustable before boot

Access and administer the server from the Mac through:

- Proxmox web UI: `https://SERVER-IP:8006`
- SSH for host maintenance
- noVNC/SPICE for VM console access
- RDP for Windows VM daily use
- SSH or web dashboards for Linux/NAS VM daily use
- Tailscale or WireGuard for secure remote access away from home

After that works, build VMnas as a custom web UI that talks to the Proxmox API.

## Build The Server ISO

The ISO builder needs Docker on macOS or can be run directly from a Debian build host.

```bash
make iso
```

On macOS, Docker Desktop must be installed and running before `make iso` can work. On a Debian build host, install live-build dependencies and run direct mode:

```bash
sudo apt-get install -y live-build xorriso isolinux syslinux-common squashfs-tools
VMNAS_DIRECT_LIVE_BUILD=1 ./server-os/build-iso.sh
```

The expected output is:

```text
dist/vmnas-server-trixie-amd64.iso
dist/vmnas-server-trixie-amd64.iso.sha256
```

The ISO is currently a Debian Trixie live/install base with VMnas install assets included. After installing Debian on the server desktop, run:

```bash
sudo vmnas-install-proxmox
```

That installs Proxmox VE, enables IOMMU boot flags, installs the VMnas agent, and enables the service.

## Simple Graphical Install Flow

The server ISO now includes a VMnas graphical installer shell.

Expected user flow:

1. Boot the server desktop from the VMnas USB installer.
2. The live desktop auto-opens the VMnas installer.
3. Choose hardware defaults, admin name, and starter modules.
4. Click `Install VMnas Server`.
5. When the installer finishes, use the pairing PIN shown on screen.
6. Open VMnas Admin on Mac, iPhone, Android, or a browser client and enter the PIN.

The default module selection installs Security Baseline, OpenMediaVault NAS, Docker Engine, WireGuard Local VPN, and Transmission BitTorrent. Transmission stores downloads under `/srv/vmnas/downloads`, watches `/srv/vmnas/watch`, and exposes its authenticated web UI on port `9091` for trusted LAN/VPN use.

The installer UI lives in:

- `server-os/installer-ui/index.html`
- `server-os/installer-ui/styles.css`
- `server-os/installer-ui/app.js`
- `server-os/installer-api/vmnas_installer_api.py`

The visual style is intentionally aligned with the Mac client: simple sidebar, light panels, 8px corners, clear resource controls, and a module selection grid.

## Run The Server Agent Locally

```bash
make server
```

Local API:

```text
http://127.0.0.1:8765
```

Installed server API:

```text
https://SERVER-IP:8765
```

Useful endpoints:

- `GET /health`
- `GET /pairing/status`
- `POST /pairing/pair`
- `POST /pairing/rotate`
- `GET /pairing/devices`
- `DELETE /pairing/devices/{id}`
- `GET /store/modules`
- `POST /store/modules/{id}/install`
- `GET /store/downloads`
- `GET /host/resources`
- `GET /host/compatibility`
- `GET /host/disks`
- `GET /host/gpus`
- `GET /host/benchmark/latest`
- `POST /host/benchmark/run`
- `GET /discovery`
- `GET /presets/nas`
- `GET /presets/vms`
- `GET /isos`
- `POST /isos/upload`
- `POST /isos/import`
- `GET /os-store/systems`
- `POST /os-store/systems/{id}/download`
- `GET /os-store/downloads`
- `GET /remote/status`
- `POST /remote/enable`
- `POST /remote/disable`
- `GET /system/update/status`
- `POST /system/update/run`
- `GET /vms`
- `POST /vms`
- `POST /vms/{vmid}/start`
- `POST /vms/{vmid}/shutdown`
- `POST /vms/{vmid}/stop`
- `POST /vms/{vmid}/reboot`
- `DELETE /vms/{vmid}`
- `GET /vms/{vmid}/access`
- `GET /vms/{vmid}/snapshots`
- `POST /vms/{vmid}/snapshots`
- `POST /vms/{vmid}/snapshots/{name}/rollback`
- `DELETE /vms/{vmid}/snapshots/{name}`

On a non-Proxmox machine, VM listing and creation return `503` because Proxmox CLI tools are not present.

## Build The Mac Client

Open `mac-client/Package.swift` in Xcode, or build with Swift Package Manager:

```bash
cd mac-client
swift build
swift run VMnasAdmin
```

## Build The Windows Installer-USB Client

On Windows with .NET 8, WSL 2, and Docker Desktop installed and running:

```powershell
dotnet run --project .\windows-client\VMnasAdmin.Windows.csproj
```

The Windows client can build the server ISO through WSL and write it to a selected USB drive after an explicit erase confirmation. See `windows-client/README.md` for prerequisites and usage.

The first Mac client screen connects to the server agent, shows host resources, shows the NAS preset, lists VMs, and opens the Proxmox web UI.

## Mac Client UI Direction

The Mac client is the primary easy-use admin surface. It includes:

- Overview dashboard
- Live System Test
- Virtual machine list
- VM creation screen with resource sliders
- Storage view
- Network view
- OS Store
- Module Store
- Installer USB
- Download status view
- Settings for server URL and access preferences

The Module Store is designed so users can click `Download` for capabilities the server needs. It is hidden in the Mac client until the Mac is paired with and connected to a running VMnas server, because modules install on the server and not on the client device. Current planned modules include:

- OpenMediaVault NAS
- TrueNAS SCALE
- Windows Guest Kit
- Linux Cloud Images
- Docker Engine
- Docker Compose
- Portainer
- K3s Kubernetes
- Home Assistant
- Jellyfin Media Server
- Nextcloud
- Minecraft Server
- PostgreSQL
- Code Server
- GPU Passthrough
- Backup Scheduler
- Tailscale Remote Access
- WireGuard Local VPN Server
- Monitoring Dashboard

The OS Store is separate from the Module Store. It lists common guest operating systems and NAS/router appliances, then downloads supported installer media into the VMnas media library. VMnas supports `.iso`, `.img`, and compressed `.img.bz2` uploads/imports; compressed disk images are expanded to `.img` on the server. OSes that require an official web flow, license agreement, or account open the vendor download page instead.

Current OS Store families:

- Linux: Ubuntu Server, Ubuntu Desktop, Debian, Fedora, Arch Linux, Linux Mint, openSUSE, Rocky Linux, AlmaLinux, Kali, Alpine
- Linux gaming: Bazzite, SteamOS Deck Image, Nobara, CachyOS, Garuda Dragonized Gaming, ChimeraOS, HoloISO, Drauger OS, Batocera.linux
- Windows: Windows 11, Windows Server
- NAS: OpenMediaVault, TrueNAS SCALE
- Network: pfSense CE
- Backup: Proxmox Backup Server

Downloaded Linux media can be launched into the `Create VM` screen from the OS Store. VMnas preselects the downloaded installer media so the user can size the VM and create it without manually hunting for the file path. ISO media is attached as a CD-ROM installer; IMG media, including SteamOS images decompressed from `.img.bz2`, is imported as the VM boot disk.

## Installer USB

The Mac client includes an `Installer USB` screen for preparing the server installer with as few steps as possible. This utility runs on the Mac and is available before pairing with a server. It automatically checks for `dist/vmnas-server-trixie-amd64.iso` and loads the VMnas server ISO into the installer field when present. If the ISO has not been built yet, the screen includes a `Build Server ISO` action. The USB boots the VMnas server installer first, always adds a writable `VMNAS_LOGS` report partition for failed install diagnostics, then can add a separate `VMNAS_ISOS` library partition with extra guest OS media for the installed server to import:

1. Auto-load or build the VMnas server ISO.
2. Optionally add Windows, Linux, NAS, router, rescue, or SteamOS image media to the Server ISO Library.
3. Select a detected removable USB drive.
4. Click `Make Installer USB`.

VMnas only lists external removable/ejectable disks, asks for confirmation before erasing, then uses macOS admin authorization for the actual write.

If the server install fails, the live installer writes a timestamped folder to `VMNAS_LOGS/reports` on the flash drive. The report includes the install log, hardware detection, disk layout, PCI devices, network state, mount table, kernel warnings, and safe install settings with the admin password redacted. Plug the flash drive back into the Mac and use the newest report folder for troubleshooting.

## Windows VM Tuning

When creating a Windows VM, the Mac client can attach optional VMnas Windows tuning media. VMnas generates a supported Windows Setup answer file plus a first-logon PowerShell script so users can choose common setup cleanup options:

- Create a local admin account for the VM.
- Skip Microsoft account screens when supported by Windows Setup.
- Hide privacy and voice prompts.
- Disable consumer app suggestions.
- Disable Widgets/news policy.
- Disable the OneDrive startup entry.

The tuning media does not bypass Windows licensing or activation. It only applies the options selected in the Create VM screen.

The Mac client also includes a `Windows Tuning` screen for testing these settings against an existing VM. Pick the VM, adjust toggles, then attach test media. Inside Windows, open the `VMNAS_WIN_TUNE` disc and run `vmnas-firstlogon.ps1` as Administrator to test the selected settings.

## VM Live View

Running VMs have a `Live` button in the Mac client. It opens an embedded PiP-style console with keyboard/mouse focus, adjustable size, aspect ratio controls, browser fallback, and performance profiles:

- `Local 120`: targets 120 Hz with low compression for home LAN use.
- `Remote 60-120`: targets adaptive 60-120 Hz with compression for outside-home links.
- `60 Hz`: lower bandwidth/battery profile.
- Security Baseline

The client now loads the module catalog from the VMnas agent and sends download/install requests to the server. The first server implementation tracks module state and dependencies persistently; later module installers will replace simulated installs with real package, VM template, and container deployment steps.

Implemented server-side module installers:

- Docker Engine: installs `docker.io` and enables Docker
- Docker Compose: installs Compose plugin support
- Portainer: writes a managed Compose stack and starts it when Docker is available
- OpenMediaVault: stages a NAS VM template
- Windows Guest Kit: stages VirtIO source and Windows VM defaults
- Linux Cloud Images: stages Debian, Ubuntu, and Fedora cloud image sources
- Tailscale: stages remote access notes and installs the package when available
- WireGuard Local VPN Server: installs WireGuard tools and stages server/client VPN templates
- Transmission BitTorrent: deploys a managed Transmission container for the NAS download hub
- Monitoring: installs Prometheus Node Exporter when available
- Backup Scheduler: stages a default VM backup policy

## Pairing Clients

VMnas is designed so a Mac, iPhone, Android phone, tablet, or future web client can pair with the server.

First version flow:

1. On the VMnas server, show the pairing code:

   ```bash
   sudo vmnas-pairing-code
   ```

2. On the Mac client, open `Settings`.
3. Confirm the server URL.
4. Enter the pairing PIN.
5. Click `Pair Device`.

Pairing QR codes use a JSON payload with `type: "vmnas-pairing"`. The QR contains the server API URL, candidate local URLs, PIN, pairing endpoint, status endpoint, discovery endpoint, and payload version so iPhone, Android, Mac, and browser clients can scan once and pair without manually typing the server address.

The server returns a long device token. The Mac client stores this token in macOS Keychain and sends it with admin requests. Once at least one device is paired, VMnas requires a valid paired-device token for server control endpoints.

## Remote Access

After a device is paired locally, VMnas can enable server-side remote access through the Tailscale module.

Flow:

1. Pair the Mac, iPhone, Android device, or browser client on the local network.
2. Open `Network` or `Settings` in the Mac client.
3. Click `Enable Remote Access`.
4. VMnas installs/enables the Tailscale remote access module when available.
5. Once authenticated, the client shows the server's remote IP and VMnas API URL.

This avoids opening router ports directly. VMnas also requires paired-device tokens on admin endpoints once a device has been paired. The installed VMnas agent runs over HTTPS on port `8765`; the installer generates a local server certificate during setup. Tailscale/WireGuard-style remote access gives the outside-home path an encrypted private network layer.

Firewall defaults:

- Allow SSH on `22`
- Allow Proxmox on `8006`
- Allow VMnas HTTPS API on `8765`
- Allow Tailscale UDP on `41641`
- Allow traffic from `tailscale0`
- Drop other inbound traffic by default

To rotate the pairing PIN on the server:

```bash
sudo vmnas-pairing-code --rotate
```

The Mac client can also rotate the pairing PIN, show a QR code for mobile pairing, list paired devices, and revoke devices that should no longer control the server.

## Discovery And Browser Client

Installed VMnas servers advertise themselves on the local network using Avahi/mDNS:

- `_vmnas._tcp` on port `8765`
- `_https._tcp` on port `8765`

The VMnas agent also serves a lightweight browser client at:

```text
https://SERVER-IP:8765/
```

Mobile client API details are documented in `docs/mobile-api.md`.

Additional release docs:

- `docs/install-guide.md`
- `docs/backup-restore.md`
- `docs/troubleshooting.md`
- `docs/update-process.md`

## First-Run Admin Hardening

The installer requires an admin password before installation starts. VMnas also writes SSH hardening defaults:

- Root SSH login disabled
- Empty passwords disabled
- Public key authentication enabled
- Password authentication allowed for the created admin user
- X11 forwarding disabled
