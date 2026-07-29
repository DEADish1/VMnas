from __future__ import annotations

import json
import math
import plistlib
import platform
import subprocess
from pathlib import Path
from typing import Union

import psutil
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .benchmark import BenchmarkStore, run_system_benchmark
from .isos import IsoStore
from .models import CompatibilityWorkload, DiscoveryInfo, GpuDevice, HostCompatibility, HostDisk, HostResources, IsoImage, ModuleInstallResponse, OsDownloadResponse, OsStoreItem, PairedDevice, PairingPinResponse, PairingRequest, PairingResponse, PairingStatus, RemoteAccessStatus, ServerUpdateStatus, SnapshotRequest, SnapshotSummary, StoreModule, SystemBenchmark, VmAccessLinks, VmCreateRequest, VmPreset, VmSummary, WindowsTuningApplyResponse, WindowsTuningConfig
from .os_store import OsStore
from .pairing import PairingStore
from .proxmox import ProxmoxCli, ProxmoxUnavailable
from .remote import RemoteAccess
from .store import ModuleStore
from .updates import ServerUpdater
from .windows_tuning import create_windows_tuning_test_iso

app = FastAPI(title="VMnas Agent", version="0.1.0")
proxmox = ProxmoxCli()
pairing = PairingStore.default()
module_store = ModuleStore.default()
iso_store = IsoStore.default()
os_store = OsStore.default(iso_store)
benchmark_store = BenchmarkStore.default()
remote_access = RemoteAccess()
server_updater = ServerUpdater()
STATIC_DIR = Path(__file__).parent / "static"

if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


def bytes_to_gb(value: int) -> float:
    return round(value / 1024 / 1024 / 1024, 2)


def detected_cpu_model() -> str:
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text(errors="ignore").splitlines():
            if line.lower().startswith("model name"):
                return line.split(":", 1)[1].strip()
    try:
        result = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], check=False, text=True, capture_output=True)
        if result.stdout.strip():
            return result.stdout.strip()
    except OSError:
        pass
    return platform.processor() or platform.machine() or "Unknown CPU"


def detected_virtualization() -> str:
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        text = f" {cpuinfo.read_text(errors='ignore').lower()} "
        flags = []
        if " svm " in text:
            flags.append("AMD-V/SVM")
        if " vmx " in text:
            flags.append("Intel VT-x")
        return ", ".join(flags) if flags else "Not detected"
    return "Unknown"


