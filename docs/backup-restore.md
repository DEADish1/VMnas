# VMnas Backup And Restore

## Goals

VMnas backups should protect:

- VM definitions
- VM disks
- NAS configuration
- Module state
- Pairing/device state

## Recommended Backup Layout

Use at least one storage target that is not the same disk as the VMnas boot disk.

Recommended targets:

- External USB disk
- Separate internal disk
- NAS replication target
- Remote backup target over VPN

## VM Backups

VMnas uses Proxmox backup primitives for VM snapshots and archives.

Recommended default policy:

- Daily backups
- Keep 7 daily backups
- Keep 4 weekly backups
- Keep 3 monthly backups

The Backup Scheduler module stages this default policy at:

```text
/opt/vmnas/modules/backup-scheduler/backup-policy.json
```

## NAS Data

NAS data should be backed up outside the NAS VM.

Best practice:

- Pass through whole disks or a disk controller to the NAS VM.
- Keep a separate backup of important NAS shares.
- Do not treat snapshots as the only backup.

## Pairing And Module State

Important VMnas state:

```text
/var/lib/vmnas/
/opt/vmnas/modules/
```

Back up these paths after setup and whenever modules are changed.

## Restore Flow

1. Reinstall VMnas if the boot disk failed.
2. Pair an admin device.
3. Restore `/var/lib/vmnas/`.
4. Restore `/opt/vmnas/modules/`.
5. Restore VM backups through the VMnas client or Proxmox.
6. Reboot the server.
7. Confirm VM list, module list, and remote access state.

