from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import psutil

from .models import BenchmarkMetric, BenchmarkRecommendation, HostDisk, HostResources, SystemBenchmark


@dataclass
class BenchmarkStore:
    path: Path

    @classmethod
    def default(cls) -> "BenchmarkStore":
        path = Path(os.environ.get("CAMONAS_BENCHMARK_STORE", "/var/lib/camonas/benchmark.json"))
        if not os.access(path.parent, os.W_OK):
            path = Path.home() / ".camonas" / "benchmark.json"
        return cls(path=path)

    def latest(self) -> SystemBenchmark:
        if not self.path.exists():
            return SystemBenchmark(status="not_run", warnings=["Benchmark has not been run yet."])
        return SystemBenchmark(**json.loads(self.path.read_text(encoding="utf-8")))

    def save(self, benchmark: SystemBenchmark) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(benchmark.model_dump(), indent=2), encoding="utf-8")
        try:
            self.path.chmod(0o600)
        except PermissionError:
            pass


def run_system_benchmark(resources: HostResources, disks: list[HostDisk], gpu_count: int) -> SystemBenchmark:
    started = datetime.now(timezone.utc)
    start_time = time.perf_counter()
    warnings: list[str] = []

    cpu_score = _cpu_score()
    memory_gbps = _memory_score()
    disk_write_mbps, disk_read_mbps = _disk_score()

    usable_memory = max(1, resources.memory_total_gb - resources.host_reserved_gb)
    x86_host = resources.architecture.lower() in {"x86_64", "amd64"}
    largest_disk = max([disk.size_gb for disk in disks], default=0)
    vm_capacity = max(1, min(resources.cpu_logical // 2, int(usable_memory // 4)))
    windows_capacity = 0 if not x86_host else max(0, min(resources.cpu_logical // 4, int(usable_memory // 8)))
    linux_capacity = max(1, min(resources.cpu_logical // 2, int(usable_memory // 4)))
    container_capacity = max(1, min(int(usable_memory // 1.5), max(1, int(disk_write_mbps // 20))))

    if disk_write_mbps < 40:
        warnings.append("Disk write speed is low for running several VMs at once.")
    if usable_memory < 8:
        warnings.append("Usable RAM is low. Keep VM count small or add memory.")
    if not x86_host:
        warnings.append("Connected host is not x86_64/amd64, so common Proxmox and Windows VM workflows are limited.")
    if largest_disk < 128:
        warnings.append("Largest detected disk is small for NAS or multiple VM workloads.")

    recommendations = [
        BenchmarkRecommendation(
            name="Safe simultaneous VMs",
            capacity=f"{vm_capacity}",
            details=[
                "Conservative limit based on detected CPU threads and RAM after host reserve.",
                "Lower this if VMs run heavy databases, desktops, or media workloads.",
            ],
        ),
        BenchmarkRecommendation(
            name="NAS VM",
            capacity="Ready" if resources.cpu_logical >= 2 and usable_memory >= 4 and largest_disk >= 64 else "Limited",
            details=[
                f"Suggested start: {max(1, resources.cpu_logical // 4)} vCPU, {max(1, int(resources.memory_total_gb // 4))} GB RAM.",
                f"Largest detected disk: {largest_disk:g} GB.",
            ],
        ),
        BenchmarkRecommendation(
            name="Windows VMs",
            capacity=f"{windows_capacity}" if windows_capacity else "Needs x86_64 server",
            details=["Assumes about 4 vCPU and 8 GB RAM per comfortable Windows VM."],
        ),
        BenchmarkRecommendation(
            name="Linux VMs",
            capacity=f"{linux_capacity}",
            details=["Assumes about 2 vCPU and 4 GB RAM per general Linux VM."],
        ),
        BenchmarkRecommendation(
            name="Container apps",
            capacity=f"{container_capacity} light services",
            details=["Media servers, sync tools, and dashboards should be added gradually while watching RAM and disk IO."],
        ),
        BenchmarkRecommendation(
            name="GPU passthrough",
            capacity="Possible" if gpu_count else "No GPU detected",
            details=["Requires clean IOMMU groups and one VM owns the passthrough GPU at a time."],
        ),
    ]

    finished = datetime.now(timezone.utc)
    return SystemBenchmark(
        status="complete",
        started_at=started.isoformat(),
        finished_at=finished.isoformat(),
        duration_seconds=round(time.perf_counter() - start_time, 2),
        host_summary=f"{resources.cpu_model} · {resources.cpu_logical} threads · {resources.memory_total_gb:g} GB RAM · {resources.architecture}",
        metrics=[
            BenchmarkMetric(name="CPU score", value=cpu_score, unit="M ops/sec", summary="Short integer workload across the Python runtime."),
            BenchmarkMetric(name="Memory write", value=memory_gbps, unit="GB/sec", summary="Short memory fill/copy test."),
            BenchmarkMetric(name="Disk write", value=disk_write_mbps, unit="MB/sec", summary="Temporary file write test."),
            BenchmarkMetric(name="Disk read", value=disk_read_mbps, unit="MB/sec", summary="Temporary file read test."),
        ],
        recommendations=recommendations,
        warnings=warnings,
    )


def _cpu_score() -> float:
    deadline = time.perf_counter() + 1.0
    loops = 0
    value = 0
    while time.perf_counter() < deadline:
        for number in range(20_000):
            value += number * number
        loops += 20_000
    _ = value
    return round(loops / 1_000_000, 2)


def _memory_score() -> float:
    size = 64 * 1024 * 1024
    block = bytearray(size)
    start = time.perf_counter()
    for offset in range(0, size, 4096):
        block[offset] = 1
    copied = bytes(block)
    elapsed = max(0.001, time.perf_counter() - start)
    _ = copied
    return round((size * 2) / elapsed / 1024 / 1024 / 1024, 2)


def _disk_score() -> tuple[float, float]:
    root = Path(os.environ.get("CAMONAS_BENCHMARK_TMP", "/var/lib/camonas"))
    if not os.access(root, os.W_OK):
        root = Path.home() / ".camonas"
    root.mkdir(parents=True, exist_ok=True)
    path = root / "benchmark.tmp"
    chunk = b"0" * (1024 * 1024)
    size_mb = 64

    start = time.perf_counter()
    with path.open("wb") as handle:
        for _ in range(size_mb):
            handle.write(chunk)
        handle.flush()
        os.fsync(handle.fileno())
    write_elapsed = max(0.001, time.perf_counter() - start)

    start = time.perf_counter()
    with path.open("rb") as handle:
        while handle.read(1024 * 1024):
            pass
    read_elapsed = max(0.001, time.perf_counter() - start)
    path.unlink(missing_ok=True)
    return round(size_mb / write_elapsed, 2), round(size_mb / read_elapsed, 2)
