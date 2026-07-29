const steps = ["welcome", "hardware", "storage", "account", "modules", "pair", "install"];
let currentStep = 0;

const title = document.querySelector("#step-title");
const statusPill = document.querySelector("#status-pill");
const backButton = document.querySelector("#back");
const nextButton = document.querySelector("#next");
const installButton = document.querySelector("#install-button");
const rebootButton = document.querySelector("#reboot-button");
const log = document.querySelector("#install-log");
const failureHelp = document.querySelector("#failure-help");
let selectedDisk = "";
let detectedHardware = null;

function stepName(id) {
  return document.querySelector(`[data-step="${id}"]`).textContent;
}

function showStep(index) {
  currentStep = Math.max(0, Math.min(index, steps.length - 1));
  const id = steps[currentStep];

  document.querySelectorAll(".step").forEach((step) => {
    step.classList.toggle("active", step.id === id);
  });
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.classList.toggle("active", item.dataset.step === id);
  });

  title.textContent = stepName(id);
  backButton.disabled = currentStep === 0;
  nextButton.textContent = currentStep === steps.length - 1 ? "Review" : "Next";
}

function selectedModules() {
  return Array.from(document.querySelectorAll(".module input:checked")).map((input) => input.value);
}

function installPayload() {
  clampResourceValues();
  return {
    hostname: document.querySelector("#hostname").value.trim() || "vmnas",
    admin_user: document.querySelector("#admin-user").value.trim() || "vmnas",
    admin_password: document.querySelector("#admin-password").value,
    timezone: document.querySelector("#timezone").value.trim() || "America/New_York",
    nas_cpu_vcpus: Number(document.querySelector("#nas-cpu").value),
    nas_ram_gb: Number(document.querySelector("#nas-ram").value),
    target_disk: selectedDisk,
    erase_confirmation: document.querySelector("#erase-confirmation").value,
    enable_iommu: document.querySelector("#enable-iommu").checked,
    enable_ssh: document.querySelector("#enable-ssh").checked,
    enable_web: document.querySelector("#enable-web").checked,
    auto_updates: document.querySelector("#auto-updates").checked,
    modules: selectedModules(),
  };
}

function installReady() {
  const password = document.querySelector("#admin-password").value;
  const confirm = document.querySelector("#admin-password-confirm").value;
  const selectedInput = document.querySelector('input[name="target-disk"]:checked');
  const installable = selectedInput ? selectedInput.dataset.installable === "true" : false;
  return Boolean(detectedHardware) && selectedDisk && installable && document.querySelector("#erase-confirmation").value.trim().toUpperCase() === "ERASE" && password.length >= 8 && password === confirm;
}

function installBlockedReason() {
  const password = document.querySelector("#admin-password").value;
  const confirm = document.querySelector("#admin-password-confirm").value;
  const selectedInput = document.querySelector('input[name="target-disk"]:checked');
  if (!detectedHardware) return "Waiting for hardware detection before install can start.";
  if (!selectedDisk || !selectedInput) return "Choose the server drive to install VMnas on.";
  if (selectedInput.dataset.installable !== "true") return "Choose an installable server drive.";
  if (document.querySelector("#erase-confirmation").value.trim().toUpperCase() !== "ERASE") return "Type ERASE to confirm the selected server drive can be repartitioned.";
  if (password.length < 8) return "Set an admin password with at least 8 characters.";
  if (password !== confirm) return "Confirm the admin password so both password fields match.";
  return "";
}

function updateInstallButton() {
  const ready = installReady();
  const reason = installBlockedReason();
  installButton.disabled = !ready;
  const warning = document.querySelector("#password-warning");
  warning.textContent = reason;
  warning.classList.toggle("hidden", ready || !reason);
}

async function getJSON(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

async function postJSON(path, body = {}) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    let message = `HTTP ${response.status}`;
    try {
      const payload = await response.json();
      message = payload.error || message;
    } catch {
      // Keep the HTTP status if the response is not JSON.
    }
    throw new Error(message);
  }
  return response.json();
}

