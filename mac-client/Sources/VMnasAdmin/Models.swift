import Foundation

struct HostResources: Codable {
    let cpuLogical: Int
    let cpuPhysical: Int
    let cpuModel: String
    let architecture: String
    let memoryTotalGb: Double
    let memoryAvailableGb: Double
    let hostReservedGb: Int
    let virtualization: String
    let gpuSummary: [String]

    enum CodingKeys: String, CodingKey {
        case cpuLogical = "cpu_logical"
        case cpuPhysical = "cpu_physical"
        case cpuModel = "cpu_model"
        case architecture
        case memoryTotalGb = "memory_total_gb"
        case memoryAvailableGb = "memory_available_gb"
        case hostReservedGb = "host_reserved_gb"
        case virtualization
        case gpuSummary = "gpu_summary"
    }
}

struct CompatibilityWorkload: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let summary: String
    let details: [String]
}

struct HostCompatibility: Codable {
    let hostSummary: String
    let liveModeHint: String
    let workloads: [CompatibilityWorkload]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case hostSummary = "host_summary"
        case liveModeHint = "live_mode_hint"
        case workloads
        case warnings
    }
}

struct HostDisk: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let sizeGb: Double
    let model: String
    let transport: String
    let driveKind: String
    let removable: Bool
    let importEligible: Bool
    let mountpoints: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case sizeGb = "size_gb"
        case model
        case transport
        case driveKind = "drive_kind"
        case removable
        case importEligible = "import_eligible"
        case mountpoints
    }
}

struct StorageIngestSource: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let sizeGb: Double
    let filesystem: String
    let label: String
    let mountpoint: String
    let removable: Bool
    let transport: String
    let sourceType: String
    let ready: Bool
    let status: String
    let recommendedAction: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case sizeGb = "size_gb"
        case filesystem
        case label
        case mountpoint
        case removable
        case transport
        case sourceType = "source_type"
        case ready
        case status
        case recommendedAction = "recommended_action"
    }
}

struct BenchmarkMetric: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let value: Double
    let unit: String
    let summary: String
}

struct BenchmarkRecommendation: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let capacity: String
    let details: [String]
}

struct SystemBenchmark: Codable {
    let status: String
    let startedAt: String
    let finishedAt: String
    let durationSeconds: Double
    let hostSummary: String
    let metrics: [BenchmarkMetric]
    let recommendations: [BenchmarkRecommendation]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case durationSeconds = "duration_seconds"
        case hostSummary = "host_summary"
        case metrics
        case recommendations
        case warnings
    }
}

struct VmPreset: Codable {
    let name: String
    let label: String
    let osType: String
    let cpuVcpus: Int
    let memoryGb: Int
    let diskGb: Int
    let gpuPassthrough: Bool
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case label
        case osType = "os_type"
        case cpuVcpus = "cpu_vcpus"
        case memoryGb = "memory_gb"
        case diskGb = "disk_gb"
        case gpuPassthrough = "gpu_passthrough"
        case notes
    }
}

struct VmCreateRequest: Codable {
    let name: String
    let osType: String
    let cpuVcpus: Int
    let memoryGb: Int
    let diskGb: Int
    let isoPath: String?
    let networkBridge: String
    let gpuPassthrough: Bool
    let gpuPciAddress: String?
    let windowsTuning: WindowsTuningConfig?

    enum CodingKeys: String, CodingKey {
        case name
        case osType = "os_type"
        case cpuVcpus = "cpu_vcpus"
        case memoryGb = "memory_gb"
        case diskGb = "disk_gb"
        case isoPath = "iso_path"
        case networkBridge = "network_bridge"
        case gpuPassthrough = "gpu_passthrough"
        case gpuPciAddress = "gpu_pci_address"
        case windowsTuning = "windows_tuning"
    }
}

