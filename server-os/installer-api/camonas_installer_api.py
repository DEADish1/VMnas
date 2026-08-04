#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import secrets
import subprocess
import threading
import urllib.parse
from datetime import datetime
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path("/opt/camonas/installer-ui")
STATE = {
    "state": "ready",
    "phase": "Ready",
    "log": "",
    "report_path": "",
    "reboot_ready": False,
}
PAIRING_PATH = Path("/var/lib/camonas/pairing.json")
REPORT_LABEL = "CAMONAS_LOGS"
DEFAULT_OS_SIZE_GB = 96
MIN_OS_SIZE_GB = 64
MIN_INSTALL_DISK_GB = 80


def partition_plan(size_gb: float) -> dict:
    os_size_gb = DEFAULT_OS_SIZE_GB
    if size_gb < DEFAULT_OS_SIZE_GB + 24:
        os_size_gb = MIN_OS_SIZE_GB
    data_size_gb = max(0, int(size_gb) - os_size_gb - 1)
    return {
        "efi_gb": 1,
        "os_gb": os_size_gb,
        "data_gb": data_size_gb,
        "data_label": "CAMONAS-DATA",
        "data_mount": "/var/lib/camonas/data",
        "installable": size_gb >= MIN_INSTALL_DISK_GB and data_size_gb >= 8,
    }


def ensure_pairing() -> dict:
    PAIRING_PATH.parent.mkdir(parents=True, exist_ok=True)
    if PAIRING_PATH.exists():
        return json.loads(PAIRING_PATH.read_text(encoding="utf-8"))
    data = {"pin": secrets.randbelow(900000) + 100000, "devices": []}
    PAIRING_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
    PAIRING_PATH.chmod(0o600)
    return data


def detected_server_urls() -> list[str]:
    urls = ["https://camonas.local:8765"]
    try:
        result = subprocess.run(["hostname", "-I"], check=False, text=True, capture_output=True, timeout=4)
        for address in result.stdout.split():
            if ":" in address:
                continue
            url = f"https://{address}:8765"
            if url not in urls:
                urls.append(url)
    except Exception:  # noqa: BLE001
        pass
    return urls


def detected_ipv4_addresses() -> list[str]:
    addresses = []
    try:
        result = subprocess.run(["hostname", "-I"], check=False, text=True, capture_output=True, timeout=4)
        for address in result.stdout.split():
            if ":" not in address and address not in addresses:
                addresses.append(address)
    except Exception:  # noqa: BLE001
        pass
    return addresses


def pairing_payload(pin: str) -> dict:
    urls = detected_server_urls()
    api_url = urls[0]
    return {
        "type": "camonas-pairing",
        "version": 1,
        "server_name": "Camo NAS Server",
        "api_url": api_url,
        "urls": urls,
        "pin": str(pin),
        "pair_endpoint": "/pairing/pair",
        "status_endpoint": "/pairing/status",
        "discovery_endpoint": "/discovery",
    }


def pairing_qr_data_url(payload: dict) -> str:
    message = json.dumps(payload, separators=(",", ":"))
    try:
        result = subprocess.run(
            ["qrencode", "--type=SVG", "--output=-", message],
            check=False,
            text=True,
            capture_output=True,
            timeout=6,
        )
    except Exception:  # noqa: BLE001
        return ""
    if result.returncode != 0 or not result.stdout:
        return ""
    return "data:image/svg+xml," + urllib.parse.quote(result.stdout)


