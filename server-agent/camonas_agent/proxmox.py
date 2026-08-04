from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .models import GpuDevice, SnapshotSummary, VmAccessLinks, VmCreateRequest, VmSummary
from .windows_tuning import create_windows_tuning_iso


class ProxmoxUnavailable(RuntimeError):
    pass


@dataclass
class CommandResult:
    stdout: str
    stderr: str


class ProxmoxCli:
    def __init__(self) -> None:
        self.qm = shutil.which("qm")
        self.pvesh = shutil.which("pvesh")

    @property
    def available(self) -> bool:
        return bool(self.qm and self.pvesh)

    def _run(self, args: list[str]) -> CommandResult:
        completed = subprocess.run(args, check=True, text=True, capture_output=True)
        return CommandResult(stdout=completed.stdout, stderr=completed.stderr)

    def require(self) -> None:
        if not self.available:
            raise ProxmoxUnavailable("Proxmox CLI tools are not available on this host.")

    def list_vms(self) -> list[VmSummary]:
        if not self.available and os.environ.get("CAMONAS_ALLOW_MOCK_VMS") == "1":
            return self._list_mock_vms()
        self.require()
        result = self._run([self.pvesh or "pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"])
        payload = json.loads(result.stdout or "[]")
        summaries: list[VmSummary] = []
        for item in payload:
            summaries.append(
                VmSummary(
                    vmid=int(item["vmid"]),
                    name=str(item.get("name") or item["vmid"]),
                    status=str(item.get("status") or "unknown"),
                    cpu_vcpus=item.get("maxcpu"),
                    memory_mb=item.get("maxmem") // 1024 // 1024 if item.get("maxmem") else None,
                )
            )
        return summaries

    def _mock_store_path(self) -> str:
        return os.environ.get("CAMONAS_MOCK_VM_STORE", "/tmp/camonas-mock-vms.json")

    def _read_mock_vms(self) -> list[dict]:
        try:
            with open(self._mock_store_path(), "r", encoding="utf-8") as handle:
                return json.load(handle)
        except FileNotFoundError:
            return []

    def _write_mock_vms(self, vms: list[dict]) -> None:
        with open(self._mock_store_path(), "w", encoding="utf-8") as handle:
            json.dump(vms, handle, indent=2)

    def _list_mock_vms(self) -> list[VmSummary]:
        return [VmSummary(**item) for item in self._read_mock_vms()]

    def next_vmid(self) -> int:
        self.require()
        result = self._run([self.pvesh or "pvesh", "get", "/cluster/nextid"])
        return int(result.stdout.strip())

    def create_vm(self, request: VmCreateRequest) -> VmSummary:
        if not self.available and os.environ.get("CAMONAS_ALLOW_MOCK_VMS") == "1":
            return self._create_mock_vm(request)
        self.require()
        vmid = self.next_vmid()
        memory_mb = request.memory_gb * 1024
        install_media = Path(request.iso_path).expanduser() if request.iso_path else None
        install_media_suffix = install_media.suffix.lower() if install_media else ""
        boot_from_disk_image = install_media_suffix == ".img"
        vm_storage = os.environ.get("CAMONAS_VM_STORAGE", "local-lvm")
        args = [
            self.qm or "qm",
            "create",
            str(vmid),
            "--name",
            request.name,
            "--cores",
            str(request.cpu_vcpus),
            "--memory",
            str(memory_mb),
            "--net0",
            f"virtio,bridge={request.network_bridge}",
            "--scsihw",
            "virtio-scsi-single",
            "--ostype",
            "win11" if request.os_type.lower().startswith("win") else "l26",
            "--machine",
            "q35",
            "--bios",
            "ovmf",
        ]
        if boot_from_disk_image:
            if install_media is None or not install_media.exists():
                raise ValueError("Selected disk image does not exist on the Camo NAS server.")
        else:
            args.extend(["--scsi0", f"{vm_storage}:{request.disk_gb}"])
        if request.iso_path and not boot_from_disk_image:
            args.extend(["--ide2", f"{request.iso_path},media=cdrom"])
        if request.os_type.lower().startswith("win") and request.windows_tuning and request.windows_tuning.enabled:
            tuning_iso = create_windows_tuning_iso(request.name, request.windows_tuning)
            args.extend(["--ide3", f"{tuning_iso},media=cdrom"])
        if request.gpu_passthrough:
            gpu_address = self._validate_passthrough_gpu(request.gpu_pci_address)
            args.extend(["--hostpci0", f"{self._pci_slot_address(gpu_address)},pcie=1,x-vga=1"])

        self._run(args)
        if boot_from_disk_image and install_media is not None:
            self._run([self.qm or "qm", "importdisk", str(vmid), str(install_media), vm_storage])
            self._run([self.qm or "qm", "set", str(vmid), "--scsi0", f"{vm_storage}:vm-{vmid}-disk-0"])
            self._run([self.qm or "qm", "set", str(vmid), "--boot", "order=scsi0"])
        return VmSummary(vmid=vmid, name=request.name, status="stopped", cpu_vcpus=request.cpu_vcpus, memory_mb=memory_mb)

    def attach_cdrom(self, vmid: int, cdrom_ref: str, slot: str = "ide3") -> None:
        if not self.available and os.environ.get("CAMONAS_ALLOW_MOCK_VMS") == "1":
            return
        self.require()
        self._run([self.qm or "qm", "set", str(vmid), f"--{slot}", f"{cdrom_ref},media=cdrom"])

    def _create_mock_vm(self, request: VmCreateRequest) -> VmSummary:
        vms = self._read_mock_vms()
        vmid = max([int(vm["vmid"]) for vm in vms], default=100) + 1
        summary = VmSummary(
            vmid=vmid,
            name=request.name,
            status="stopped",
            cpu_vcpus=request.cpu_vcpus,
            memory_mb=request.memory_gb * 1024,
        )
        vms.append(summary.model_dump())
        self._write_mock_vms(vms)
        return summary

    def _validate_passthrough_gpu(self, pci_address: str | None) -> str:
        if not pci_address:
            raise ValueError("Choose a detected GPU before enabling passthrough.")
        normalized = pci_address.strip()
        gpus = {gpu.pci_address: gpu for gpu in self.detect_gpus()}
        gpu = gpus.get(normalized)
        if gpu is None:
            raise ValueError(f"GPU {normalized} was not found on this server.")
        if not gpu.passthrough_ready:
            hint = " ".join(gpu.notes) if gpu.notes else "Check BIOS virtualization and IOMMU settings."
            raise ValueError(f"GPU {normalized} is not ready for passthrough. {hint}")
        return normalized

    def _pci_slot_address(self, pci_address: str) -> str:
        return pci_address.rsplit(".", 1)[0] if "." in pci_address else pci_address

    def vm_action(self, vmid: int, action: str) -> None:
        self.require()
        allowed = {
            "start": "start",
            "shutdown": "shutdown",
            "stop": "stop",
            "reboot": "reboot",
            "reset": "reset",
        }
        command = allowed.get(action)
        if command is None:
            raise ValueError(f"Unsupported VM action: {action}")
        self._run([self.qm or "qm", command, str(vmid)])

    def delete_vm(self, vmid: int) -> None:
        if not self.available and os.environ.get("CAMONAS_ALLOW_MOCK_VMS") == "1":
            self._write_mock_vms([vm for vm in self._read_mock_vms() if int(vm["vmid"]) != vmid])
            return
        self.require()
        self._run([self.qm or "qm", "destroy", str(vmid), "--purge", "1"])

    def access_links(self, vmid: int) -> VmAccessLinks:
        host = os.environ.get("CAMONAS_PUBLIC_HOST", "SERVER-IP")
        return VmAccessLinks(
            vmid=vmid,
            console_url=f"https://{host}:8006/?console=kvm&vmid={vmid}",
            rdp_url=f"rdp://full%20address=s:{host}",
            ssh_command=f"ssh user@{host}",
        )

    def snapshots(self, vmid: int) -> list[SnapshotSummary]:
        if not self.available:
            return []
        self.require()
        result = self._run([self.qm or "qm", "listsnapshot", str(vmid)])
        snapshots = []
        for line in result.stdout.splitlines():
            line = line.strip().lstrip("`->").strip()
            if not line or line.startswith("Name"):
                continue
            name = line.split()[0]
            if name != "current":
                snapshots.append(SnapshotSummary(name=name))
        return snapshots

    def create_snapshot(self, vmid: int, name: str) -> SnapshotSummary:
        self.require()
        self._run([self.qm or "qm", "snapshot", str(vmid), name])
        return SnapshotSummary(name=name)

    def rollback_snapshot(self, vmid: int, name: str) -> None:
        self.require()
        self._run([self.qm or "qm", "rollback", str(vmid), name])

    def delete_snapshot(self, vmid: int, name: str) -> None:
        self.require()
        self._run([self.qm or "qm", "delsnapshot", str(vmid), name])

    def detect_gpus(self) -> list[GpuDevice]:
        lspci = shutil.which("lspci")
        if not lspci:
            return []
        result = subprocess.run([lspci, "-D", "-nn"], check=False, text=True, capture_output=True)
        devices = []
        for line in result.stdout.splitlines():
            lower = line.lower()
            if "vga compatible controller" not in lower and "3d controller" not in lower and "display controller" not in lower:
                continue
            address = line.split()[0]
            group = self._iommu_group(address)
            notes = []
            if not group:
                notes.append("IOMMU group was not found. Enable SVM/IOMMU in BIOS.")
            vendor = ""
            if "nvidia" in lower:
                vendor = "NVIDIA"
            elif "amd" in lower or "advanced micro devices" in lower or "ati" in lower:
                vendor = "AMD"
            elif "intel" in lower:
                vendor = "Intel"
            devices.append(
                GpuDevice(
                    pci_address=address,
                    name=line,
                    vendor=vendor,
                    iommu_group=group,
                    passthrough_ready=bool(group),
                    notes=notes,
                )
            )
        return devices

    def _iommu_group(self, address: str) -> str:
        path = Path(f"/sys/bus/pci/devices/{address}/iommu_group")
        if not path.exists():
            return ""
        try:
            return path.resolve().name
        except OSError:
            return ""
