#!/bin/bash
set -euo pipefail

ISO="/Users/deadmac/Documents/VMnas/dist/vmnas-server-trixie-amd64.iso"
DEVICE="/dev/disk4"
RAW_DEVICE="/dev/rdisk4"
LOG="/Users/deadmac/Documents/VMnas/usb-write-disk4.log"

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "---- VMnas server ISO write started $(date) ----"
echo "Target: $DEVICE"
echo "Source: $ISO"
echo "This will erase $DEVICE. Press Control-C in the next 5 seconds to cancel."
sleep 5

if [ ! -f "$ISO" ]; then
  echo "ISO not found: $ISO" >&2
  exit 2
fi

if [ ! -e "$DEVICE" ]; then
  echo "USB device not found: $DEVICE" >&2
  exit 3
fi

echo "Requesting admin access..."
sudo -v

run_dd_with_progress() {
  local output_device="$1"
  sudo /bin/dd if="$ISO" of="$output_device" bs=4m &
  local dd_pid=$!
  (
    while kill -0 "$dd_pid" 2>/dev/null; do
      sleep 10
      kill -INFO "$dd_pid" 2>/dev/null || true
    done
  ) &
  local info_pid=$!
  wait "$dd_pid"
  local status=$?
  kill "$info_pid" 2>/dev/null || true
  wait "$info_pid" 2>/dev/null || true
  return "$status"
}

echo "Unmounting $DEVICE..."
sudo /usr/sbin/diskutil unmountDisk force "$DEVICE"

echo "Writing VMnas ISO to $RAW_DEVICE..."
if ! run_dd_with_progress "$RAW_DEVICE"; then
  echo "Raw write failed; retrying slower buffered path $DEVICE..."
  sudo /usr/sbin/diskutil unmountDisk force "$DEVICE" || true
  run_dd_with_progress "$DEVICE"
fi

echo "Flushing writes..."
/bin/sync

echo "Creating VMNAS_LOGS report partition..."
sudo /usr/sbin/diskutil unmountDisk force "$DEVICE" || true
sudo /usr/sbin/diskutil addPartition "$DEVICE" ExFAT VMNAS_LOGS 512m
sudo /usr/sbin/diskutil mountDisk "$DEVICE" || true
REPORT_DEST="$(/usr/sbin/diskutil info -plist VMNAS_LOGS | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null || true)"
if [ -z "$REPORT_DEST" ]; then
  REPORT_DEST="/Volumes/VMNAS_LOGS"
fi
if [ ! -d "$REPORT_DEST" ]; then
  echo "VMNAS_LOGS report partition was not mounted." >&2
  exit 4
fi
mkdir -p "$REPORT_DEST/reports"
cat > "$REPORT_DEST/README.txt" <<'EOF'
VMnas install reports

If a server install fails, booted VMnas installer logs will be saved in the reports folder on this partition.
Plug this USB drive back into your Mac and share the newest report folder so the issue can be diagnosed.
EOF
echo "VMNAS_LOGS is ready at $REPORT_DEST"

echo "Ejecting $DEVICE..."
sudo /usr/sbin/diskutil eject "$DEVICE"

echo "---- VMnas server ISO write completed $(date) ----"
echo "Done. You can close this Terminal window."