struct WindowsTuningConfig: Codable, Hashable {
    let enabled: Bool
    let localAccountName: String
    let skipMicrosoftAccount: Bool
    let hidePrivacyPrompts: Bool
    let disableConsumerFeatures: Bool
    let disableWidgets: Bool
    let disableOneDriveStartup: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case localAccountName = "local_account_name"
        case skipMicrosoftAccount = "skip_microsoft_account"
        case hidePrivacyPrompts = "hide_privacy_prompts"
        case disableConsumerFeatures = "disable_consumer_features"
        case disableWidgets = "disable_widgets"
        case disableOneDriveStartup = "disable_onedrive_startup"
    }
}

struct WindowsTuningApplyResponse: Codable {
    let vmid: Int
    let cdrom: String
    let scriptPreview: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case vmid
        case cdrom
        case scriptPreview = "script_preview"
        case message
    }
}

struct IsoImage: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let sizeMb: Double

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case sizeMb = "size_mb"
    }
}

enum OsFamily: String, CaseIterable, Identifiable, Codable {
    case linux = "Linux"
    case windows = "Windows"
    case nas = "NAS"
    case network = "Network"
    case backup = "Backup"

    var id: String { rawValue }
}

struct OsStoreItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let family: OsFamily
    let summary: String
    let details: String
    let version: String
    let architecture: String
    let sizeMb: Int
    let tags: [String]
    let license: String
    let downloadUrl: String
    let downloadPage: String
    let downloadSupported: Bool
    let isoPath: String
    let installNotes: [String]
    let installState: ModuleInstallState
    let progress: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case family
        case summary
        case details
        case version
        case architecture
        case sizeMb = "size_mb"
        case tags
        case license
        case downloadUrl = "download_url"
        case downloadPage = "download_page"
        case downloadSupported = "download_supported"
        case isoPath = "iso_path"
        case installNotes = "install_notes"
        case installState = "install_state"
        case progress
    }
}

struct OsDownloadResponse: Codable {
    let id: String
    let installState: String
    let progress: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case id
        case installState = "install_state"
        case progress
        case message
    }
}

struct RemoteAccessStatus: Codable {
    let provider: String
    let installed: Bool
    let running: Bool
    let authenticated: Bool
    let hostname: String
    let remoteIp: String
    let adminUrl: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case provider
        case installed
        case running
        case authenticated
        case hostname
        case remoteIp = "remote_ip"
        case adminUrl = "admin_url"
        case message
    }
}

struct ServerUpdateStatus: Codable {
    let status: String
    let running: Bool
    let startedAt: String
    let finishedAt: String
    let exitCode: Int
    let message: String
    let logTail: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case running
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case exitCode = "exit_code"
        case message
        case logTail = "log_tail"
    }
}

struct GpuDevice: Codable, Identifiable, Hashable {
    var id: String { pciAddress }
    let pciAddress: String
    let name: String
    let vendor: String
    let iommuGroup: String
    let passthroughReady: Bool
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case pciAddress = "pci_address"
        case name
        case vendor
        case iommuGroup = "iommu_group"
        case passthroughReady = "passthrough_ready"
        case notes
    }
}

struct VmAccessLinks: Codable {
    let vmid: Int
    let consoleUrl: String
    let rdpUrl: String
    let sshCommand: String

    enum CodingKeys: String, CodingKey {
        case vmid
        case consoleUrl = "console_url"
        case rdpUrl = "rdp_url"
        case sshCommand = "ssh_command"
    }
}

struct SnapshotRequest: Codable {
    let name: String
}

struct SnapshotSummary: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
}

struct VmSummary: Codable, Identifiable {
    var id: Int { vmid }
    let vmid: Int
    let name: String
    let status: String
    let cpuVcpus: Int?
    let memoryMb: Int?

    enum CodingKeys: String, CodingKey {
        case vmid
        case name
        case status
        case cpuVcpus = "cpu_vcpus"
        case memoryMb = "memory_mb"
    }
}