async function loadHardware() {
  try {
    const hardware = await getJSON("/api/hardware");
    detectedHardware = hardware;
    const graphics = hardware.gpu && hardware.gpu.length ? hardware.gpu.join("<br>") : "No dedicated GPU detected";
    document.querySelector("#hardware-list").innerHTML = `
      <div><dt>CPU</dt><dd>${hardware.cpu}</dd></div>
      <div><dt>CPU Threads</dt><dd>${hardware.cpu_logical}</dd></div>
      <div><dt>Memory</dt><dd>${hardware.memory_gb} GB</dd></div>
      <div><dt>VM-usable RAM</dt><dd>${hardware.usable_memory_gb} GB</dd></div>
      <div><dt>Graphics</dt><dd>${graphics}</dd></div>
      <div><dt>Network</dt><dd>${hardware.network}</dd></div>
    `;
    configureResourceSliders(hardware);
  } catch {
    statusPill.textContent = "Offline";
    statusPill.style.color = "#a15c00";
  }
}

function configureResourceSliders(hardware) {
  const cpuInput = document.querySelector("#nas-cpu");
  const ramInput = document.querySelector("#nas-ram");
  cpuInput.max = Math.max(1, Number(hardware.cpu_logical || 1));
  cpuInput.value = Math.max(1, Number(hardware.nas_default_vcpus || 1));
  ramInput.max = Math.max(1, Number(hardware.usable_memory_gb || 1));
  ramInput.value = Math.max(1, Number(hardware.nas_default_memory_gb || 1));
  updateResourceOutputs();
  updateInstallButton();
}

function clampResourceValues() {
  const cpuInput = document.querySelector("#nas-cpu");
  const ramInput = document.querySelector("#nas-ram");
  const cpuMin = Number(cpuInput.min || 1);
  const cpuMax = Number(cpuInput.max || 1);
  const ramMin = Number(ramInput.min || 1);
  const ramMax = Number(ramInput.max || 1);
  cpuInput.value = Math.min(cpuMax, Math.max(cpuMin, Number(cpuInput.value || cpuMin)));
  ramInput.value = Math.min(ramMax, Math.max(ramMin, Number(ramInput.value || ramMin)));
  updateResourceOutputs();
}

function updateResourceOutputs() {
  const cpuInput = document.querySelector("#nas-cpu");
  const ramInput = document.querySelector("#nas-ram");
  const cpuValue = Number(cpuInput.value);
  const ramValue = Number(ramInput.value);
  const cpuMax = Number(cpuInput.max);
  const ramMax = Number(ramInput.max);
  document.querySelector("#cpu-out").textContent = `${cpuValue} vCPU${cpuValue === 1 ? "" : "s"} of ${cpuMax}`;
  document.querySelector("#ram-out").textContent = `${ramValue} GB of ${ramMax} GB usable`;
}

