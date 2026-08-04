[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(0, 99)]
    [int]$DiskNumber,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$IsoPath
)

$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:ProgramData 'CamoNAS'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
Start-Transcript -Path (Join-Path $logDirectory 'usb-write.log') -Append | Out-Null

try {
    $disk = Get-Disk -Number $DiskNumber
    $physicalDisk = Get-CimInstance Win32_DiskDrive | Where-Object { [int]$_.Index -eq $DiskNumber }
    if ($null -eq $physicalDisk -or $disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne 'USB' -or $physicalDisk.MediaType -ne 'Removable Media' -or $physicalDisk.InterfaceType -ne 'USB') {
        throw "Disk $DiskNumber is not a removable USB target."
    }

    $iso = Get-Item -LiteralPath $IsoPath
    if ($iso.Length -gt $disk.Size) {
        throw "The ISO is larger than Disk $DiskNumber."
    }

    Write-Host "Writing $($iso.Name) to Disk $DiskNumber ($($disk.FriendlyName))."
    # Removable USB media cannot be taken offline. Clear the selected disk through
    # the Storage API instead of removing its mount point, which can make some USB
    # controllers report the raw device as not ready.
    Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false
    Start-Sleep -Seconds 2
    try {
        $source = [System.IO.File]::Open($iso.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $target = [System.IO.File]::Open("\\.\PhysicalDrive$DiskNumber", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try {
            $buffer = New-Object byte[] (4MB)
            $written = 0L
            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $target.Write($buffer, 0, $read)
                $written += $read
                Write-Host ("Wrote {0:N0} MB" -f ($written / 1MB))
            }
            $target.Flush($true)
        }
        finally {
            $target.Dispose()
            $source.Dispose()
        }
    }
    finally {
        try {
            Update-Disk -Number $DiskNumber
        }
        catch {
            Write-Warning "Windows could not immediately rescan the USB drive: $($_.Exception.Message)"
        }
    }

    $verifyLength = [Math]::Min($iso.Length, 64MB)
    $sourceCheck = [System.IO.File]::Open($iso.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $targetCheck = [System.IO.File]::Open("\\.\PhysicalDrive$DiskNumber", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sourceBytes = New-Object byte[] $verifyLength
        $targetBytes = New-Object byte[] $verifyLength
        [void]$sourceCheck.Read($sourceBytes, 0, $sourceBytes.Length)
        [void]$targetCheck.Read($targetBytes, 0, $targetBytes.Length)
        $hash = [System.Security.Cryptography.SHA256]::Create()
        try {
            if (-not [System.Linq.Enumerable]::SequenceEqual($hash.ComputeHash($sourceBytes), $hash.ComputeHash($targetBytes))) {
                throw 'USB read-back verification failed.'
            }
        }
        finally {
            $hash.Dispose()
        }
    }
    finally {
        $targetCheck.Dispose()
        $sourceCheck.Dispose()
    }

    $disk = Get-Disk -Number $DiskNumber
    if ($disk.LargestFreeExtent -ge 256MB) {
        $dataPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $dataPartition -FileSystem exFAT -NewFileSystemLabel 'CamoNAS' -Confirm:$false | Out-Null
        Write-Host "Created Camo NAS data partition on drive $($dataPartition.DriveLetter):."
    }

    Write-Host 'Camo NAS installer USB is ready.'
}
catch {
    Write-Host "ERROR: $($_.Exception.ToString())"
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