struct PairingStatus: Codable {
    let enabled: Bool
    let pinHint: String
    let pairedDevices: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case pinHint = "pin_hint"
        case pairedDevices = "paired_devices"
    }
}

struct PairingResponse: Codable {
    let deviceName: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
        case token
    }
}

struct PairedDevice: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct PairingPinResponse: Codable {
    let pin: String
}

enum ModuleCategory: String, CaseIterable, Identifiable, Codable {
    case nas = "NAS"
    case virtualMachines = "VM Tools"
    case containers = "Containers"
    case apps = "Apps"
    case developer = "Developer"
    case gpu = "GPU"
    case backup = "Backup"
    case network = "Network"
    case monitoring = "Monitoring"
    case security = "Security"

    var id: String { rawValue }
}

enum ModuleInstallState: String, Codable {
    case available
    case downloading
    case installed
    case failed

    var label: String {
        switch self {
        case .available: "Available"
        case .downloading: "Downloading"
        case .installed: "Installed"
        case .failed: "Failed"
        }
    }
}

struct StoreModule: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: ModuleCategory
    let summary: String
    let details: String
    let sizeMb: Int
    let required: Bool
    let tags: [String]
    let dependencies: [String]
    let installState: ModuleInstallState
    let progress: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case summary
        case details
        case sizeMb = "size_mb"
        case required
        case tags
        case dependencies
        case installState = "install_state"
        case progress
    }

    init(
        id: String,
        name: String,
        category: ModuleCategory,
        summary: String,
        details: String,
        sizeMb: Int,
        required: Bool,
        tags: [String],
        dependencies: [String] = [],
        installState: ModuleInstallState = .available,
        progress: Int = 0
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.details = details
        self.sizeMb = sizeMb
        self.required = required
        self.tags = tags
        self.dependencies = dependencies
        self.installState = installState
        self.progress = progress
    }
}

