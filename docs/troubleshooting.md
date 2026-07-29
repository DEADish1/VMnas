# VMnas Troubleshooting

## Mac Client Cannot Connect

Check:

- Server is powered on.
- Mac is on the same network or connected through remote access.
- URL starts with `https://`.
- Port is `8765`.
- Firewall allows VMnas API.

Try:

```text
https://SERVER-IP:8765/health
```

## Pairing Fails

Check:

- PIN is current.
- PIN was typed before rotation.
- Device is on local network for initial pairing.

On the server:

```bash
sudo vmnas-pairing-code
```

Rotate PIN:

```bash
sudo vmnas-pairing-code --rotate
```

## VM Will Not Start

Check:

- Enough RAM is available.
- ISO path exists.
- Storage pool has free space.
- Another VM is not using the RTX GPU.

Try stopping other VMs before starting a large Windows VM.

## GPU Passthrough Is Not Ready

Check BIOS:

- SVM / AMD-V enabled
- IOMMU enabled
- Above 4G Decoding enabled

Check VMnas GPU page:

- IOMMU group present
- NVIDIA GPU detected
- Host is not using the passthrough GPU as its only active display

## Remote Access Does Not Work

Check:

- Tailscale module installed.
- Server is authenticated to Tailscale.
- Client device is on the same Tailnet.
- Remote IP appears in VMnas Network page.

## Store Module Fails

Check:

- Internet access from the server.
- DNS works.
- Disk has free space.
- Module dependencies are installed.

Open Downloads and retry the failed module.