def hardware() -> dict:
    cpu_text = Path("/proc/cpuinfo").read_text(errors="ignore")
    cpu = cpu_text.split("model name")
    cpu_name = "Detected host"
    if len(cpu) > 1:
        cpu_name = cpu[1].split(":", 1)[1].splitlines()[0].strip()
    cpu_logical = sum(1 for line in cpu_text.splitlines() if line.startswith("processor"))
    if cpu_logical < 1:
        try:
            cpu_logical = os.cpu_count() or 1
        except Exception:  # noqa: BLE001
            cpu_logical = 1
    mem_kb = 0
    for line in Path("/proc/meminfo").read_text().splitlines():
        if line.startswith("MemTotal:"):
            mem_kb = int(line.split()[1])
            break
    memory_gb = round(mem_kb / 1024 / 1024, 1)
    host_reserved_gb = min(8, max(2, round(memory_gb * 0.10)))
    usable_memory_gb = max(1, int(memory_gb - host_reserved_gb))
    gpu_names = []
    try:
        result = subprocess.run(["lspci"], check=False, text=True, capture_output=True)
        for line in result.stdout.splitlines():
            lower = line.lower()
            if "vga compatible controller" in lower or "3d controller" in lower or "display controller" in lower:
                gpu_names.append(line.strip())
    except FileNotFoundError:
        gpu_names.append("GPU detection tool unavailable in this boot environment")
    addresses = detected_ipv4_addresses()
    network = f"Connected: {', '.join(addresses)}" if addresses else "Check cable or DHCP"
    return {
        "cpu": cpu_name,
        "cpu_logical": cpu_logical,
        "memory_gb": memory_gb,
        "host_reserved_gb": host_reserved_gb,
        "usable_memory_gb": usable_memory_gb,
        "nas_default_vcpus": max(1, int(cpu_logical * 0.25)),
        "nas_default_memory_gb": max(1, min(usable_memory_gb, int(memory_gb * 0.25))),
        "gpu": gpu_names,
        "network": network,
        "ipv4": addresses,
    }


