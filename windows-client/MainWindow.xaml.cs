using Microsoft.Win32;
using System.IO;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CamoNASAdmin.Windows;

public partial class MainWindow : Window
{
    private readonly string _projectRoot;
    private List<UsbDisk> _disks = [];
    private readonly ObservableCollection<string> _guestMedia = [];
    private readonly ServerPairing _serverPairing = new();

    public MainWindow()
    {
        InitializeComponent();
        ApplyRandomCamouflage();
        _projectRoot = FindProjectRoot(AppContext.BaseDirectory);
        IsoPathTextBox.Text = Path.Combine(_projectRoot, "dist", "camonas-server-trixie-amd64.iso");
        GuestMediaListBox.ItemsSource = _guestMedia;
        CatalogComboBox.ItemsSource = GuestMediaCatalog.Items;
        CatalogComboBox.SelectedIndex = 0;
        Loaded += async (_, _) => await RefreshDisksAsync();
    }

    private void ApplyRandomCamouflage()
    {
        foreach (var panel in LayoutGrid.Children.OfType<Border>().Where(panel => Grid.GetRow(panel) is >= 1 and <= 4))
            panel.Background = CreateCamouflageBrush(Random.Shared.Next());
    }

    private static DrawingBrush CreateCamouflageBrush(int seed)
    {
        var random = new Random(seed);
        var drawing = new DrawingGroup();
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(10, 11, 11)), null, new RectangleGeometry(new Rect(0, 0, 1000, 420))));
        var charcoals = new[] { Color.FromRgb(55, 47, 53), Color.FromRgb(67, 56, 63), Color.FromRgb(47, 42, 46) };
        var reds = new[] { Color.FromRgb(244, 24, 24), Color.FromRgb(210, 22, 30), Color.FromRgb(180, 25, 35) };

        // Large overlapping chevrons mimic the dense, angular blocks in the reference.
        for (var index = 0; index < 21; index++)
        {
            var x = random.Next(-180, 940);
            var y = random.Next(-90, 390);
            var width = random.Next(150, 330);
            var height = random.Next(80, 185);
            var red = index % 3 == 0;
            AddChevron(drawing, red ? reds[random.Next(reds.Length)] : charcoals[random.Next(charcoals.Length)], x, y, width, height, random.Next(0, 2) == 0, red || index % 4 == 0, new[] { -48, -25, 0, 22, 46, 90, 135 }[random.Next(7)]);
        }

        // Smaller black cut-outs keep the composition rough and layered rather than decorative.
        for (var index = 0; index < 9; index++)
        {
            AddChevron(drawing, Color.FromRgb(8, 9, 9), random.Next(-100, 960), random.Next(-40, 380), random.Next(120, 260), random.Next(62, 128), random.Next(0, 2) == 0, false, new[] { -45, 0, 45, 90, 135 }[random.Next(5)]);
        }

        return new DrawingBrush(drawing)
        {
            Stretch = Stretch.Fill,
            TileMode = TileMode.None,
            Viewbox = new Rect(0, 0, 1000, 420),
            ViewboxUnits = BrushMappingMode.Absolute
        };
    }

    private static void AddChevron(DrawingGroup drawing, Color color, double x, double y, double width, double height, bool pointsRight, bool striped, double angle)
    {
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            if (pointsRight)
            {
                context.BeginFigure(new Point(x, y + height * .24), true, true);
                context.LineTo(new Point(x + width * .55, y), true, false);
                context.LineTo(new Point(x + width, y + height * .48), true, false);
                context.LineTo(new Point(x + width * .55, y + height), true, false);
                context.LineTo(new Point(x, y + height * .73), true, false);
                context.LineTo(new Point(x + width * .35, y + height * .49), true, false);
            }
            else
            {
                context.BeginFigure(new Point(x + width, y + height * .24), true, true);
                context.LineTo(new Point(x + width * .45, y), true, false);
                context.LineTo(new Point(x, y + height * .48), true, false);
                context.LineTo(new Point(x + width * .45, y + height), true, false);
                context.LineTo(new Point(x + width, y + height * .73), true, false);
                context.LineTo(new Point(x + width * .65, y + height * .49), true, false);
            }
        }
        geometry.Transform = new RotateTransform(angle, x + width / 2, y + height / 2);
        drawing.Children.Add(new GeometryDrawing(new SolidColorBrush(color), null, geometry));
    }

    private async void RefreshDisks_Click(object sender, RoutedEventArgs e) => await RefreshDisksAsync();

    private async Task RefreshDisksAsync()
    {
        SetBusy(true, "Looking for removable USB disks...");
        try
        {
            _disks = await UsbWriter.GetRemovableUsbDisksAsync();
            DiskComboBox.ItemsSource = _disks;
            DiskComboBox.SelectedIndex = _disks.Count > 0 ? 0 : -1;
            if (_disks.Count == 0)
                WarningTextBlock.Text = "No eligible USB disks found. Connect a removable USB drive, then refresh.";
        }
        catch (Exception ex)
        {
            WarningTextBlock.Text = ex.Message;
            AppendLog(ex.ToString());
        }
        finally { SetBusy(false, "Ready."); }
    }

    private void BrowseIso_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "ISO image (*.iso)|*.iso", CheckFileExists = true };
        if (dialog.ShowDialog(this) == true) IsoPathTextBox.Text = dialog.FileName;
    }

    private void AddGuestMedia_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Guest media (*.iso;*.img;*.img.bz2)|*.iso;*.img;*.img.bz2", CheckFileExists = true, Multiselect = true };
        if (dialog.ShowDialog(this) != true) return;
        foreach (var path in dialog.FileNames.Where(IsGuestMedia).Where(path => !_guestMedia.Contains(path))) _guestMedia.Add(path);
        UpdateCapacity();
    }

    private void RemoveGuestMedia_Click(object sender, RoutedEventArgs e)
    {
        if (GuestMediaListBox.SelectedItem is string path) _guestMedia.Remove(path);
        UpdateCapacity();
    }

    private void OpenCatalogPage_Click(object sender, RoutedEventArgs e)
    {
        if (CatalogComboBox.SelectedItem is GuestMediaCatalogItem item)
            Process.Start(new ProcessStartInfo(item.DownloadPage) { UseShellExecute = true });
    }

    private async void DownloadCatalogItem_Click(object sender, RoutedEventArgs e)
    {
        if (CatalogComboBox.SelectedItem is not GuestMediaCatalogItem item || item.DirectUrl is null || item.Sha256 is null) { OpenCatalogPage_Click(sender, e); return; }
        try {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "CamoNAS");
            Directory.CreateDirectory(directory);
            var destination = Path.Combine(directory, item.FileName);
            PairingStatusTextBlock.Text = $"Downloading {item.Name}...";
            using var client = new HttpClient();
            await using (var source = await client.GetStreamAsync(item.DirectUrl)) await using (var target = File.Create(destination)) await source.CopyToAsync(target);
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(File.OpenRead(destination)));
            if (!hash.Equals(item.Sha256, StringComparison.OrdinalIgnoreCase)) { File.Delete(destination); throw new InvalidOperationException("Checksum verification failed."); }
            _guestMedia.Add(destination);
            UpdateCapacity();
            PairingStatusTextBlock.Text = $"Downloaded and verified {item.Name}.";
        }
        catch (Exception ex) { PairingStatusTextBlock.Text = $"Download failed: {ex.Message}"; }
    }

    private async void PairServer_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            PairingStatusTextBlock.Text = "Pairing with Camo NAS server...";
            await _serverPairing.PairAsync(ServerUrlTextBox.Text, DeviceNameTextBox.Text, PairingPinBox.Password);
            PairingPinBox.Clear();
            PairingStatusTextBlock.Text = "Paired securely. The device token is stored in Windows Credential Manager.";
        }
        catch (Exception ex) { PairingStatusTextBlock.Text = $"Pairing failed: {ex.Message}"; }
    }

    private async void RefreshServer_Click(object sender, RoutedEventArgs e)
    {
        try { VmListBox.ItemsSource = await _serverPairing.VmsAsync(ServerUrlTextBox.Text); PairingStatusTextBlock.Text = await _serverPairing.HealthAsync(ServerUrlTextBox.Text); }
        catch (Exception ex) { PairingStatusTextBlock.Text = $"Server unavailable: {ex.Message}"; }
    }

    private async void VmAction_Click(object sender, RoutedEventArgs e)
    {
        if (VmListBox.SelectedItem is not VmSummary vm || sender is not Button button) { PairingStatusTextBlock.Text = "Select a VM first."; return; }
        try { await _serverPairing.VmActionAsync(ServerUrlTextBox.Text, vm.Vmid, button.Tag.ToString()!); await RefreshVmsAsync(); }
        catch (Exception ex) { PairingStatusTextBlock.Text = $"VM action failed: {ex.Message}"; }
    }

    private async Task RefreshVmsAsync()
    {
        VmListBox.ItemsSource = await _serverPairing.VmsAsync(ServerUrlTextBox.Text);
        PairingStatusTextBlock.Text = "Connected to Camo NAS server.";
    }

    private async void DeleteVm_Click(object sender, RoutedEventArgs e)
    {
        if (VmListBox.SelectedItem is not VmSummary vm) { PairingStatusTextBlock.Text = "Select a VM first."; return; }
        if (MessageBox.Show(this, $"Delete VM {vm.Vmid} ({vm.Name})? This cannot be undone.", "Delete VM", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try { await _serverPairing.DeleteVmAsync(ServerUrlTextBox.Text, vm.Vmid); await RefreshVmsAsync(); }
        catch (Exception ex) { PairingStatusTextBlock.Text = $"VM deletion failed: {ex.Message}"; }
    }

    private async void BuildIso_Click(object sender, RoutedEventArgs e)
    {
        SetBusy(true, "Building the server ISO through WSL...");
        try
        {
            var output = await RunAsync("wsl.exe", $"--cd \"{ToWslPath(_projectRoot)}\" -- bash server-os/build-iso.sh");
            AppendLog(output);
            var isoPath = Path.Combine(_projectRoot, "dist", "camonas-server-trixie-amd64.iso");
            if (!File.Exists(isoPath)) throw new InvalidOperationException("The ISO build finished without creating dist\\camonas-server-trixie-amd64.iso.");
            IsoPathTextBox.Text = isoPath;
            StatusTextBlock.Text = "Server ISO built successfully.";
        }
        catch (Exception ex) { AppendLog(ex.Message); StatusTextBlock.Text = "ISO build failed. Install WSL and start Docker Desktop, then try again."; }
        finally { SetBusy(false, StatusTextBlock.Text); }
    }

    private async void WriteUsb_Click(object sender, RoutedEventArgs e)
    {
        if (DiskComboBox.SelectedItem is not UsbDisk disk)
        {
            MessageBox.Show(this, "Choose an existing Camo NAS server ISO and a removable USB drive first.", "Camo NAS Admin", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!File.Exists(IsoPathTextBox.Text))
        {
            MessageBox.Show(this, "Choose an existing Camo NAS server ISO and a removable USB drive first.", "Camo NAS Admin", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        SetBusy(true, $"Writing {disk.DisplayName}. Windows will request administrator permission...");
        WriteProgressPanel.Visibility = Visibility.Visible;
        UpdateWriteProgress(new UsbWriteProgress(null, "Waiting for Windows administrator permission..."));
        try
        {
            await UsbWriter.WriteIsoAsync(IsoPathTextBox.Text, _guestMedia.ToList(), disk, UpdateWriteProgress);
            StatusTextBlock.Text = "USB installer created. Safely eject the drive before booting the server.";
        }
        catch (Exception ex) { AppendLog(ex.ToString()); UpdateWriteProgress(new UsbWriteProgress(null, "USB write failed. See the activity log below.")); StatusTextBlock.Text = "USB write failed."; }
        finally { SetBusy(false, StatusTextBlock.Text); }
    }

    private void DiskComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        WarningTextBlock.Text = DiskComboBox.SelectedItem is UsbDisk disk
            ? $"Warning: writing will erase every partition on {disk.DisplayName}. Verify the physical drive before continuing."
            : "";
        UpdateCapacity();
    }

    private void SetBusy(bool busy, string status) { WriteButton.IsEnabled = !busy; StatusTextBlock.Text = status; }
    private void AppendLog(string message) { LogTextBox.AppendText($"{message.Trim()}\n"); LogTextBox.ScrollToEnd(); }
    private void UpdateWriteProgress(UsbWriteProgress update)
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.Invoke(() => UpdateWriteProgress(update)); return; }
        WriteProgressTextBlock.Text = update.Message;
        WriteProgressBar.IsIndeterminate = update.Percent is null;
        if (update.Percent is not null) WriteProgressBar.Value = update.Percent.Value;
    }

    private static string FindProjectRoot(string start)
    {
        for (var directory = new DirectoryInfo(start); directory != null; directory = directory.Parent)
            if (Directory.Exists(Path.Combine(directory.FullName, "server-os"))) return directory.FullName;
        return Directory.GetCurrentDirectory();
    }

    private static string ToWslPath(string path) => "/mnt/" + char.ToLowerInvariant(path[0]) + path[2..].Replace('\\', '/');
    private static bool IsGuestMedia(string path) => path.EndsWith(".iso", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".img", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".img.bz2", StringComparison.OrdinalIgnoreCase);

    private void UpdateCapacity()
    {
        var serverBytes = File.Exists(IsoPathTextBox.Text) ? new FileInfo(IsoPathTextBox.Text).Length : 0L;
        var mediaBytes = _guestMedia.Where(File.Exists).Sum(path => new FileInfo(path).Length);
        var total = serverBytes + mediaBytes;
        var diskBytes = (DiskComboBox.SelectedItem as UsbDisk)?.Size ?? 0;
        var percent = diskBytes == 0 ? 0 : Math.Min(100, total * 100d / diskBytes);
        CapacityProgressBar.Value = percent;
        CapacityTextBlock.Text = $"Server ISO: {FormatBytes(serverBytes)}  •  Guest media: {FormatBytes(mediaBytes)}  •  Total: {FormatBytes(total)}  •  USB: {FormatBytes(diskBytes)} ({percent:0.0}% used)";
    }

    private static string FormatBytes(long value) => value >= 1024L * 1024 * 1024 ? $"{value / 1024d / 1024d / 1024d:0.00} GB" : $"{value / 1024d / 1024d:0.00} MB";

    private static async Task<string> RunAsync(string executable, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo(executable, arguments) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false })
            ?? throw new InvalidOperationException($"Could not start {executable}.");
        var output = await process.StandardOutput.ReadToEndAsync();
        var error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? output : error);
        return output;
    }
}

public sealed record UsbDisk(int Number, string FriendlyName, string SerialNumber, long Size, string UniqueId)
{
    public string DisplayName => $"Disk {Number}: {FriendlyName} ({Size / 1024d / 1024d / 1024d:0.0} GB)";
}
