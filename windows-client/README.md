# Camo NAS Admin for Windows

This native Windows desktop client prepares the Camo NAS server installer USB.

## Requirements

- Windows 10/11 with .NET 8 SDK
- Docker Desktop running
- WSL 2 with a Linux distribution installed
- A removable USB drive; it will be erased

## Run

From the repository root:

```powershell
dotnet run --project .\windows-client\CamoNASAdmin.Windows.csproj
```

Choose an existing `dist\camonas-server-trixie-amd64.iso`, or use **Build ISO (WSL)**. The builder calls `server-os/build-iso.sh` inside WSL, which uses Docker Desktop. Select the intended USB device, type `ERASE`, and approve the Windows administrator prompt.

Only non-system disks reported by Windows as `BusType USB` are listed. Always confirm the physical drive and capacity before writing.

The client writes and then reads back the complete hybrid ISO. It intentionally does not create an extra Windows data partition: adding one to this type of boot image overwrites the installer and makes the USB non-bootable. The ISO itself is labeled `CamoNAS` during the server build; Windows may show its boot partition as unknown or blank, which is expected.

Guest-media copying is temporarily disabled for bootable server USBs. It requires a dedicated boot-library format rather than a Windows partition appended to a hybrid installer image.

For a logged command-line write, run PowerShell as Administrator:

```powershell
.\tools\write-camonas-usb.ps1 -DiskNumber 3 -IsoPath .\dist\camonas-server-trixie-amd64.iso
```