def detected_disks() -> list[HostDisk]:
    lsblk = Path("/usr/bin/lsblk")
    if lsblk.exists():
        result = subprocess.run(
            [str(lsblk), "--json", "--bytes", "--output", "NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,MOUNTPOINTS"],
            check=False,
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            payload = json.loads(result.stdout or "{}")
            disks = []
            for item in payload.get("blockdevices", []):
                if item.get("type") != "disk":
                    continue
                mountpoints = [value for value in item.get("mountpoints") or [] if value]
                disks.append(
                    HostDisk(
                        name=item.get("name", ""),
                        path=item.get("path", ""),
                        size_gb=round(int(item.get("size") or 0) / 1000 / 1000 / 1000, 1),
                        model=item.get("model") or "Unknown disk",
                        transport=item.get("tran") or "unknown",
                        removable=bool(item.get("rm")),
                        mountpoints=mountpoints,
                    )
                )
            return disks

    try:
        result = subprocess.run(["diskutil", "list", "-plist"], check=False, text=True, capture_output=True)
        if result.returncode != 0:
            return []
        payload = plistlib.loads(result.stdout.encode("utf-8"))
    except Exception:
        return []
    disks = []
    for item in payload.get("AllDisksAndPartitions", []):
        identifier = item.get("DeviceIdentifier", "")
        info = subprocess.run(["diskutil", "info", "-plist", identifier], check=False, text=True, capture_output=True)
        if info.returncode != 0:
            continue
        try:
            detail = plistlib.loads(info.stdout.encode("utf-8"))
        except Exception:
            continue
        if detail.get("WholeDisk") is False:
            continue
        if detail.get("BusProtocol") == "Disk Image":
            continue
        disks.append(
            HostDisk(
                name=detail.get("MediaName") or detail.get("VolumeName") or identifier,
                path=detail.get("DeviceNode") or f"/dev/{identifier}",
                size_gb=round(int(detail.get("TotalSize") or 0) / 1000 / 1000 / 1000, 1),
                model=detail.get("MediaName") or "Unknown disk",
                transport=detail.get("BusProtocol") or "unknown",
                removable=bool(detail.get("RemovableMedia") or detail.get("Ejectable")),
                mountpoints=[],
            )
        )
    return disks


def require_paired_device(authorization: str = Header(default=""), x_vmnas_token: str = Header(default="")) -> None:
    token = x_vmnas_token.strip()
    if authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
    if not pairing.has_paired_devices():
        return
    if not pairing.validate_token(token):
        raise HTTPException(status_code=401, detail="A paired device token is required.")


@app.get("/health")
def health() -> dict[str, Union[bool, str]]:
    return {"ok": True, "proxmox_available": proxmox.available}


@app.get("/")
def browser_client() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/discovery", response_model=DiscoveryInfo)
def discovery() -> DiscoveryInfo:
    return DiscoveryInfo(api_url="https://vmnas.local:8765")


@app.get("/pairing/status", response_model=PairingStatus)
def pairing_status() -> PairingStatus:
    return PairingStatus(**pairing.status())


@app.post("/pairing/pair", response_model=PairingResponse)
def pair_device(request: PairingRequest) -> PairingResponse:
    try:
        token = pairing.pair(request.device_name, request.pin)
        return PairingResponse(device_name=request.device_name, token=token)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


@app.post("/pairing/rotate", response_model=PairingPinResponse, dependencies=[Depends(require_paired_device)])
def rotate_pairing_pin() -> PairingPinResponse:
    pin = pairing.rotate_pin()
    return PairingPinResponse(pin=pin)


@app.get("/pairing/devices", response_model=list[PairedDevice], dependencies=[Depends(require_paired_device)])
def paired_devices() -> list[PairedDevice]:
    return [PairedDevice(**device) for device in pairing.devices()]


@app.delete("/pairing/devices/{device_id}", dependencies=[Depends(require_paired_device)])
def revoke_paired_device(device_id: str) -> dict[str, str]:
    if not pairing.revoke_device(device_id):
        raise HTTPException(status_code=404, detail="Paired device not found.")
    return {"status": "revoked"}


@app.get("/host/resources", response_model=HostResources, dependencies=[Depends(require_paired_device)])
def host_resources() -> HostResources:
    memory = psutil.virtual_memory()
    gpus = proxmox.detect_gpus()
    return HostResources(
        cpu_logical=psutil.cpu_count(logical=True) or 1,
        cpu_physical=psutil.cpu_count(logical=False) or psutil.cpu_count(logical=True) or 1,
        cpu_model=detected_cpu_model(),
        architecture=platform.machine(),
        memory_total_gb=bytes_to_gb(memory.total),
        memory_available_gb=bytes_to_gb(memory.available),
        host_reserved_gb=4,
        virtualization=detected_virtualization(),
        gpu_summary=[gpu.name for gpu in gpus],
    )


@app.get("/host/gpus", response_model=list[GpuDevice], dependencies=[Depends(require_paired_device)])
def host_gpus() -> list[GpuDevice]:
    return proxmox.detect_gpus()


@app.get("/host/disks", response_model=list[HostDisk], dependencies=[Depends(require_paired_device)])
def host_disks() -> list[HostDisk]:
    return detected_disks()


@app.get("/host/compatibility", response_model=HostCompatibility, dependencies=[Depends(require_paired_device)])
def host_compatibility() -> HostCompatibility:
    resources = host_resources()
    gpus = proxmox.detect_gpus()
    disks = detected_disks()
    memory = resources.memory_total_gb
    cpu = resources.cpu_logical
    usable_memory = max(1, memory - resources.host_reserved_gb)
    root_disk = psutil.disk_usage("/")
    free_disk_gb = bytes_to_gb(root_disk.free)
    total_disk_gb = bytes_to_gb(root_disk.total)
    largest_disk_gb = max([disk.size_gb for disk in disks], default=total_disk_gb)
    has_gpu = bool(gpus or resources.gpu_summary)
    virt_ready = resources.virtualization not in {"", "Unknown", "Not detected"} or proxmox.available
    x86_host = resources.architecture.lower() in {"x86_64", "amd64"}

    def level(ok: bool, limited: bool = False) -> str:
        if ok:
            return "Excellent"
        if limited:
            return "Limited"
        return "Needs setup"

    workloads = [
        CompatibilityWorkload(
            id="nas",
            name="NAS VM",
            status=level(cpu >= 2 and usable_memory >= 4 and largest_disk_gb >= 64, usable_memory >= 2 and largest_disk_gb >= 32),
            summary="File sharing and storage appliance VM.",
            details=[
                f"Recommended starting point: {max(1, math.floor(cpu * 0.25))} vCPU and {max(1, math.floor(memory * 0.25))} GB RAM.",
                f"Detected {len(disks)} storage device(s); largest is {largest_disk_gb:g} GB.",
            ],
        ),
        CompatibilityWorkload(
            id="linux-vms",
            name="Linux VMs",
            status=level(cpu >= 2 and usable_memory >= 4, usable_memory >= 2),
            summary="Server or desktop Linux virtual machines.",
            details=[f"Detected {cpu} logical CPU threads and {usable_memory:g} GB VM-usable RAM after host reserve."],
        ),
        CompatibilityWorkload(
            id="windows-vms",
            name="Windows VMs",
            status=level(x86_host and cpu >= 4 and usable_memory >= 8, x86_host and cpu >= 2 and usable_memory >= 4),
            summary="Windows desktop or server virtual machines.",
            details=["Install the Windows Guest Kit module for VirtIO drivers.", f"Detected architecture: {resources.architecture}."],
        ),
        CompatibilityWorkload(
            id="multiple-vms",
            name="Multiple VMs",
            status=level(cpu >= 8 and usable_memory >= 16, cpu >= 4 and usable_memory >= 8),
            summary="Run a NAS VM plus one or more app/test VMs.",
            details=[f"VMnas will cap sliders using detected {cpu} threads and {memory:g} GB RAM."],
        ),
        CompatibilityWorkload(
            id="containers",
            name="Containers",
            status=level(usable_memory >= 4 and free_disk_gb >= 20, usable_memory >= 2),
            summary="Docker, media apps, dashboards, and self-hosted services.",
            details=[f"Detected root disk: {total_disk_gb:g} GB total, {free_disk_gb:g} GB free."],
        ),
        CompatibilityWorkload(
            id="gpu-passthrough",
            name="GPU Passthrough",
            status=level(has_gpu and any(gpu.passthrough_ready for gpu in gpus), has_gpu),
            summary="Assign a detected GPU to one VM at a time.",
            details=[
                "Requires IOMMU groups and VFIO setup.",
                f"Detected GPUs: {len(gpus)}.",
            ],
        ),
        CompatibilityWorkload(
            id="remote-access",
            name="Secure Remote Access",
            status="Good",
            summary="Pair local devices, then use the server-side VPN module outside the home network.",
            details=["Tailscale Remote Access can be installed from the Module Store."],
        ),
    ]

    warnings = []
    latest_benchmark = benchmark_store.latest()
    if latest_benchmark.status == "complete":
        for recommendation in latest_benchmark.recommendations:
            if recommendation.name == "Safe simultaneous VMs":
                warnings.append(f"Latest benchmark suggests a conservative limit of {recommendation.capacity} simultaneous VM(s).")
                break
    if not virt_ready:
        warnings.append("Hardware virtualization was not detected from the connected server. Check BIOS/UEFI virtualization settings.")
    if memory <= resources.host_reserved_gb:
        warnings.append("Detected RAM is close to the host reserve. Increase RAM or lower the reserve before running VMs.")
    if free_disk_gb < 20:
        warnings.append("Detected free storage is low for ISO downloads and VM disks.")
    if not x86_host:
        warnings.append("The connected host is not x86_64/amd64. Common Windows and Proxmox server workflows expect an x86_64 server.")

    host_summary = f"{resources.cpu_model} · {cpu} logical threads · {memory:g} GB RAM · {resources.architecture}"
    return HostCompatibility(
        host_summary=host_summary,
        live_mode_hint="Live Mode refreshes this test every few seconds while hardware, drives, or modules are changing.",
        workloads=workloads,
        warnings=warnings,
    )


@app.get("/host/benchmark/latest", response_model=SystemBenchmark, dependencies=[Depends(require_paired_device)])
def latest_benchmark() -> SystemBenchmark:
    return benchmark_store.latest()


@app.post("/host/benchmark/run", response_model=SystemBenchmark, dependencies=[Depends(require_paired_device)])
def run_benchmark() -> SystemBenchmark:
    resources = host_resources()
    disks = detected_disks()
    gpus = proxmox.detect_gpus()
    benchmark = run_system_benchmark(resources, disks, len(gpus))
    benchmark_store.save(benchmark)
    return benchmark


@app.get("/store/modules", response_model=list[StoreModule], dependencies=[Depends(require_paired_device)])
def store_modules() -> list[StoreModule]:
    return module_store.modules()


@app.post("/store/modules/{module_id}/install", response_model=ModuleInstallResponse, dependencies=[Depends(require_paired_device)])
def install_module(module_id: str) -> ModuleInstallResponse:
    try:
        return module_store.install(module_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get("/store/downloads", response_model=list[StoreModule], dependencies=[Depends(require_paired_device)])
def store_downloads() -> list[StoreModule]:
    return module_store.downloads()


@app.get("/isos", response_model=list[IsoImage], dependencies=[Depends(require_paired_device)])
def list_isos() -> list[IsoImage]:
    return iso_store.list()


@app.post("/isos/import", response_model=IsoImage, dependencies=[Depends(require_paired_device)])
def import_iso(path: str) -> IsoImage:
    try:
        return iso_store.import_path(path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/isos/upload", response_model=IsoImage, dependencies=[Depends(require_paired_device)])
async def upload_iso(file: UploadFile = File(...)) -> IsoImage:
    try:
        return await iso_store.upload(file)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/os-store/systems", response_model=list[OsStoreItem], dependencies=[Depends(require_paired_device)])
def os_store_systems() -> list[OsStoreItem]:
    return os_store.systems()


@app.post("/os-store/systems/{os_id}/download", response_model=OsDownloadResponse, dependencies=[Depends(require_paired_device)])
def download_os(os_id: str) -> OsDownloadResponse:
    try:
        return os_store.download(os_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.get("/os-store/downloads", response_model=list[OsStoreItem], dependencies=[Depends(require_paired_device)])
def os_downloads() -> list[OsStoreItem]:
    return os_store.downloads()


@app.get("/remote/status", response_model=RemoteAccessStatus, dependencies=[Depends(require_paired_device)])
def remote_status() -> RemoteAccessStatus:
    return remote_access.status()


@app.post("/remote/enable", response_model=RemoteAccessStatus, dependencies=[Depends(require_paired_device)])
def enable_remote_access() -> RemoteAccessStatus:
    return remote_access.enable()


@app.post("/remote/disable", response_model=RemoteAccessStatus, dependencies=[Depends(require_paired_device)])
def disable_remote_access() -> RemoteAccessStatus:
    return remote_access.disable()


@app.get("/system/update/status", response_model=ServerUpdateStatus, dependencies=[Depends(require_paired_device)])
def server_update_status() -> ServerUpdateStatus:
    return server_updater.status()


@app.post("/system/update/run", response_model=ServerUpdateStatus, dependencies=[Depends(require_paired_device)])
def run_server_update() -> ServerUpdateStatus:
    return server_updater.start()


@app.get("/presets/nas", response_model=VmPreset, dependencies=[Depends(require_paired_device)])
def nas_preset() -> VmPreset:
    resources = host_resources()
    usable_memory = max(1, math.floor(resources.memory_total_gb - resources.host_reserved_gb))
    cpu = max(1, math.floor(resources.cpu_logical * 0.25))
    memory = min(usable_memory, max(1, math.floor(resources.memory_total_gb * 0.25)))
    notes = [
        "Default is 25% of logical CPU threads and RAM.",
        f"Detected host: {resources.cpu_logical} logical CPU threads and {resources.memory_total_gb:g} GB RAM.",
        "OpenMediaVault is recommended for a lightweight first NAS VM.",
    ]
    return VmPreset(name="nas", label="NAS", os_type="linux", cpu_vcpus=cpu, memory_gb=memory, disk_gb=128, notes=notes)


@app.get("/presets/vms", response_model=list[VmPreset], dependencies=[Depends(require_paired_device)])
def vm_presets() -> list[VmPreset]:
    resources = host_resources()
    nas = nas_preset()
    usable_memory = max(1, int(resources.memory_total_gb - resources.host_reserved_gb))
    windows_cpu = min(max(4, resources.cpu_logical // 2), resources.cpu_logical)
    windows_memory = min(16, max(1, usable_memory // 2))
    linux_cpu = min(4, max(2, resources.cpu_logical // 4))
    linux_memory = min(8, max(1, usable_memory // 4))
    return [
        nas,
        VmPreset(
            name="windows",
            label="Windows",
            os_type="windows",
            cpu_vcpus=windows_cpu,
            memory_gb=windows_memory,
            disk_gb=128,
            gpu_passthrough=False,
            notes=["Use VirtIO drivers for best performance.", "Enable GPU passthrough only after GPU detection passes."],
        ),
        VmPreset(
            name="linux",
            label="Linux",
            os_type="linux",
            cpu_vcpus=linux_cpu,
            memory_gb=linux_memory,
            disk_gb=64,
            gpu_passthrough=False,
            notes=["Good default for server and development VMs.", "Use cloud images when the Linux Cloud Images module is installed."],
        ),
    ]


@app.get("/vms", response_model=list[VmSummary], dependencies=[Depends(require_paired_device)])
def list_vms() -> list[VmSummary]:
    try:
        return proxmox.list_vms()
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/vms", response_model=VmSummary, dependencies=[Depends(require_paired_device)])
def create_vm(request: VmCreateRequest) -> VmSummary:
    try:
        return proxmox.create_vm(request)
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.delete("/vms/{vmid}", dependencies=[Depends(require_paired_device)])
def delete_vm(vmid: int) -> dict[str, str]:
    try:
        proxmox.delete_vm(vmid)
        return {"status": "deleted"}
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get("/vms/{vmid}/access", response_model=VmAccessLinks, dependencies=[Depends(require_paired_device)])
def vm_access(vmid: int) -> VmAccessLinks:
    return proxmox.access_links(vmid)


@app.post("/vms/{vmid}/windows-tuning/test-media", response_model=WindowsTuningApplyResponse, dependencies=[Depends(require_paired_device)])
def attach_windows_tuning_test_media(vmid: int, request: WindowsTuningConfig) -> WindowsTuningApplyResponse:
    try:
        config = request.model_copy(update={"enabled": True})
        cdrom, script_preview = create_windows_tuning_test_iso(vmid, config)
        proxmox.attach_cdrom(vmid, cdrom)
        return WindowsTuningApplyResponse(
            vmid=vmid,
            cdrom=cdrom,
            script_preview=script_preview,
            message="Windows tuning test media was attached. Start the VM, open the VMNAS_WIN_TUNE disc, and run vmnas-firstlogon.ps1 as Administrator to test the selected settings.",
        )
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.get("/vms/{vmid}/snapshots", response_model=list[SnapshotSummary], dependencies=[Depends(require_paired_device)])
def vm_snapshots(vmid: int) -> list[SnapshotSummary]:
    try:
        return proxmox.snapshots(vmid)
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/vms/{vmid}/snapshots", response_model=SnapshotSummary, dependencies=[Depends(require_paired_device)])
def create_vm_snapshot(vmid: int, request: SnapshotRequest) -> SnapshotSummary:
    try:
        return proxmox.create_snapshot(vmid, request.name)
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/vms/{vmid}/snapshots/{name}/rollback", dependencies=[Depends(require_paired_device)])
def rollback_vm_snapshot(vmid: int, name: str) -> dict[str, str]:
    try:
        proxmox.rollback_snapshot(vmid, name)
        return {"status": "rolled_back"}
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.delete("/vms/{vmid}/snapshots/{name}", dependencies=[Depends(require_paired_device)])
def delete_vm_snapshot(vmid: int, name: str) -> dict[str, str]:
    try:
        proxmox.delete_snapshot(vmid, name)
        return {"status": "deleted"}
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.post("/vms/{vmid}/start", dependencies=[Depends(require_paired_device)])
def start_vm(vmid: int) -> dict[str, Union[str, int]]:
    return run_vm_action(vmid, "start")


@app.post("/vms/{vmid}/shutdown", dependencies=[Depends(require_paired_device)])
def shutdown_vm(vmid: int) -> dict[str, Union[str, int]]:
    return run_vm_action(vmid, "shutdown")


@app.post("/vms/{vmid}/stop", dependencies=[Depends(require_paired_device)])
def stop_vm(vmid: int) -> dict[str, Union[str, int]]:
    return run_vm_action(vmid, "stop")


@app.post("/vms/{vmid}/reboot", dependencies=[Depends(require_paired_device)])
def reboot_vm(vmid: int) -> dict[str, Union[str, int]]:
    return run_vm_action(vmid, "reboot")


def run_vm_action(vmid: int, action: str) -> dict[str, Union[str, int]]:
    try:
        proxmox.vm_action(vmid, action)
        return {"vmid": vmid, "action": action, "status": "accepted"}
    except ProxmoxUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
