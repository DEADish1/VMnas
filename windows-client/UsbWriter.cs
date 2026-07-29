using System.Diagnostics;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace VMnasAdmin.Windows;

public sealed record UsbWriteProgress(double? Percent, string Message);

public static class UsbWriter
{
    private const string DiskQuery = "$removableNumbers = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.MediaType -eq 'Removable Media' -and $_.InterfaceType -eq 'USB' } | ForEach-Object { [int]$_.Index }); Get-Disk | Where-Object { $removableNumbers -contains $_.Number -and -not $_.IsBoot -and -not $_.IsSystem } | Select-Object Number,FriendlyName,SerialNumber,Size,UniqueId,IsOffline,IsReadOnly | ConvertTo-Json -Compress";

    public static async Task<List<UsbDisk>> GetRemovableUsbDisksAsync()
    {
        var json = await RunPowerShellAsync(DiskQuery);
        if (string.IsNullOrWhiteSpace(json) || json.Trim() == "null") return [];
        using var document = JsonDocument.Parse(json);
        IEnumerable<JsonElement> values = document.RootElement.ValueKind == JsonValueKind.Array
            ? document.RootElement.EnumerateArray().ToArray()
            : [document.RootElement];
        return values.Select(value => new UsbDisk(
            value.GetProperty("Number").GetInt32(),
            value.GetProperty("FriendlyName").GetString() ?? "USB disk",
            value.TryGetProperty("SerialNumber", out var serial) ? serial.GetString() ?? "" : "",
            value.GetProperty("Size").GetInt64(),
            value.TryGetProperty("UniqueId", out var uniqueId) ? uniqueId.GetString() ?? "" : ""))
            .Where(disk => disk.Size > 0)
            .OrderBy(disk => disk.Number).ToList();
    }

