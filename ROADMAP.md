# VMnas Roadmap

This checklist tracks the path from the current prototype foundation to a usable `1.0` release.

Version numbering starts at `0.5` because the project already has a server OS scaffold, management agent, Mac client, module store UI, pairing flow, and graphical installer shell.

## 0.5 - Foundation Prototype

- [x] Create project workspace and README
- [x] Choose Proxmox/Debian as the server base
- [x] Add custom ISO build scaffold
- [x] Add server install script for Proxmox setup
- [x] Add VMnas server agent scaffold
- [x] Add host resource detection endpoint
- [x] Add live system compatibility test endpoint
- [x] Add server benchmark endpoint and first-boot benchmark service
- [x] Add NAS 25% CPU/RAM preset endpoint
- [x] Add VM listing endpoint
- [x] Add VM creation skeleton
- [x] Add VM start, shutdown, force stop, and reboot endpoints
- [x] Add native SwiftUI Mac admin client scaffold
- [x] Add Mac dashboard
- [x] Add Mac Live System Test screen
- [x] Add Mac benchmark results and safe workload recommendations
- [x] Add VM table with lifecycle controls
- [x] Add VM creation screen with CPU/RAM/disk sliders
- [x] Add module store UI
- [x] Lock Module Store until the Mac is paired with and connected to a server
- [x] Add store modules for NAS, Docker, GPU passthrough, backup, monitoring, VPN, apps, and developer tools
- [x] Add pairing PIN/token API foundation
- [x] Add Mac pairing screen
- [x] Add graphical server installer shell
- [x] Add installer pairing PIN display
- [x] Add installer module selection screen
- [x] Add installer autostart/kiosk wiring
- [x] Verify Python syntax checks
- [x] Verify Mac client builds

## 0.6 - Installable Server Alpha

- [x] Add disk selection UI
- [x] Add destructive install confirmation
- [x] Add automatic disk partitioning
- [x] Add bootloader installation
- [x] Add install progress phases instead of raw log only
- [x] Add install failure recovery screen
- [x] Add post-install reboot prompt
- [x] Add Mac USB Maker for server installer media
- [x] Add multi-ISO USB library staging for guest/server ISO import
- [x] Add native Windows installer-USB client
- [x] Add Windows removable-drive safety checks and erase confirmation
- [x] Add Windows multi-ISO guest media library support
- [ ] Add Windows managed guest-media download catalog with checksum verification
- [x] Add a visible `VMnas` USB data-partition label
- [x] Ensure VMnas server agent starts after reboot
- [ ] Ensure Proxmox web UI is reachable after reboot
- [x] Generate pairing PIN automatically after install
- [x] Show server IP address and pairing code on first boot
- [x] Build first local ISO artifact
- [ ] Test ISO boot in a VM
- [ ] Test ISO boot on physical desktop server

## 0.7 - Real Module Store

- [x] Add `/store/modules` endpoint
- [x] Add `/store/modules/{id}/install` endpoint
- [x] Add `/store/downloads` endpoint
- [x] Add download progress tracking
- [x] Add installed module inventory
- [x] Add module dependency handling
- [x] Add Docker Engine installer module
- [x] Add Docker Compose installer module
- [x] Add Portainer installer module
- [x] Add OpenMediaVault template module
- [x] Make default NAS setup include WireGuard VPN and Transmission BitTorrent
- [x] Add Windows VirtIO driver module
- [x] Add Linux cloud image module
- [x] Add Tailscale remote access module
- [x] Add WireGuard local VPN server module
- [x] Add monitoring module
- [x] Add backup scheduler module
- [x] Connect Mac Store download buttons to server endpoints

## 0.8 - VM Management Beta

- [x] Add full VM creation through Mac client
- [x] Add ISO upload/import flow
- [x] Add expanded Linux ISO downloader and Create VM handoff
- [x] Add Linux gaming distro OS Store entries
- [x] Add Windows VM preset
- [x] Add optional Windows VM setup tuning media
- [x] Add Windows tuning test screen for existing VMs
- [x] Add Linux VM preset
- [x] Add NAS VM preset
- [x] Add CPU/RAM validation against host capacity
- [x] Add warning when RAM is over-allocated
- [x] Add GPU passthrough detection
- [x] Add GPU IOMMU group check
- [x] Add GPU assignment UI
- [x] Add VM console launch buttons
- [x] Add RDP launch helper for Windows VMs
- [x] Add embedded VM Live view with local 120 Hz and remote adaptive profiles
- [x] Add SSH launch helper for Linux VMs
- [x] Add snapshot create/restore/delete
- [x] Add VM delete confirmation
- [x] Add Windows paired-server dashboard and VM controls
- [x] Add Windows pairing-token storage
- [ ] Add Windows ISO upload and VM creation flow
- [ ] Add Windows module store and remote-access controls

## 0.9 - Paired Device Security And Mobile Ready

- [x] Store Mac pairing token in macOS Keychain
- [x] Require device token on admin endpoints
- [x] Add paired device list
- [x] Add revoke paired device action
- [x] Add rotate pairing PIN action in Mac client
- [x] Add QR code pairing option
- [x] Add local network server discovery
- [x] Add browser client shell
- [x] Define iPhone client API contract
- [x] Define Android client API contract
- [x] Add HTTPS setup for VMnas agent
- [x] Add first-run password/admin hardening
- [x] Add firewall rules for VMnas services

## 1.0 - First Usable Release

- [ ] Build signed/reproducible ISO release artifact
- [ ] Complete end-to-end install on physical desktop server
- [ ] Complete end-to-end Mac pairing
- [ ] Create NAS VM from Mac client
- [ ] Create Windows VM from Mac client
- [x] Create Linux VM from Mac client
- [ ] Stop one VM and start another from Mac client
- [ ] Install Docker module from Store
- [ ] Install backup module from Store
- [ ] Verify GPU passthrough workflow
- [x] Verify remote access workflow
- [x] Add backup/restore documentation
- [x] Add install guide with screenshots
- [x] Add troubleshooting guide
- [x] Add update process
- [ ] Run final physical hardware test
- [ ] Tag `v1.0.0`