def disks() -> dict:
    result = subprocess.run(
        ["lsblk", "--json", "--bytes", "--output", "NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,MOUNTPOINTS"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return {"disks": []}
    payload = json.loads(result.stdout or "{}")
    found = []
    for item in payload.get("blockdevices", []):
        if item.get("type") != "disk":
            continue
        if item.get("rm"):
            continue
        size_gb = round(int(item.get("size") or 0) / 1000 / 1000 / 1000, 1)
        found.append(
            {
                "name": item.get("name", ""),
                "path": item.get("path", ""),
                "size_gb": size_gb,
                "model": item.get("model") or "Unknown disk",
                "transport": item.get("tran") or "unknown",
                "plan": partition_plan(size_gb),
            }
        )
    return {"disks": found}


def set_phase(phase: str) -> None:
    STATE["phase"] = phase
    STATE["log"] += f"\n== {phase} ==\n"


def run_text(command: list[str], timeout: int = 12) -> str:
    try:
        result = subprocess.run(command, check=False, text=True, capture_output=True, timeout=timeout)
    except Exception as exc:  # noqa: BLE001
        return f"{command[0]} failed to run: {exc}\n"
    output = result.stdout or ""
    if result.stderr:
        output += "\n[stderr]\n" + result.stderr
    return output


def mounted_report_volume() -> Path | None:
    candidates = [
        Path(f"/media/{REPORT_LABEL}"),
        Path(f"/mnt/{REPORT_LABEL}"),
        Path(f"/run/media/camonas/{REPORT_LABEL}"),
        Path(f"/run/live/medium/{REPORT_LABEL}"),
    ]
    for candidate in candidates:
        if candidate.is_dir():
            return candidate

    device = Path(f"/dev/disk/by-label/{REPORT_LABEL}")
    if not device.exists():
        return None

    mount_dir = Path(f"/mnt/{REPORT_LABEL}")
    mount_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["mount", str(device), str(mount_dir)], check=False, text=True, capture_output=True)
    if result.returncode == 0 and mount_dir.is_dir():
        return mount_dir
    return None


def safe_payload(payload: dict) -> dict:
    sanitized = dict(payload)
    if "admin_password" in sanitized:
        sanitized["admin_password"] = "[redacted]"
    return sanitized


def write_error_report(exit_code: int, payload: dict) -> str:
    volume = mounted_report_volume()
    if volume is None:
        STATE["log"] += "\nNo CAMONAS_LOGS partition was found for the install error report.\n"
        return ""

    timestamp = datetime.utcnow().strftime("%Y%m%d-%H%M%SZ")
    report_dir = volume / "reports" / f"install-failed-{timestamp}"
    report_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "timestamp_utc": timestamp,
        "exit_code": exit_code,
        "phase": STATE.get("phase", ""),
        "state": STATE.get("state", ""),
        "payload": safe_payload(payload),
    }
    (report_dir / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (report_dir / "installer.log").write_text(STATE.get("log", ""), encoding="utf-8")
    (report_dir / "hardware.json").write_text(json.dumps(hardware(), indent=2), encoding="utf-8")
    (report_dir / "disks.json").write_text(json.dumps(disks(), indent=2), encoding="utf-8")

    commands = {
        "lsblk.txt": ["lsblk", "--all", "--output", "NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MODEL,TYPE,TRAN,RM,MOUNTPOINTS"],
        "lspci.txt": ["lspci", "-nn"],
        "ip-address.txt": ["ip", "addr"],
        "ip-route.txt": ["ip", "route"],
        "mounts.txt": ["findmnt"],
        "dmesg-tail.txt": ["dmesg", "--ctime", "--level=err,warn"],
        "journal-installer.txt": ["journalctl", "--no-pager", "-n", "400"],
    }
    for filename, command in commands.items():
        (report_dir / filename).write_text(run_text(command), encoding="utf-8")

    target_log_dir = report_dir / "target"
    if Path("/mnt/camonas-target").exists():
        target_log_dir.mkdir(exist_ok=True)
        for source in [
            Path("/mnt/camonas-target/etc/apt/sources.list"),
            Path("/mnt/camonas-target/etc/apt/sources.list.d/proxmox.sources"),
            Path("/mnt/camonas-target/etc/hosts"),
            Path("/mnt/camonas-target/etc/hostname"),
            Path("/mnt/camonas-target/var/lib/camonas/install-profile.json"),
        ]:
            if source.exists():
                (target_log_dir / source.name).write_text(source.read_text(errors="ignore"), encoding="utf-8")

    (volume / "LATEST-REPORT.txt").write_text(str(report_dir) + "\n", encoding="utf-8")
    subprocess.run(["sync"], check=False)
    STATE["log"] += f"\nInstall error report saved to {report_dir}.\n"
    return str(report_dir)


def validate_install_payload(payload: dict) -> str | None:
    target_disk = str(payload.get("target_disk") or "")
    confirmation = str(payload.get("erase_confirmation") or "")
    admin_password = str(payload.get("admin_password") or "")
    installer_script = Path("/usr/local/sbin/camonas-install-proxmox")
    detected = hardware()
    try:
        nas_cpu_vcpus = int(payload.get("nas_cpu_vcpus", detected["nas_default_vcpus"]))
        nas_ram_gb = int(payload.get("nas_ram_gb", detected["nas_default_memory_gb"]))
    except (TypeError, ValueError):
        return "Choose valid NAS CPU and RAM amounts."
    if not target_disk.startswith("/dev/"):
        return "Select a valid target disk."
    if confirmation.strip().upper() != "ERASE":
        return "Type ERASE to confirm only the selected server drive can be repartitioned."
    if len(admin_password) < 8:
        return "Set an admin password with at least 8 characters."
    if not installer_script.exists():
        return "Installer engine is missing from this Camo NAS boot media. Rebuild the server ISO and remake the USB."
    if not os.access(installer_script, os.X_OK):
        return "Installer engine is not executable on this Camo NAS boot media. Rebuild the server ISO and remake the USB."
    if nas_cpu_vcpus < 1 or nas_cpu_vcpus > int(detected["cpu_logical"]):
        return f"NAS CPU must be between 1 and {detected['cpu_logical']} vCPU."
    if nas_ram_gb < 1 or nas_ram_gb > int(detected["usable_memory_gb"]):
        return f"NAS RAM must be between 1 and {detected['usable_memory_gb']} GB."
    available = {disk["path"]: disk for disk in disks()["disks"]}
    if target_disk not in available:
        return "Selected disk is not available."
    if not available[target_disk].get("plan", {}).get("installable", False):
        return "Selected disk is too small. Camo NAS needs at least 80 GB for the OS partition, update overhead, and a ready data partition."
    return None


def run_install(payload: dict) -> None:
    STATE["state"] = "running"
    STATE["phase"] = "Preparing"
    STATE["log"] = ""
    STATE["report_path"] = ""
    STATE["reboot_ready"] = False
    env = os.environ.copy()
    env["CAMONAS_HOSTNAME"] = payload.get("hostname", "camonas")
    env["CAMONAS_ADMIN_USER"] = payload.get("admin_user", "camonas")
    env["CAMONAS_ADMIN_PASSWORD"] = payload.get("admin_password", "")
    env["CAMONAS_MODULES"] = ",".join(payload.get("modules", []))
    detected = hardware()
    env["CAMONAS_NAS_CPU_VCPUS"] = str(payload.get("nas_cpu_vcpus", detected["nas_default_vcpus"]))
    env["CAMONAS_NAS_RAM_GB"] = str(payload.get("nas_ram_gb", detected["nas_default_memory_gb"]))
    env["CAMONAS_TARGET_DISK"] = payload.get("target_disk", "")
    env["CAMONAS_OS_SIZE_GB"] = str(DEFAULT_OS_SIZE_GB)
    env["CAMONAS_MIN_OS_SIZE_GB"] = str(MIN_OS_SIZE_GB)
    env["CAMONAS_ERASE_CONFIRMED"] = "1"
    set_phase("Partitioning selected server drive")
    set_phase("Installing Debian base")
    set_phase("Installing Proxmox and Camo NAS services")
    process = subprocess.Popen(
        ["/usr/local/sbin/camonas-install-proxmox"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    assert process.stdout is not None
    for line in process.stdout:
        if line.startswith("CAMONAS_PHASE:"):
            set_phase(line.split(":", 1)[1].strip())
        else:
            STATE["log"] += line
    code = process.wait()
    STATE["state"] = "complete" if code == 0 else "failed"
    STATE["phase"] = "Complete" if code == 0 else "Failed"
    STATE["reboot_ready"] = code == 0
    STATE["log"] += f"\nInstaller exited with code {code}.\n"
    if code != 0:
        STATE["report_path"] = write_error_report(code, payload)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, format, *args):  # noqa: A002
        return

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def json_response(self, payload: dict, status: int = 200) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self):  # noqa: N802
        if self.path == "/api/hardware":
            self.json_response(hardware())
            return
        if self.path == "/api/disks":
            self.json_response(disks())
            return
        if self.path == "/api/pairing":
            pin = str(ensure_pairing()["pin"])
            payload = pairing_payload(pin)
            self.json_response({"pin": pin, "payload": payload, "qr_svg": pairing_qr_data_url(payload)})
            return
        if self.path == "/api/install/status":
            self.json_response(STATE)
            return
        super().do_GET()

    def do_POST(self):  # noqa: N802
        if self.path == "/api/pairing/rotate":
            data = ensure_pairing()
            data["pin"] = secrets.randbelow(900000) + 100000
            PAIRING_PATH.write_text(json.dumps(data, indent=2), encoding="utf-8")
            pin = str(data["pin"])
            payload = pairing_payload(pin)
            self.json_response({"pin": pin, "payload": payload, "qr_svg": pairing_qr_data_url(payload)})
            return
        if self.path == "/api/install/start":
            if STATE["state"] == "running":
                self.json_response({"error": "Installer is already running."}, 409)
                return
            payload = self.body_json()
            error = validate_install_payload(payload)
            if error:
                self.json_response({"error": error}, 400)
                return
            threading.Thread(target=run_install, args=(payload,), daemon=True).start()
            self.json_response({"state": "running"})
            return
        if self.path == "/api/reboot":
            if not STATE.get("reboot_ready"):
                self.json_response({"error": "Install is not complete."}, 409)
                return
            subprocess.Popen(["systemctl", "reboot"])
            self.json_response({"state": "rebooting"})
            return
        self.json_response({"error": "Not found"}, 404)


def main() -> None:
    ensure_pairing()
    server = ThreadingHTTPServer(("127.0.0.1", 8780), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
