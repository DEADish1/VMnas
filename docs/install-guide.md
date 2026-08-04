# Camo NAS Install Guide

## Requirements

- Desktop-class server machine
- CPU with virtualization support enabled
- Enough RAM for the VMs you plan to run
- Dedicated GPU if passthrough is desired
- Wired Ethernet
- USB installer drive
- Dedicated boot/server disk that can be repartitioned
- Any existing data disks you want to keep should remain installed but not selected as the Camo NAS boot/server disk

## BIOS Settings

Enable:

- SVM / AMD-V
- IOMMU
- Above 4G Decoding if available
- UEFI boot

Optional:

- Resizable BAR may be enabled, but disable it if GPU passthrough is unstable.

## Install Steps

1. Boot from the Camo NAS USB installer.
2. Wait for the graphical Camo NAS installer to open.
3. Click through the guided screens:
   - Start
   - Drive
   - Admin
   - Install
4. Confirm the selected server drive. Camo NAS auto-selects the first usable install drive, but you can choose another one.
5. Set the admin username and password.
6. Click `Install Camo NAS Server`.
7. Reboot when prompted.
8. On first boot, Camo NAS automatically brings up a Proxmox bridge named `vmbr0` using DHCP on the detected wired LAN interface.
9. Read the server IP and pairing PIN from the console.
10. Open Camo NAS Admin on the Mac.
11. Scan the QR code or enter:

   ```text
   https://SERVER-IP:8765
   ```

12. Pair with the displayed PIN.

Advanced hardware, NAS resource, and starter module settings are available from the final Install screen, but the normal install path uses recommended defaults automatically.

The installed server should not require manual shell network edits. If the console shows an unreachable address such as `10.0.2.15`, plug Ethernet directly into the home router/network and reinstall with the latest Camo NAS ISO so the installer can create the automatic DHCP bridge.

## Install Disk Layout

Camo NAS does not require every drive in the system to be reformatted. The installer only repartitions the selected server boot disk:

- 1 GB `CAMONAS-EFI` partition for UEFI boot.
- 96 GB `CAMONAS-ROOT` partition by default for Proxmox, Camo NAS services, logs, kernels, and update overhead.
- 64 GB `CAMONAS-ROOT` fallback on smaller supported disks.
- Remaining space formatted as `CAMONAS-DATA` and mounted at `/var/lib/camonas/data`.

Other internal drives are left untouched unless you later choose to format, pass through, or import them from the Camo NAS client.

## After Pairing

Recommended first actions:

1. Enable Remote Access if you want outside-home control.
2. Install Docker Engine from the Store.
3. Install Backup Scheduler from the Store.
4. Upload Windows/Linux installer ISOs.
5. Create the NAS VM.
6. Create Windows and Linux VMs.
