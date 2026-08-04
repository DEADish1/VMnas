# Camo NAS Update Process

## Update Types

Camo NAS has three update layers:

- Server OS and Proxmox packages
- Camo NAS server agent
- Mac/mobile/browser clients

## Server OS Updates

Use the Camo NAS client update flow when available. Manual fallback:

```bash
sudo apt update
sudo apt full-upgrade
sudo reboot
```

## Camo NAS Agent Updates

The Camo NAS agent lives at:

```text
/opt/camonas/server-agent
```

Future release installers should:

1. Stop `camonas-agent`.
2. Back up `/opt/camonas/server-agent`.
3. Install the new agent.
4. Reinstall Python requirements.
5. Start `camonas-agent`.
6. Run `/health`.

## Module Updates

Modules live under:

```text
/opt/camonas/modules
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
2. Back up `/var/lib/camonas`.
3. Back up `/opt/camonas/modules`.
4. Confirm remote access is working.

If an update fails:

1. Use Proxmox local console or SSH.
2. Restore the previous Camo NAS agent directory.
3. Restart `camonas-agent`.
4. Re-pair a client if token state was restored from an old backup.

