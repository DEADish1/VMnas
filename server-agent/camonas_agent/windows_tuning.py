from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from xml.sax.saxutils import escape

from .models import WindowsTuningConfig


def create_windows_tuning_iso(vm_name: str, config: WindowsTuningConfig) -> str:
    root = _workspace_root(vm_name)
    staging = root / "staging"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True, exist_ok=True)
    (staging / "autounattend.xml").write_text(_answer_file(config), encoding="utf-8")
    (staging / "camonas-firstlogon.ps1").write_text(_first_logon_script(config), encoding="utf-8")
    (staging / "README.txt").write_text(
        "Camo NAS Windows setup tuning media. Attach this ISO during Windows setup.\n",
        encoding="utf-8",
    )

    output_path, cdrom_ref = _output_location(vm_name)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mkisofs = shutil.which("xorriso") or shutil.which("genisoimage") or shutil.which("mkisofs")
    if not mkisofs:
        if os.environ.get("CAMONAS_ALLOW_MOCK_VMS") == "1":
            return str(staging)
        raise RuntimeError("Windows tuning needs xorriso, genisoimage, or mkisofs installed on the Camo NAS server.")
    if Path(mkisofs).name == "xorriso":
        args = [mkisofs, "-as", "mkisofs", "-J", "-r", "-V", "CAMONAS_WIN_TUNE", "-o", str(output_path), str(staging)]
    else:
        args = [mkisofs, "-J", "-r", "-V", "CAMONAS_WIN_TUNE", "-o", str(output_path), str(staging)]
    subprocess.run(args, check=True, capture_output=True, text=True)
    return cdrom_ref


def create_windows_tuning_test_iso(vmid: int, config: WindowsTuningConfig) -> tuple[str, str]:
    cdrom = create_windows_tuning_iso(f"vm-{vmid}-test", config)
    return cdrom, _first_logon_script(config)


def windows_tuning_script_preview(config: WindowsTuningConfig) -> str:
    return _first_logon_script(config)


def _workspace_root(vm_name: str) -> Path:
    base = Path(os.environ.get("CAMONAS_WINDOWS_TUNING_STORE", "/var/lib/camonas/windows-tuning"))
    if not os.access(base.parent, os.W_OK):
        base = Path.home() / ".camonas" / "windows-tuning"
    safe = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in vm_name).strip(".-") or "windows-vm"
    return base / safe


def _output_location(vm_name: str) -> tuple[Path, str]:
    safe = "".join(ch if ch.isalnum() or ch in "._-" else "-" for ch in vm_name).strip(".-") or "windows-vm"
    filename = f"camonas-{safe}-windows-tuning.iso"
    proxmox_iso_dir = Path("/var/lib/vz/template/iso")
    if os.access(proxmox_iso_dir, os.W_OK):
        return proxmox_iso_dir / filename, f"local:iso/{filename}"
    root = _workspace_root(vm_name)
    return root / filename, str(root / filename)


def _answer_file(config: WindowsTuningConfig) -> str:
    account = escape(config.local_account_name)
    oobe = []
    if config.skip_microsoft_account:
        oobe.append("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>")
    if config.hide_privacy_prompts:
        oobe.extend(
            [
                "<HideEULAPage>true</HideEULAPage>",
                "<ProtectYourPC>3</ProtectYourPC>",
            ]
        )
    oobe.append("<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>")
    first_logon = escape(
        r'cmd /c for %i in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do if exist %i:\camonas-firstlogon.ps1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File %i:\camonas-firstlogon.ps1'
    )
    return f"""<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        {''.join(oobe)}
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <Name>{account}</Name>
            <Group>Administrators</Group>
            <DisplayName>{account}</DisplayName>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <Order>1</Order>
          <Description>Apply Camo NAS Windows tuning</Description>
          <CommandLine>{first_logon}</CommandLine>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
</unattend>
"""


def _first_logon_script(config: WindowsTuningConfig) -> str:
    commands = [
        "$ErrorActionPreference = 'SilentlyContinue'",
        "New-Item -Path 'HKLM:\\SOFTWARE\\CamoNAS' -Force | Out-Null",
        "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\CamoNAS' -Name 'WindowsTuningApplied' -Value 1 -Type DWord",
    ]
    if config.hide_privacy_prompts:
        commands.extend(
            [
                "New-Item -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE' -Force | Out-Null",
                "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE' -Name 'DisablePrivacyExperience' -Value 1 -Type DWord",
                "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE' -Name 'DisableVoice' -Value 1 -Type DWord",
            ]
        )
    if config.disable_consumer_features:
        commands.extend(
            [
                "New-Item -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' -Force | Out-Null",
                "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord",
                "Set-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0 -Type DWord",
            ]
        )
    if config.disable_widgets:
        commands.extend(
            [
                "New-Item -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Dsh' -Force | Out-Null",
                "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Dsh' -Name 'AllowNewsAndInterests' -Value 0 -Type DWord",
            ]
        )
    if config.disable_onedrive_startup:
        commands.append("Remove-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'OneDrive' -Force")
    commands.append("Write-Host 'Camo NAS Windows tuning complete.'")
    return "\n".join(commands) + "\n"