extension StoreModule {
    static let catalog: [StoreModule] = [
        StoreModule(
            id: "openmediavault",
            name: "OpenMediaVault NAS",
            category: .nas,
            summary: "Fast lightweight NAS template sized from detected host resources.",
            details: "Downloads the OpenMediaVault installer, creates a tuned NAS VM preset from live CPU/RAM detection, and enables SMB/NFS share helpers.",
            sizeMb: 980,
            required: false,
            tags: ["Recommended", "NAS", "SMB"]
        ),
        StoreModule(
            id: "truenas-scale",
            name: "TrueNAS SCALE",
            category: .nas,
            summary: "Advanced ZFS NAS VM template.",
            details: "Downloads TrueNAS SCALE media and configures a VM profile for disk passthrough and higher memory allocation.",
            sizeMb: 1900,
            required: false,
            tags: ["ZFS", "NAS"]
        ),
        StoreModule(
            id: "windows-guest-kit",
            name: "Windows Guest Kit",
            category: .virtualMachines,
            summary: "VirtIO drivers and Windows VM defaults.",
            details: "Downloads VirtIO drivers, applies Windows 11 VM defaults, and adds RDP launch shortcuts.",
            sizeMb: 720,
            required: false,
            tags: ["Windows", "Drivers"]
        ),
        StoreModule(
            id: "linux-cloud-images",
            name: "Linux Cloud Images",
            category: .virtualMachines,
            summary: "Ubuntu, Debian, and Fedora VM templates.",
            details: "Adds quick-create templates for common Linux servers with cloud-init support.",
            sizeMb: 1600,
            required: false,
            tags: ["Linux", "Templates"]
        ),
        StoreModule(
            id: "nvidia-rtx-passthrough",
            name: "GPU Passthrough",
            category: .gpu,
            summary: "VFIO setup and GPU VM assignment tools.",
            details: "Detects AMD, NVIDIA, Intel, and other PCI display devices, checks IOMMU groups, configures VFIO support, and enables per-VM GPU assignment.",
            sizeMb: 120,
            required: false,
            tags: ["GPU", "VFIO", "AMD", "NVIDIA", "Intel", "Gaming"]
        ),
        StoreModule(
            id: "docker-engine",
            name: "Docker Engine",
            category: .containers,
            summary: "Run containers directly on VMnas.",
            details: "Installs Docker Engine, enables the service, configures storage, and adds a guarded API bridge for the Mac client.",
            sizeMb: 180,
            required: false,
            tags: ["Docker", "Containers", "Runtime"]
        ),
        StoreModule(
            id: "docker-compose",
            name: "Docker Compose",
            category: .containers,
            summary: "Deploy multi-container apps from compose files.",
            details: "Adds Compose support, project folders, environment-file handling, and start/stop/update controls.",
            sizeMb: 46,
            required: false,
            tags: ["Compose", "Stacks"]
        ),
        StoreModule(
            id: "portainer",
            name: "Portainer",
            category: .containers,
            summary: "Web dashboard for Docker containers.",
            details: "Deploys Portainer as a managed container and adds a launch button from the Mac client.",
            sizeMb: 320,
            required: false,
            tags: ["Docker", "Dashboard"]
        ),
        StoreModule(
            id: "k3s",
            name: "K3s Kubernetes",
            category: .containers,
            summary: "Lightweight Kubernetes lab module.",
            details: "Installs K3s for users who want Kubernetes-style app hosting without a full cluster.",
            sizeMb: 95,
            required: false,
            tags: ["Kubernetes", "Lab"]
        ),
        StoreModule(
            id: "home-assistant",
            name: "Home Assistant",
            category: .apps,
            summary: "Smart home server template.",
            details: "Deploys Home Assistant with persistent storage, restart policy, and LAN access.",
            sizeMb: 760,
            required: false,
            tags: ["Smart Home", "Docker"]
        ),
        StoreModule(
            id: "jellyfin",
            name: "Jellyfin Media Server",
            category: .apps,
            summary: "Self-hosted movies, shows, and music.",
            details: "Deploys Jellyfin with movies, TV, music, and photo folders from the VMnas media library. Intended for easy LAN or VPN streaming without subscriptions.",
            sizeMb: 520,
            required: false,
            tags: ["Media", "Streaming", "Movies", "Music"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "plex",
            name: "Plex Media Server",
            category: .apps,
            summary: "Polished streaming server for movies, shows, and music.",
            details: "Deploys Plex with media libraries, hardware-transcode notes for detected GPUs, and LAN discovery-friendly ports.",
            sizeMb: 610,
            required: false,
            tags: ["Media", "Streaming", "GPU"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "emby",
            name: "Emby Media Server",
            category: .apps,
            summary: "Personal media server with broad client support.",
            details: "Deploys Emby with persistent configuration, media folder mapping, and optional GPU acceleration notes.",
            sizeMb: 540,
            required: false,
            tags: ["Media", "Streaming"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "navidrome",
            name: "Navidrome Music Server",
            category: .apps,
            summary: "Fast private music streaming.",
            details: "Deploys Navidrome for personal music streaming from /srv/vmnas/media/music with persistent playlists, users, and scan data.",
            sizeMb: 120,
            required: false,
            tags: ["Media", "Music", "Streaming"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "audiobookshelf",
            name: "Audiobookshelf",
            category: .apps,
            summary: "Audiobook and podcast streaming.",
            details: "Deploys Audiobookshelf with audiobook, podcast, and metadata folders under the VMnas media library.",
            sizeMb: 340,
            required: false,
            tags: ["Media", "Audiobooks", "Podcasts"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "ersatztv",
            name: "ErsatzTV",
            category: .apps,
            summary: "Create live-style channels from your media.",
            details: "Deploys ErsatzTV so users can build custom streaming channels from local movies, shows, and videos stored on the NAS.",
            sizeMb: 520,
            required: false,
            tags: ["Media", "Channels", "Streaming"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "arr-media-stack",
            name: "Arr Media Automation",
            category: .apps,
            summary: "Sonarr, Radarr, Prowlarr, and qBittorrent stack.",
            details: "Stages a Compose stack for TV/movie automation with shared downloads, media folders, and VPN-ready network notes.",
            sizeMb: 980,
            required: false,
            tags: ["Media", "Automation", "Compose"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "immich",
            name: "Immich Photos",
            category: .apps,
            summary: "Private phone photo and video backup.",
            details: "Stages Immich with PostgreSQL, Redis, upload storage, and mobile backup-ready defaults.",
            sizeMb: 1300,
            required: false,
            tags: ["Photos", "Backup", "Mobile"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "photoprism",
            name: "PhotoPrism",
            category: .apps,
            summary: "AI-friendly private photo library.",
            details: "Deploys PhotoPrism with originals/import folders, persistent database storage, and LAN access.",
            sizeMb: 920,
            required: false,
            tags: ["Photos", "Gallery"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "filebrowser",
            name: "File Browser",
            category: .nas,
            summary: "Simple web file manager for NAS shares.",
            details: "Deploys File Browser against the VMnas shares folder for browser-based upload, download, rename, and delete.",
            sizeMb: 95,
            required: false,
            tags: ["NAS", "Files", "Web"],
            dependencies: ["docker-engine"]
        ),
        StoreModule(
            id: "samba-shares",
            name: "SMB Share Manager",
            category: .nas,
            summary: "Windows and macOS file sharing.",
            details: "Installs Samba and stages a default shares configuration for Time Machine-style and general LAN shares.",
            sizeMb: 82,
            required: false,
            tags: ["SMB", "Shares", "Mac"]
        ),
        StoreModule(
            id: "nfs-shares",
            name: "NFS Share Manager",
            category: .nas,
            summary: "Fast Linux and virtualization file shares.",
            details: "Installs NFS server support and stages export templates for Linux clients and VM storage.",
            sizeMb: 56,
            required: false,
            tags: ["NFS", "Shares", "Linux"]
        ),
        StoreModule(
            id: "syncthing",
            name: "Syncthing",
            category: .nas,
            summary: "Peer-to-peer folder sync.",
            details: "Deploys Syncthing with persistent config and a shared data folder for laptop, phone, and server sync.",
            sizeMb: 120,
            required: false,
            tags: ["Sync", "Files"],
            dependencies: ["docker-engine"]
        ),
        StoreModule(
            id: "paperless-ngx",
            name: "Paperless-ngx",
            category: .apps,
            summary: "Document scanning and archive server.",
            details: "Stages Paperless-ngx with PostgreSQL, Redis, consume/export folders, and OCR-ready storage.",
            sizeMb: 780,
            required: false,
            tags: ["Documents", "OCR"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "vaultwarden",
            name: "Vaultwarden",
            category: .security,
            summary: "Lightweight private password vault.",
            details: "Deploys Vaultwarden with persistent encrypted storage and reverse-proxy guidance for remote access.",
            sizeMb: 150,
            required: false,
            tags: ["Passwords", "Security"],
            dependencies: ["docker-engine"]
        ),
        StoreModule(
            id: "nginx-proxy-manager",
            name: "Nginx Proxy Manager",
            category: .network,
            summary: "Friendly reverse proxy and certificate manager.",
            details: "Deploys Nginx Proxy Manager for local service names, HTTPS certificates, and app routing.",
            sizeMb: 460,
            required: false,
            tags: ["Proxy", "HTTPS", "Apps"],
            dependencies: ["docker-engine", "docker-compose"]
        ),
        StoreModule(
            id: "adguard-home",
            name: "AdGuard Home",
            category: .network,
            summary: "Network-wide DNS ad blocking.",
            details: "Deploys AdGuard Home with persistent work/config folders and DNS port mapping notes.",
            sizeMb: 180,
            required: false,
            tags: ["DNS", "Privacy"],
            dependencies: ["docker-engine"]
        ),
        StoreModule(
            id: "duplicati",
            name: "Duplicati",
            category: .backup,
            summary: "Encrypted backups to cloud or another NAS.",
            details: "Deploys Duplicati with access to VMnas share folders and encrypted backup target configuration.",
            sizeMb: 260,
            required: false,
            tags: ["Backup", "Encrypted"],
            dependencies: ["docker-engine"]
        ),
        StoreModule(
            id: "restic-backups",
            name: "Restic Backup Tools",
            category: .backup,
            summary: "Fast encrypted snapshot backups.",
            details: "Installs Restic and stages scripts for encrypted backups of VM configs, shares, and module data.",
            sizeMb: 42,
            required: false,
            tags: ["Backup", "CLI", "Encrypted"]
        ),
        StoreModule(
            id: "nextcloud",
            name: "Nextcloud",
            category: .apps,
            summary: "Private cloud files, sync, and sharing.",
            details: "Deploys Nextcloud with a database, persistent storage, and reverse-proxy-ready settings.",
            sizeMb: 850,
            required: false,
            tags: ["Cloud", "Files"]
        ),
        StoreModule(
            id: "minecraft-server",
            name: "Minecraft Server",
            category: .apps,
            summary: "Game server template with backups.",
            details: "Creates a managed Minecraft server container with memory controls, scheduled backups, and console access.",
            sizeMb: 420,
            required: false,
            tags: ["Game Server", "Java"]
        ),
        StoreModule(
            id: "postgres",
            name: "PostgreSQL",
            category: .developer,
            summary: "Managed database for local apps.",
            details: "Deploys PostgreSQL with persistent volumes, backup hooks, and local network access controls.",
            sizeMb: 390,
            required: false,
            tags: ["Database", "Dev"]
        ),
        StoreModule(
            id: "code-server",
            name: "Code Server",
            category: .developer,
            summary: "Browser-based VS Code on VMnas.",
            details: "Runs a secure code-server instance for editing files and projects hosted on the server.",
            sizeMb: 610,
            required: false,
            tags: ["IDE", "Remote"]
        ),
        StoreModule(
            id: "backup-scheduler",
            name: "Backup Scheduler",
            category: .backup,
            summary: "Scheduled VM backups and retention policies.",
            details: "Adds backup schedules, retention rules, and storage target checks for VM snapshots and archives.",
            sizeMb: 64,
            required: false,
            tags: ["Snapshots", "Retention"]
        ),
        StoreModule(
            id: "tailscale-access",
            name: "Tailscale Remote Access",
            category: .network,
            summary: "Secure access to VMnas away from home.",
            details: "Installs Tailscale on the server and exposes safe links for Proxmox, VMnas, SSH, and selected guest services.",
            sizeMb: 48,
            required: false,
            tags: ["VPN", "Remote"]
        ),
        StoreModule(
            id: "wireguard-local-vpn",
            name: "WireGuard Local VPN Server",
            category: .network,
            summary: "Host your own VPN on the VMnas server.",
            details: "Installs WireGuard, stages a local server configuration, enables IP forwarding notes, and creates client-profile instructions for secure access outside the home network.",
            sizeMb: 32,
            required: false,
            tags: ["VPN", "WireGuard", "Local"]
        ),
        StoreModule(
            id: "monitoring",
            name: "Monitoring Dashboard",
            category: .monitoring,
            summary: "Live CPU, RAM, disk, temperature, and VM graphs.",
            details: "Adds host and guest metric collection with clean charts for daily operations.",
            sizeMb: 240,
            required: false,
            tags: ["Graphs", "Health"]
        ),
        StoreModule(
            id: "security-baseline",
            name: "Security Baseline",
            category: .security,
            summary: "Firewall, SSH hardening, and update policy.",
            details: "Applies safer defaults for SSH, firewall rules, update checks, and admin access.",
            sizeMb: 24,
            required: true,
            tags: ["Required", "Firewall"]
        )
    ]
}
