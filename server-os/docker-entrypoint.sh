#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/work"
BUILD_DIR="/build/vmnas-live"
OUT_DIR="/out"
ISO_NAME="${VMNAS_ISO_NAME:-vmnas-server-trixie-amd64.iso}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

lb config \
  --distribution trixie \
  --architectures amd64 \
  --archive-areas "main contrib non-free-firmware" \
  --binary-images iso-hybrid \
  --iso-volume "VMnas" \
  --debian-installer live \
  --bootappend-live "boot=live components hostname=vmnas-server username=vmnas"

mkdir -p config/includes.chroot/usr/local/sbin
mkdir -p config/includes.chroot/opt/vmnas
mkdir -p config/includes.chroot/etc/systemd/system
mkdir -p config/includes.chroot/etc/avahi/services
mkdir -p config/includes.chroot/etc/skel/.config/openbox
mkdir -p config/includes.chroot/etc/lightdm/lightdm.conf.d
mkdir -p config/package-lists

cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-install-proxmox" \
  config/includes.chroot/usr/local/sbin/vmnas-install-proxmox
chmod +x config/includes.chroot/usr/local/sbin/vmnas-install-proxmox
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-pairing-code" \
  config/includes.chroot/usr/local/sbin/vmnas-pairing-code
chmod +x config/includes.chroot/usr/local/sbin/vmnas-pairing-code
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-firstboot-info" \
  config/includes.chroot/usr/local/sbin/vmnas-firstboot-info
chmod +x config/includes.chroot/usr/local/sbin/vmnas-firstboot-info
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-generate-cert" \
  config/includes.chroot/usr/local/sbin/vmnas-generate-cert
chmod +x config/includes.chroot/usr/local/sbin/vmnas-generate-cert
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-apply-firewall" \
  config/includes.chroot/usr/local/sbin/vmnas-apply-firewall
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-update" config/includes.chroot/usr/local/sbin/vmnas-update
chmod +x config/includes.chroot/usr/local/sbin/vmnas-update
cp "${WORK_DIR}/server-os/includes/usr/local/sbin/vmnas-remote-update" config/includes.chroot/usr/local/sbin/vmnas-remote-update
chmod +x config/includes.chroot/usr/local/sbin/vmnas-remote-update
chmod +x config/includes.chroot/usr/local/sbin/vmnas-apply-firewall

cp -R "${WORK_DIR}/server-agent" config/includes.chroot/opt/vmnas/server-agent
cp -R "${WORK_DIR}/server-os/installer-ui" config/includes.chroot/opt/vmnas/installer-ui
cp -R "${WORK_DIR}/server-os/installer-api" config/includes.chroot/opt/vmnas/installer-api
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-agent.service" \
  config/includes.chroot/etc/systemd/system/vmnas-agent.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-installer-ui.service" \
  config/includes.chroot/etc/systemd/system/vmnas-installer-ui.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-firstboot-info.service" \
  config/includes.chroot/etc/systemd/system/vmnas-firstboot-info.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-generate-cert.service" \
  config/includes.chroot/etc/systemd/system/vmnas-generate-cert.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-firewall.service" \
  config/includes.chroot/etc/systemd/system/vmnas-firewall.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-update.service" config/includes.chroot/etc/systemd/system/vmnas-update.service
cp "${WORK_DIR}/server-os/includes/etc/systemd/system/vmnas-update.timer" config/includes.chroot/etc/systemd/system/vmnas-update.timer
cp "${WORK_DIR}/server-os/includes/etc/skel/.config/openbox/autostart" \
  config/includes.chroot/etc/skel/.config/openbox/autostart
chmod +x config/includes.chroot/etc/skel/.config/openbox/autostart
cp "${WORK_DIR}/server-os/includes/etc/lightdm/lightdm.conf.d/50-vmnas-autologin.conf" \
  config/includes.chroot/etc/lightdm/lightdm.conf.d/50-vmnas-autologin.conf
cp "${WORK_DIR}/server-os/includes/etc/avahi/services/vmnas.service" \
  config/includes.chroot/etc/avahi/services/vmnas.service

cat > config/package-lists/vmnas.list.chroot <<'PKGS'
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
cat > config/hooks/normal/0200-vmnas-services.hook.chroot <<'HOOK'
#!/usr/bin/env bash
set -e
systemctl enable vmnas-installer-ui.service
systemctl enable vmnas-update.timer
systemctl set-default graphical.target
HOOK
chmod +x config/hooks/normal/0200-vmnas-services.hook.chroot

lb build
cp live-image-amd64.hybrid.iso "${OUT_DIR}/${ISO_NAME}"
sha256sum "${OUT_DIR}/${ISO_NAME}" > "${OUT_DIR}/${ISO_NAME}.sha256"
