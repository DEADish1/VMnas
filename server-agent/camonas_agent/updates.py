from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from .models import ServerUpdateStatus


STATE_PATH = Path("/var/lib/camonas/update-status.json")
LOG_PATH = Path("/var/log/camonas/update.log")
RUNNER = Path("/usr/local/sbin/camonas-remote-update")


class ServerUpdater:
    def __init__(self, state_path: Path = STATE_PATH, log_path: Path = LOG_PATH, runner: Path = RUNNER) -> None:
        self.state_path = state_path
        self.log_path = log_path
        self.runner = runner

    def status(self) -> ServerUpdateStatus:
        state = self._read_state()
        running = self._is_running()
        if running:
            state["status"] = "running"
            state["message"] = "Server update is running."
        elif state.get("status") == "running":
            state["status"] = "unknown"
            state["message"] = "Update process ended before writing final status."
        state.setdefault("status", "idle")
        state.setdefault("started_at", "")
        state.setdefault("finished_at", "")
        state.setdefault("exit_code", 0)
        state.setdefault("message", "No remote update has been run yet.")
        state["running"] = running
        state["log_tail"] = self._log_tail()
        return ServerUpdateStatus(**state)

    def start(self) -> ServerUpdateStatus:
        if self._is_running():
            return self.status()
        if not self.runner.exists():
            return ServerUpdateStatus(
                status="missing",
                running=False,
                exit_code=127,
                message="Remote update runner is not installed on this server.",
                log_tail=self._log_tail(),
            )
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        now = datetime.now(timezone.utc).isoformat()
        self._write_state(
            {
                "status": "starting",
                "running": True,
                "started_at": now,
                "finished_at": "",
                "exit_code": 0,
                "message": "Starting remote server update.",
            }
        )
        subprocess.Popen(
            [str(self.runner)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return self.status()

    def _read_state(self) -> dict:
        if not self.state_path.exists():
            return {}
        try:
            return json.loads(self.state_path.read_text(errors="ignore") or "{}")
        except json.JSONDecodeError:
            return {"status": "unknown", "message": "Update status file could not be read."}

    def _write_state(self, payload: dict) -> None:
        self.state_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _is_running(self) -> bool:
        marker = Path("/run/camonas-update.pid")
        if not marker.exists():
            return False
        try:
            pid = int(marker.read_text().strip())
        except ValueError:
            return False
        return Path(f"/proc/{pid}").exists()

    def _log_tail(self) -> list[str]:
        if not self.log_path.exists():
            return []
        lines = self.log_path.read_text(errors="ignore").splitlines()
        return lines[-80:]