    public static async Task WriteIsoAsync(string isoPath, List<string> guestMediaPaths, UsbDisk disk, Action<UsbWriteProgress> progress)
    {
        if (guestMediaPaths.Count > 0) throw new InvalidOperationException("Guest media is disabled for bootable server USBs until the boot-library format is complete. Remove the extra files, then write the server installer.");
        if (new FileInfo(isoPath).Length > disk.Size) throw new InvalidOperationException("The selected USB disk is too small for the VMnas installer.");
        var encodedIso = Convert.ToBase64String(Encoding.Unicode.GetBytes(isoPath));
        var encodedId = Convert.ToBase64String(Encoding.Unicode.GetBytes(disk.UniqueId));
        var resultPath = Path.Combine(Path.GetTempPath(), $"vmnas-usb-result-{Guid.NewGuid():N}.txt");
        var encodedResultPath = Convert.ToBase64String(Encoding.Unicode.GetBytes(resultPath));
        var script = $@"
$ErrorActionPreference = 'Stop'
$isoPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{encodedIso}'))
$expectedId = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{encodedId}'))
$resultPath = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{encodedResultPath}'))
function Report([double]$percent, [string]$message) {{ }}
try {{
$disk = Get-Disk -Number {disk.Number}
if ($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne 'USB') {{ throw 'Refusing to write a system or non-USB disk.' }}
$physicalDisk = Get-CimInstance Win32_DiskDrive | Where-Object {{ [int]$_.Index -eq $disk.Number }}
if ($physicalDisk.MediaType -ne 'Removable Media' -or $physicalDisk.InterfaceType -ne 'USB') {{ throw 'Refusing to write a disk that Windows does not classify as removable USB media.' }}
if ($expectedId -and $disk.UniqueId -ne $expectedId) {{ throw 'The selected disk changed. Refresh the drive list and confirm again.' }}
if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {{ throw 'ISO no longer exists.' }}
if ((Get-Item -LiteralPath $isoPath).Length -gt $disk.Size) {{ throw 'The selected ISO is larger than this USB disk.' }}
Clear-Disk -Number $disk.Number -RemoveData -Confirm:$false
Start-Sleep -Seconds 2
try {{
  $source = [IO.File]::Open($isoPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $target = [IO.File]::Open('\\.\PhysicalDrive' + $disk.Number, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
  try {{
    $buffer = New-Object byte[] (4MB); $written = 0L; $total = $source.Length
    while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {{ $target.Write($buffer, 0, $read); $written += $read; Report (70 * $written / $total) ('Writing installer: ' + [Math]::Round($written / 1MB) + ' MB of ' + [Math]::Round($total / 1MB) + ' MB') }}
    $target.Flush($true)
  }} finally {{ $target.Dispose(); $source.Dispose() }}
}} finally {{ Update-Disk -Number $disk.Number }}
Report 70 'Verifying the bootable installer...'
$source = [IO.File]::Open($isoPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$verify = [IO.File]::Open('\\.\PhysicalDrive' + $disk.Number, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
try {{
  $sampleSize = [Math]::Min(16MB, $source.Length); $offsets = @(0)
  if ($source.Length -gt $sampleSize) {{ $offsets += $source.Length - $sampleSize }}
  $hash = [Security.Cryptography.SHA256]::Create(); $sample = 0
  foreach ($offset in $offsets) {{
    $source.Position = $offset; $verify.Position = $offset
    $expected = New-Object byte[] $sampleSize; $actual = New-Object byte[] $sampleSize
    $read = $source.Read($expected, 0, $sampleSize); $actualRead = $verify.Read($actual, 0, $sampleSize)
    if ($read -ne $sampleSize -or $actualRead -ne $sampleSize) {{ throw 'USB verification could not read back the installer sample.' }}
    if ([BitConverter]::ToString($hash.ComputeHash($expected)) -ne [BitConverter]::ToString($hash.ComputeHash($actual))) {{ throw 'USB verification failed. The installer image does not match the source ISO.' }}
    $sample++; Report (70 + 30 * $sample / $offsets.Count) ('Verified installer sample ' + $sample + ' of ' + $offsets.Count)
  }}
}} finally {{ $verify.Dispose(); $source.Dispose() }}
Report 100 'Bootable VMnas installer is ready and verified.'
}} catch {{ try {{ [IO.File]::WriteAllText($resultPath, $_.Exception.Message) }} catch {{ }}; exit 1 }}";
        var encodedScript = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var start = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encodedScript}")
        {
            Verb = "runas", UseShellExecute = true, WindowStyle = ProcessWindowStyle.Normal,
        };
        progress(new UsbWriteProgress(null, "Waiting for Windows administrator permission..."));
        try
        {
            using var process = Process.Start(start) ?? throw new InvalidOperationException("Administrator permission was declined.");
            progress(new UsbWriteProgress(null, "Creating and verifying the bootable installer. This can take several minutes..."));
            await process.WaitForExitAsync();
            if (process.ExitCode != 0)
            {
                var error = File.Exists(resultPath) ? File.ReadAllText(resultPath).Trim() : "The elevated USB writer stopped without an error message.";
                throw new InvalidOperationException(error);
            }
            progress(new UsbWriteProgress(100, "Bootable VMnas installer is ready and verified."));
        }
        finally { if (File.Exists(resultPath)) File.Delete(resultPath); }
    }

    private static async Task MonitorProgressAsync(string progressPath, Process process, Action<UsbWriteProgress> progress)
    {
        var position = 0L;
        async Task ReadPendingUpdatesAsync()
        {
            try
            {
                if (!File.Exists(progressPath)) return;
                using var stream = new FileStream(progressPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                stream.Position = position;
                using var reader = new StreamReader(stream);
                string? line;
                while ((line = await reader.ReadLineAsync()) is not null)
                {
                    try
                    {
                        using var entry = JsonDocument.Parse(line);
                        var percent = entry.RootElement.GetProperty("percent").GetDouble();
                        progress(new UsbWriteProgress(percent < 0 ? null : percent, entry.RootElement.GetProperty("message").GetString() ?? "Writing USB..."));
                    }
                    catch (JsonException) { }
                }
                position = stream.Position;
            }
            catch (IOException) { /* PowerShell owns the log momentarily; retry on the next poll. */ }
        }

        while (!process.HasExited)
        {
            await ReadPendingUpdatesAsync();
            await Task.Delay(160);
        }
        await Task.Delay(160);
        await ReadPendingUpdatesAsync();
    }

    private static async Task<string> RunPowerShellAsync(string command)
    {
        using var process = Process.Start(new ProcessStartInfo("powershell.exe", $"-NoProfile -Command \"{command}\"") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false })
            ?? throw new InvalidOperationException("PowerShell could not start.");
        var output = await process.StandardOutput.ReadToEndAsync();
        var error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0) throw new InvalidOperationException(error);
        return output;
    }
}
