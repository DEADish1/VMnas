# VMnas Install Guide

## Requirements

- Desktop-class server machine
- CPU with virtualization support enabled
- Enough RAM for the VMs you plan to run
- Dedicated GPU if passthrough is desired
- Wired Ethernet
- USB installer drive
- Dedicated boot/server disk that can be repartitioned
- Any existing data disks you want to keep should remain installed but not selected as the VMnas boot/server disk

## BIOS Settings

Enable:

- SVM / AMD-V
- IOMMU
- Above 4G Decoding if available
- UEFI boot

Optional:

- Resizable BAR may be enabled, but disable it if GPU passthrough is unstable.

## Install Steps

1. Boot from the VMnas USB installer.
2. Wait for the graphical VMnas installer to open.
3. Confirm detected CPU, RAM, network, and the selected server boot disk.
4. Type `ERASE`.
5. Set the admin username and password.
6. Leave the default starter modules selected unless you want to change them.
7. Click `Install VMnas Server`.
8. Reboot when prompted.
9. On first boot, VMnas automatically brings up a Proxmox bridge named `vmbr0` using DHCP on the detected wired LAN interface.
10. Read the server IP and pairing PIN from the console.
11. Open VMnas Admin on the Mac.
12. Scan the QR code or enter:

   ```text
   https://SERVER-IP:8765
   ```

13. Pair with the displayed PIN.

The installed server should not require manual shell network edits. If the console shows an unreachable address such as `10.0.2.15`, plug Ethernet directly into the home router/network and reinstall with the latest VMnas ISO so the installer can create the automatic DHCP bridge.

## Install Disk Layout

VMnas does not require every drive in the system to be reformatted. The installer only repartitions the selected server boot disk:

- 1 GB `VMNAS-EFI` partition for UEFI boot.
- 96 GB `VMNAS-ROOT` partition by default for Proxmox, VMnas services, logs, kernels, and update overhead.
- 64 GB `VMNAS-ROOT` fallback on smaller supported disks.
- Remaining space formatted as `VMNAS-DATA` and mounted at `/var/lib/vmnas/data`.

Other internal drives are left untouched unless you later choose to format, pass through, or import them from the VMnas client.

## After Pairing

Recommended first actions:

1. Enable Remote Access if you want outside-home control.
2. Install Docker Engine from the Store.
3. Install Backup Scheduler from the Store.
4. Upload Windows/Linux installer ISOs.
5. Create the NAS VM.
6. Create Windows and Linux VMs.
