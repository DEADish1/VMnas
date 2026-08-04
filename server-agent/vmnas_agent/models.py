from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


class HostResources(BaseModel):
    cpu_logical: int
    cpu_physical: int
    cpu_model: str = ""
    architecture: str = ""
    memory_total_gb: float
    memory_available_gb: float
    host_reserved_gb: int
    virtualization: str = ""
    gpu_summary: list[str] = []


class CompatibilityWorkload(BaseModel):
    id: str
    name: str
    status: str
    summary: str
    details: list[str] = []


class HostCompatibility(BaseModel):
    host_summary: str
    live_mode_hint: str
    workloads: list[CompatibilityWorkload]
    warnings: list[str] = []


class BenchmarkMetric(BaseModel):
    name: str
    value: float
    unit: str
    summary: str = ""


class BenchmarkRecommendation(BaseModel):
    name: str
    capacity: str
    details: list[str] = []


class SystemBenchmark(BaseModel):
    status: str
    started_at: str = ""
    finished_at: str = ""
    duration_seconds: float = 0
    host_summary: str = ""
    metrics: list[BenchmarkMetric] = []
    recommendations: list[BenchmarkRecommendation] = []
    warnings: list[str] = []


class HostDisk(BaseModel):
    name: str
    path: str
    size_gb: float
    model: str = ""
    transport: str = ""
    drive_kind: str = "drive"
    removable: bool = False
    import_eligible: bool = False
    mountpoints: list[str] = []


class StorageIngestSource(BaseModel):
    id: str
    name: str
    path: str
    size_gb: float
    filesystem: str = ""
    label: str = ""
    mountpoint: str = ""
    removable: bool = False
    transport: str = ""
    source_type: str = "drive"
    ready: bool = False
    status: str = ""
    recommended_action: str = ""


class VmPreset(BaseModel):
    name: str
    label: str = ""
    os_type: str = "linux"
    cpu_vcpus: int = Field(ge=1)
    memory_gb: int = Field(ge=1)
    disk_gb: int = Field(default=64, ge=8)
    gpu_passthrough: bool = False
    notes: list[str]


class WindowsTuningConfig(BaseModel):
    enabled: bool = False
    local_account_name: str = Field(default="vmnas", min_length=1, max_length=32, pattern=r"^[a-zA-Z0-9_.-]+$")
    skip_microsoft_account: bool = True
    hide_privacy_prompts: bool = True
    disable_consumer_features: bool = True
    disable_widgets: bool = True
    disable_onedrive_startup: bool = True


class WindowsTuningApplyResponse(BaseModel):
    vmid: int
    cdrom: str
    script_preview: str
    message: str


class VmCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$")
    os_type: str = Field(default="linux")
    cpu_vcpus: int = Field(ge=1)
    memory_gb: int = Field(ge=1)
    disk_gb: int = Field(default=64, ge=8)
    iso_path: Optional[str] = None
    network_bridge: str = "vmbr0"
    gpu_passthrough: bool = False
    gpu_pci_address: Optional[str] = None
    windows_tuning: Optional[WindowsTuningConfig] = None


class VmSummary(BaseModel):
    vmid: int
    name: str
    status: str
    cpu_vcpus: Optional[int] = None
    memory_mb: Optional[int] = None


class PairingStatus(BaseModel):
    enabled: bool
    pin_hint: str
    paired_devices: int


class PairingRequest(BaseModel):
    device_name: str = Field(min_length=1, max_length=80)
    pin: str = Field(min_length=4, max_length=12)


class PairingResponse(BaseModel):
    device_name: str
    token: str


class PairedDevice(BaseModel):
    id: str
    name: str


class PairingPinResponse(BaseModel):
    pin: str


class StoreModule(BaseModel):
    id: str
    name: str
    category: str
    summary: str
    details: str
    size_mb: int
    required: bool = False
    tags: list[str] = []
    dependencies: list[str] = []
    install_state: str = "available"
    progress: int = Field(default=0, ge=0, le=100)


class ModuleInstallResponse(BaseModel):
    id: str
    install_state: str
    progress: int


class IsoImage(BaseModel):
    name: str
    path: str
    size_mb: float


class OsStoreItem(BaseModel):
    id: str
    name: str
    family: str
    summary: str
    details: str
    version: str = ""
    architecture: str = "amd64"
    size_mb: int = 0
    tags: list[str] = []
    license: str = ""
    download_url: str = ""
    download_page: str = ""
    download_supported: bool = True
    iso_path: str = ""
    install_notes: list[str] = []
    install_state: str = "available"
    progress: int = Field(default=0, ge=0, le=100)


class OsDownloadResponse(BaseModel):
    id: str
    install_state: str
    progress: int
    message: str = ""


class RemoteAccessStatus(BaseModel):
    provider: str = "tailscale"
    installed: bool
    running: bool
    authenticated: bool
    hostname: str = ""
    remote_ip: str = ""
    admin_url: str = ""
    message: str = ""


class ServerUpdateStatus(BaseModel):
    status: str = "idle"
    running: bool = False
    started_at: str = ""
    finished_at: str = ""
    exit_code: int = 0
    message: str = ""
    log_tail: list[str] = []


class GpuDevice(BaseModel):
    pci_address: str
    name: str
    vendor: str = ""
    iommu_group: str = ""
    passthrough_ready: bool = False
    notes: list[str] = []


class VmAccessLinks(BaseModel):
    vmid: int
    console_url: str
    rdp_url: str = ""
    ssh_command: str = ""


class SnapshotRequest(BaseModel):
    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-zA-Z0-9][a-zA-Z0-9_.-]*$")


class SnapshotSummary(BaseModel):
    name: str
    description: str = ""


class DiscoveryInfo(BaseModel):
    name: str = "VMnas"
    api_url: str
    mdns_name: str = "vmnas.local"
    services: list[str] = ["_vmnas._tcp", "_https._tcp"]
