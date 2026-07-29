# VMnas Update Process

## Update Types

VMnas has three update layers:

- Server OS and Proxmox packages
- VMnas server agent
- Mac/mobile/browser clients

## Server OS Updates

Use the VMnas client update flow when available. Manual fallback:

```bash
sudo apt update
sudo apt full-upgrade
sudo reboot
```

## VMnas Agent Updates

The VMnas agent lives at:

```text
/opt/vmnas/server-agent
```

Future release installers should:

1. Stop `vmnas-agent`.
2. Back up `/opt/vmnas/server-agent`.
3. Install the new agent.
4. Reinstall Python requirements.
5. Start `vmnas-agent`.
6. Run `/health`.

## Module Updates

Modules live under:

```text
/opt/vmnas/modules
```

Module updates should preserve:

- Config files
- Persistent volumes
- VM templates
- Backup policies

## Client Updates

Mac client updates should preserve the Keychain token. If the token is lost, pair the device again.

## Rollback

Before updating:

1. Create VM snapshots if needed.
2. Back up `/var/lib/vmnas`.
3. Back up `/opt/vmnas/modules`.
4. Confirm remote access is working.

If an update fails:

1. Use Proxmox local console or SSH.
2. Restore the previous VMnas agent directory.
3. Restart `vmnas-agent`.
4. Re-pair a client if token state was restored from an old backup.

