namespace VMnasAdmin.Windows;

public sealed record GuestMediaCatalogItem(string Name, string FileName, string DownloadPage, string? DirectUrl = null, string? Sha256 = null)
{
    public bool RequiresBrowserFlow => DirectUrl is null;
}

public static class GuestMediaCatalog
{
    // Direct downloads are enabled only when the publisher provides a stable, redistributable URL.
    public static readonly IReadOnlyList<GuestMediaCatalogItem> Items = [
        new("Bazzite NVIDIA", "bazzite-nvidia-open-stable-live-amd64.iso", "https://bazzite.gg/"),
        new("CachyOS Desktop", "cachyos-desktop-linux-260628.iso", "https://wiki.cachyos.org/cachyos_basic/download/", "https://iso.cachyos.org/desktop/260628/cachyos-desktop-linux-260628.iso", "136c84942eacdc6deed205fe7018c69fe7b70757f2f9b4010936ee05e060f336"),
        new("Garuda Cinnamon", "garuda-cinnamon-linux-zen-260309.iso", "https://garudalinux.org/downloads"),
        new("Garuda Gaming", "garuda-dr460nized-gaming-linux-zen-260309.iso", "https://garudalinux.org/downloads"),
        new("Nobara Official", "Nobara-43-Official-2026-04-19.iso", "https://nobaraproject.org/download.html"),
        new("Pop!_OS NVIDIA", "pop-os_24.04_amd64_nvidia_27.iso", "https://pop.system76.com/"),
        new("SteamOS Recovery", "steamdeck-oobe-repair-20260707.10-3.8.14.img.bz2", "https://store.steampowered.com/steamos/download?ver=steamdeck"),
        new("Windows 11", "Win11_25H2_English_x64_v2.iso", "https://www.microsoft.com/software-download/windows11"),
        new("ZimaOS", "zimaos-x86_64-1.6.2_installer.img", "https://www.zimaspace.com/zimaos/")
    ];
}
