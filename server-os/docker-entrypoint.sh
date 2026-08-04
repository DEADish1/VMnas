#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/work"
BUILD_DIR="/build/camonas-live"
OUT_DIR="/out"
ISO_NAME="${CAMONAS_ISO_NAME:-camonas-server-trixie-amd64.iso}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

lb config \
  --distribution trixie \
  --architectures amd64 \
  --archive-areas "main contrib non-free-firmware" \
  --binary-images iso-hybrid \
  --iso-volume "CamoNAS" \
  --debian-installer live \
  --bootappend-live "boot=live components hostname=camonas-server username=camonas"

mkdir -p config/includes.chroot/usr/local/sbin
mkdir -p config/includes.chroot/opt/camonas
mkdir -p config/includes.chroot/etc/systemd/system
mkdir -p config/includes.chroot/etc/avahi/services
mkdir -p config/includes.chroot/etc/skel/.config/openbox
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
mkdir -p config/package-lists

cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-install-proxmox" \
  config/includes.chroot/usr/local/sbin/camonas-install-proxmox
chmod +x config/includes.chroot/usr/local/sbin/camonas-install-proxmox
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-pairing-code" \
  config/includes.chroot/usr/local/sbin/camonas-pairing-code
chmod +x config/includes.chroot/usr/local/sbin/camonas-pairing-code
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-firstboot-info" \
  config/includes.chroot/usr/local/sbin/camonas-firstboot-info
chmod +x config/includes.chroot/usr/local/sbin/camonas-firstboot-info
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-generate-cert" \
  config/includes.chroot/usr/local/sbin/camonas-generate-cert
chmod +x config/includes.chroot/usr/local/sbin/camonas-generate-cert
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-apply-firewall" \
  config/includes.chroot/usr/local/sbin/camonas-apply-firewall
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-update" config/includes.chroot/usr/local/sbin/camonas-update
chmod +x config/includes.chroot/usr/local/sbin/camonas-update
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/camonas-remote-update" config/includes.chroot/usr/local/sbin/camonas-remote-update
chmod +x config/includes.chroot/usr/local/sbin/camonas-remote-update
chmod +x config/includes.chroot/usr/local/sbin/camonas-apply-firewall

cp -R "${WORK_DIR}/server-agent" config/includes.chroot/opt/camonas/server-agent
cp -R "${WORK_DIR}/server-os/installer-ui" config/includes.chroot/opt/camonas/installer-ui
cp -R "${WORK_DIR}/server-os/installer-api" config/includes.chroot/opt/camonas/installer-api
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-agent.service" \
  config/includes.chroot/etc/systemd/system/camonas-agent.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-installer-ui.service" \
  config/includes.chroot/etc/systemd/system/camonas-installer-ui.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-firstboot-info.service" \
  config/includes.chroot/etc/systemd/system/camonas-firstboot-info.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-generate-cert.service" \
  config/includes.chroot/etc/systemd/system/camonas-generate-cert.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-firewall.service" \
  config/includes.chroot/etc/systemd/system/camonas-firewall.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-update.service" config/includes.chroot/etc/systemd/system/camonas-update.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/camonas-update.timer" config/includes.chroot/etc/systemd/system/camonas-update.timer
cp "${WORK_DIR}/server-os/includes/etc/skel/.config/openbox/autostart" \
  config/includes.chroot/etc/skel/.config/openbox/autostart
chmod +x config/includes.chroot/etc/skel/.config/openbox/autostart
cp "${WORK_DIR}/server-os/includes/etc/lightdm/lightdm.conf.d/50-camonas-autologin.conf" \
  config/includes.chroot/etc/lightdm/lightdm.conf.d/50-camonas-autologin.conf
cp "${WORK_DIR}/server-os/includes/etc/avahi/services/camonas.service" \
  config/includes.chroot/etc/avahi/services/camonas.service

cat > config/package-lists/camonas.list.chroot <<'PKGS'
openssh-server
sudo
curl
openssl
ca-certificates
avahi-daemon
debootstrap
dosfstools
e2fsprogs
gdisk
gnupg
firefox-esr
lightdm
nftables
openbox
parted
pciutils
python3
python3-venv
python3-pip
qrencode
rsync
util-linux
iproute2
xorg
zfsutils-linux
PKGS

mkdir -p config/hooks/normal
cat > config/hooks/normal/0200-camonas-services.hook.chroot <<'HOOK'
#!/usr/bin/env bash
set -e
systemctl enable camonas-installer-ui.service
systemctl enable camonas-update.timer
systemctl set-default graphical.target
HOOK
chmod +x config/hooks/normal/0200-camonas-services.hook.chroot

lb build
cp live-image-amd64.hybrid.iso "${OUT_DIR}/${ISO_NAME}"
sha256sum "${OUT_DIR}/${ISO_NAME}" > "${OUT_DIR}/${ISO_NAME}.sha256"