async function loadDisks() {
  const list = document.querySelector("#disk-list");
  try {
    const payload = await getJSON("/api/disks");
    if (!payload.disks.length) {
      list.innerHTML = "<p>No installable internal disks were detected.</p>";
      return;
    }
    list.innerHTML = payload.disks.map((disk) => {
      const plan = disk.plan || {};
      const installable = plan.installable !== false;
      const disabled = installable ? "" : "disabled";
      const dataText = installable
        ? `Plan: 1 GB EFI · ${plan.os_gb} GB VMnas OS · ${plan.data_gb} GB VMNAS-DATA`
        : "Too small for VMnas OS plus a usable data partition";
      return `
      <label class="disk-option ${installable ? "" : "disabled"}">
        <input type="radio" name="target-disk" value="${disk.path}" data-installable="${installable}" ${disabled}>
        <span class="disk-title">${disk.model}</span>
        <small>${disk.path} · ${disk.size_gb} GB · ${disk.transport}</small>
        <small>${dataText}</small>
      </label>
    `;
    }).join("");
    document.querySelectorAll('input[name="target-disk"]').forEach((input) => {
      input.addEventListener("change", () => {
        selectedDisk = input.value;
        document.querySelectorAll(".disk-option").forEach((option) => {
          option.classList.toggle("selected", option.contains(input));
        });
        const disk = payload.disks.find((item) => item.path === selectedDisk);
        const plan = disk && disk.plan ? disk.plan : {};
        document.querySelector("#selected-disk-summary").textContent = `${selectedDisk} only will be repartitioned. Other drives are left untouched. VMnas will create a ${plan.os_gb || 96} GB OS partition and a ready ${plan.data_gb || 0} GB VMNAS-DATA partition.`;
        updateInstallButton();
      });
    });
  } catch {
    list.innerHTML = "<p>Disk detection failed. Check installer logs.</p>";
  }
}

async function loadPairing() {
  try {
    const pairing = await getJSON("/api/pairing");
    document.querySelector("#pair-code").textContent = pairing.pin;
  } catch {
    document.querySelector("#pair-code").textContent = "------";
  }
}

async function pollInstall() {
  const status = await getJSON("/api/install/status");
  statusPill.textContent = status.state;
  document.querySelector("#install-phase").textContent = status.phase || status.state;
  log.textContent = status.log || "";
  log.scrollTop = log.scrollHeight;
  rebootButton.disabled = !status.reboot_ready;
  failureHelp.classList.toggle("hidden", status.state !== "failed");
  const reportPath = document.querySelector("#install-report-path");
  if (status.report_path) {
    reportPath.textContent = `Saved report: ${status.report_path}`;
    reportPath.classList.remove("hidden");
  } else {
    reportPath.textContent = "";
    reportPath.classList.add("hidden");
  }
  if (status.state === "failed") {
    installButton.disabled = !installReady();
  }
  if (status.state === "running") {
    setTimeout(pollInstall, 1500);
  }
}

document.querySelectorAll(".nav-item").forEach((item) => {
  item.addEventListener("click", () => showStep(steps.indexOf(item.dataset.step)));
});

document.querySelectorAll(".module input").forEach((input) => {
  input.addEventListener("change", () => {
    input.closest(".module").classList.toggle("selected", input.checked);
  });
});

["#nas-cpu", "#nas-ram"].forEach((selector) => {
  const input = document.querySelector(selector);
  input.addEventListener("input", () => {
    updateResourceOutputs();
  });
});

backButton.addEventListener("click", () => showStep(currentStep - 1));
nextButton.addEventListener("click", () => showStep(currentStep + 1));

document.querySelector("#rotate-pin").addEventListener("click", async () => {
  const pairing = await postJSON("/api/pairing/rotate");
  document.querySelector("#pair-code").textContent = pairing.pin;
});

installButton.addEventListener("click", async () => {
  if (!installReady()) return;
  installButton.disabled = true;
  statusPill.textContent = "running";
  log.textContent = "Starting VMnas installation...\n";
  try {
    await postJSON("/api/install/start", installPayload());
    failureHelp.classList.add("hidden");
    pollInstall();
  } catch (error) {
    installButton.disabled = false;
    failureHelp.classList.remove("hidden");
    log.textContent = `Install did not start: ${error.message}\n`;
  }
});

document.querySelector("#erase-confirmation").addEventListener("input", updateInstallButton);
document.querySelector("#admin-password").addEventListener("input", updateInstallButton);
document.querySelector("#admin-password-confirm").addEventListener("input", updateInstallButton);

rebootButton.addEventListener("click", () => {
  postJSON("/api/reboot").catch(() => {
    log.textContent += "\nReboot command is not available in this installer environment.\n";
  });
});

showStep(0);
loadHardware();
loadDisks();
loadPairing();
updateInstallButton();
