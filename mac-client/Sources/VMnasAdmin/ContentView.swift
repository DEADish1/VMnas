import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case virtualMachines = "Virtual Computers"
    case createVM = "New Virtual Computer"
    case windowsTuning = "Windows Tuning"
    case systemTest = "System Test"
    case storage = "NAS & Storage"
    case network = "Internet & Remote"
    case osStore = "OS Store"
    case store = "Apps"
    case usbMaker = "Installer USB"
    case downloads = "Downloads"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .virtualMachines: "rectangle.stack"
        case .createVM: "plus.rectangle.on.rectangle"
        case .windowsTuning: "switch.2"
        case .systemTest: "checkmark.seal"
        case .storage: "externaldrive"
        case .network: "network"
        case .osStore: "opticaldiscdrive"
        case .store: "square.grid.2x2"
        case .usbMaker: "externaldrive.badge.plus"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @StateObject private var api = VMnasAPI()
    @AppStorage("hasCompletedFirstRunSetup") private var hasCompletedFirstRunSetup = false
    @State private var selection: AppSection? = .overview
    @State private var vmName = "nas-01"
    @State private var selectedPresetName = "nas"
    @State private var cpuVcpus = 4.0
    @State private var memoryGb = 8.0
    @State private var diskGb = 128.0
    @State private var isoPath = ""
    @State private var selectedIsoPath = ""
    @State private var gpuPassthrough = false
    @State private var selectedGpuPciAddress = ""
    @State private var autostart = true
    @State private var snapshots = true
    @State private var exposeShares = true
    @State private var windowsTuningEnabled = true
    @State private var windowsLocalAccountName = "vmnas"
    @State private var windowsSkipMicrosoftAccount = true
    @State private var windowsHidePrivacyPrompts = true
    @State private var windowsDisableConsumerFeatures = true
    @State private var windowsDisableWidgets = true
    @State private var windowsDisableOneDriveStartup = true
    @State private var selectedCategory: ModuleCategory? = nil
    @State private var selectedOsFamily: OsFamily? = nil
    @State private var searchText = ""
    @State private var osSearchText = ""
    @State private var pairingPin = ""
    @State private var deviceName = Host.current().localizedName ?? "Mac Admin"
    @State private var showPairingQR = false
    @State private var pendingDeleteVM: VmSummary?
    @State private var usbIsoPath = ""
    @State private var usbExtraIsoURLs: [URL] = []
    @State private var usbDevices: [USBDevice] = []
    @State private var selectedUSBDeviceID = ""
    @State private var usbStatus = "VMnas will load the server ISO automatically when it is built."
    @State private var serverISOStatus = "Checking for VMnas server ISO..."
    @State private var isBuildingServerISO = false
    @State private var isWritingUSB = false
    @State private var showUSBConfirmation = false
    @State private var liveSystemTest = false
    @State private var liveSystemTestTask: Task<Void, Never>?
    @State private var isRunningBenchmark = false
    @State private var isStartingServerUpdate = false
    @State private var selectedWindowsTuningVMID = 0
    @State private var liveVM: VmSummary?
    @State private var liveURL: URL?
    @State private var liveViewerWidth = 760.0
    @State private var liveAspectRatio = "16:9"
    @State private var liveViewerFullscreen = false
    @State private var livePerformanceProfile = "local120"

    private var filteredModules: [StoreModule] {
        api.modules.filter { module in
            let matchesCategory = selectedCategory == nil || module.category == selectedCategory
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || module.name.localizedCaseInsensitiveContains(query)
                || module.summary.localizedCaseInsensitiveContains(query)
                || module.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesSearch
        }
    }

    private var filteredOperatingSystems: [OsStoreItem] {
        api.osStore.filter { item in
            let matchesFamily = selectedOsFamily == nil || item.family == selectedOsFamily
            let query = osSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || item.summary.localizedCaseInsensitiveContains(query)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesFamily && matchesSearch
        }
    }

    private var selectedPreset: VmPreset? {
        api.vmPresets.first { $0.name == selectedPresetName } ?? api.nasPreset
    }

    private var availableSections: [AppSection] {
        AppSection.allCases.filter { section in
            if !api.isConnected {
                return section == .overview || section == .usbMaker || section == .settings
            }
            return section != .store || api.isModuleStoreAvailable
        }
    }

    private var memoryWarning: String? {
        guard let resources = api.resources else { return nil }
        let usable = max(1, resources.memoryTotalGb - Double(resources.hostReservedGb))
        if memoryGb > usable {
            return "This VM uses more RAM than the host should safely allocate."
        }
        if memoryGb > usable * 0.75 {
            return "This VM will consume most available RAM. Stop other VMs first."
        }
        return nil
    }

    private var canCreateVM: Bool {
        let hasName = !vmName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let gpuReady = !gpuPassthrough || api.gpus.contains { $0.pciAddress == selectedGpuPciAddress && $0.passthroughReady }
        return hasName && memoryWarning == nil && gpuReady
    }

    private var maxCpuVcpus: Double {
        Double(max(1, api.resources?.cpuLogical ?? 1))
    }

    private var maxMemoryGb: Double {
        guard let resources = api.resources else { return 1 }
        return max(1, floor(resources.memoryTotalGb - Double(resources.hostReservedGb)))
    }

    private var usbInstallerIsoSize: Int64 {
        fileSize(atPath: usbIsoPath.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var serverISOCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundleResources = Bundle.main.resourcePath ?? ""
        return [
            expectedServerISOPath,
            "\(home)/Documents/VMnas/dist/vmnas-server-trixie-amd64.iso",
            "\(FileManager.default.currentDirectoryPath)/dist/vmnas-server-trixie-amd64.iso",
            "\(bundleResources)/vmnas-server-trixie-amd64.iso"
        ].filter { !$0.isEmpty }
    }

    private var expectedServerISOPath: String {
        "\(projectRootCandidate)/dist/vmnas-server-trixie-amd64.iso"
    }

    private var projectRootCandidate: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/VMnas"
    }

    private var usbExtraIsoTotalSize: Int64 {
        usbExtraIsoURLs.reduce(Int64(0)) { total, url in
            total + fileSize(atPath: url.path)
        }
    }

    private var usbPayloadSize: Int64 {
        usbInstallerIsoSize + usbExtraIsoTotalSize
    }

    private var usbReportPartitionSize: Int64 {
        536_870_912
    }

    private var usbReservedOverhead: Int64 {
        usbReportPartitionSize + (usbExtraIsoURLs.isEmpty ? 0 : 1_073_741_824)
    }

    private var usbRequiredSize: Int64 {
        usbPayloadSize + usbReservedOverhead
    }

    private var usbEstimatedRemainingSize: Int64? {
        guard let device = selectedUSBDevice else { return nil }
        return device.sizeBytes - usbRequiredSize
    }

    private var canMakeInstallerUSB: Bool {
        guard selectedUSBDevice != nil else { return false }
        guard usbInstallerIsoSize > 0 else { return false }
        guard !isWritingUSB else { return false }
        return (usbEstimatedRemainingSize ?? -1) >= 0
    }

    private var installMediaTypes: [UTType] {
        ["iso", "img", "bz2"].compactMap { UTType(filenameExtension: $0) }
    }

    var body: some View {
        NavigationSplitView {
            List(availableSections, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("VMnas")
            .frame(minWidth: 220)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                content
                if let liveVM, let liveURL {
                    liveVMOverlay(vm: liveVM, url: liveURL)
                        .padding(18)
                }
            }
        }
        .task {
            await refresh()
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedFirstRunSetup },
            set: { dismissed in
                if !dismissed {
                    hasCompletedFirstRunSetup = true
                }
            }
        )) {
            firstRunSetup
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection ?? .overview {
        case .overview:
            overview
        case .virtualMachines:
            virtualMachines
        case .createVM:
            createVM
        case .windowsTuning:
            windowsTuning
        case .systemTest:
            systemTest
        case .storage:
            storage
        case .network:
            network
        case .osStore:
            osStore
        case .store:
            if api.isModuleStoreAvailable {
                store
            } else {
                lockedModuleStore
            }
        case .usbMaker:
            usbMaker
        case .downloads:
            downloads
        case .settings:
            settings
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar(title: "Home")

                if let error = api.errorMessage {
                    statusBanner(error)
                }

                if !api.isConnected {
                    setupRequired
                } else {

                    HStack(spacing: 14) {
                        metricTile("CPU Threads", value: api.resources.map { "\($0.cpuLogical)" } ?? "-", systemImage: "cpu")
                        metricTile("Total RAM", value: api.resources.map { formatGb($0.memoryTotalGb) } ?? "-", systemImage: "memorychip")
                        metricTile("Available RAM", value: api.resources.map { formatGb($0.memoryAvailableGb) } ?? "-", systemImage: "chart.bar")
                        metricTile("VMs", value: "\(api.vms.count)", systemImage: "rectangle.stack")
                        metricTile("Updates", value: api.updateStatus?.running == true ? "Running" : (api.updateStatus?.status.capitalized ?? "Idle"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        controlCard(
                            title: "Run Storage",
                            detail: nasRecommendationText,
                            icon: "externaldrive.connected.to.line.below",
                            primary: "Open NAS & Storage",
                            section: .storage
                        )
                        controlCard(
                            title: "Run Virtual Computers",
                            detail: "Start, stop, view, snapshot, or create Windows, Linux, gaming, and NAS systems.",
                            icon: "rectangle.stack",
                            primary: "Open Computers",
                            section: .virtualMachines
                        )
                        controlCard(
                            title: "Install Apps",
                            detail: "Add Plex, Jellyfin, Transmission, Docker, VPN, backups, and more from the server app store.",
                            icon: "square.grid.2x2",
                            primary: "Open Apps",
                            section: .store
                        )
                        controlCard(
                            title: "Stay Connected",
                            detail: "Turn on secure remote access so paired devices can control the server away from home.",
                            icon: "lock.shield",
                            primary: "Remote Access",
                            section: .network
                        )
                    }

                    panel("Virtual Computers") {
                        vmTable(height: 220)
                    }
                }
            }
            .padding(24)
        }
    }

    private var virtualMachines: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "Virtual Computers")
            vmTable(height: nil)
        }
        .padding(24)
    }

    private var windowsTuning: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar(title: "Windows Tuning")

                panel("Target VM") {
                    VStack(alignment: .leading, spacing: 12) {
                        if api.vms.isEmpty {
                            Text("No VMs are loaded from the server yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("VM", selection: $selectedWindowsTuningVMID) {
                                Text("Choose VM").tag(0)
                                ForEach(api.vms) { vm in
                                    Text("\(vm.name) · \(vm.status)").tag(vm.vmid)
                                }
                            }
                            .onAppear {
                                if selectedWindowsTuningVMID == 0 {
                                    selectedWindowsTuningVMID = api.vms.first?.vmid ?? 0
                                }
                            }
                        }
                        Text("This creates a test ISO and attaches it to the VM. Boot Windows, open the VMNAS_WIN_TUNE disc, and run the script as Administrator to test the selected settings.")
                            .foregroundStyle(.secondary)
                    }
                }

                windowsTuningControls

                HStack {
                    Button("Attach Test Media") {
                        Task { await attachWindowsTuningTestMedia() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedWindowsTuningVMID == 0)
                    Button("Refresh VMs") {
                        Task { await refresh() }
                    }
                }

                if let result = api.windowsTuningResult {
                    panel("Test Media") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("VM", value: "\(result.vmid)")
                            LabeledContent("CD-ROM", value: result.cdrom)
                            Text(result.message)
                                .foregroundStyle(.secondary)
                            Text(result.scriptPreview)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var createVM: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar(title: "New Virtual Computer")

                panel("Template") {
                    Picker("Type", selection: $selectedPresetName) {
                        ForEach(api.vmPresets, id: \.name) { preset in
                            Text(preset.label.isEmpty ? preset.name.capitalized : preset.label).tag(preset.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPresetName) {
                        applySelectedPreset()
                    }
                    TextField("Name", text: $vmName)
                        .textFieldStyle(.roundedBorder)
                }

                panel("Resources") {
                    sliderRow("CPU", value: $cpuVcpus, range: 1...maxCpuVcpus, suffix: "vCPU")
                    sliderRow("RAM", value: $memoryGb, range: 1...maxMemoryGb, suffix: "GB")
                    sliderRow("Disk", value: $diskGb, range: 32...2048, suffix: "GB")
                    if let warning = memoryWarning {
                        statusBanner(warning)
                    }
                }

                panel("Options") {
                        Picker("Installer media", selection: $selectedIsoPath) {
                            Text("None").tag("")
                            ForEach(api.isos) { iso in
                                Text("\(iso.name) (\(iso.sizeMb, specifier: "%.0f") MB)").tag(iso.path)
                            }
                        }
                        HStack {
                        TextField("Manual media path", text: $isoPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose Media") {
                            chooseIso()
                        }
                        Button("Refresh") {
                            Task { await api.refreshIsos() }
                        }
                    }
                    Toggle("Start automatically", isOn: $autostart)
                    Toggle("Enable snapshots", isOn: $snapshots)
                    Toggle("Use GPU passthrough", isOn: $gpuPassthrough)
                    Toggle("Expose shares to network", isOn: $exposeShares)
                }

                if selectedPreset?.osType.lowercased().hasPrefix("win") == true {
                    panel("Windows Setup Tuning") {
                        windowsTuningControls
                    }
                }

                panel("GPU Passthrough") {
                    if api.gpus.isEmpty {
                        Text("No GPU passthrough candidates detected yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Assigned GPU", selection: $selectedGpuPciAddress) {
                            Text("None").tag("")
                            ForEach(api.gpus) { gpu in
                                Text(gpuPickerLabel(gpu)).tag(gpu.pciAddress)
                            }
                        }
                        .disabled(!gpuPassthrough)

                        ForEach(api.gpus) { gpu in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gpuPickerLabel(gpu))
                                        .font(.headline)
                                    Text("\(gpu.pciAddress) · IOMMU \(gpu.iommuGroup.isEmpty ? "missing" : gpu.iommuGroup)")
                                        .foregroundStyle(.secondary)
                                    if !gpu.notes.isEmpty {
                                        Text(gpu.notes.joined(separator: " "))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(gpu.passthroughReady ? "Ready" : "Check BIOS")
                                    .foregroundStyle(gpu.passthroughReady ? .green : .orange)
                            }
                        }
                        Text("Only assign a GPU that the host can spare. If AMD is your host/display GPU and NVIDIA is for gaming, choose the NVIDIA card for the gaming VM.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Open Store") {
                        selection = .store
                    }
                    .disabled(!api.isModuleStoreAvailable)
                    Button("Create") {
                        Task { await createSelectedVM() }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canCreateVM)
                }
            }
            .padding(24)
        }
    }

    private var systemTest: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar(title: "System Test")

                panel("Detected Hardware") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(api.compatibility?.hostSummary ?? "Hardware has not been tested yet.")
                            .font(.headline)
                        if let resources = api.resources {
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                                GridRow {
                                    Text("CPU")
                                    Text(resources.cpuModel)
                                }
                                GridRow {
                                    Text("Cores / Threads")
                                    Text("\(resources.cpuPhysical) / \(resources.cpuLogical)")
                                }
                                GridRow {
                                    Text("RAM")
                                    Text("\(formatGb(resources.memoryTotalGb)) total, \(formatGb(resources.memoryAvailableGb)) available")
                                }
                                GridRow {
                                    Text("Virtualization")
                                    Text(resources.virtualization)
                                }
                            }
                        }
                    }
                }

                panel("Live Mode") {
                    HStack {
                        Toggle("Live Mode", isOn: $liveSystemTest)
                            .toggleStyle(.switch)
                        Spacer()
                        Button("Run Test") {
                            Task { await api.refreshCompatibility() }
                        }
                        Button(isRunningBenchmark ? "Benchmarking" : "Run Benchmark") {
                            Task { await runServerBenchmark() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunningBenchmark)
                    }
                    Text(api.compatibility?.liveModeHint ?? "Refreshes system-fit results while you test hardware, drives, and modules.")
                        .foregroundStyle(.secondary)
                }

                panel("Benchmark") {
                    if let benchmark = api.benchmark, benchmark.status == "complete" {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Completed in \(benchmark.durationSeconds, specifier: "%.1f") seconds")
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                                ForEach(benchmark.metrics) { metric in
                                    metricTile(metric.name, value: "\(String(format: "%.1f", metric.value)) \(metric.unit)", systemImage: "speedometer")
                                }
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(benchmark.recommendations) { recommendation in
                                    recommendationRow(recommendation)
                                }
                            }
                        }
                    } else {
                        Text("No benchmark result yet. Run the benchmark after installing server software to get safe workload limits.")
                            .foregroundStyle(.secondary)
                    }
                }

                panel("Detected Storage") {
                    if api.disks.isEmpty {
                        Text("No server disks detected yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        diskList(api.disks)
                    }
                }

                if let compatibility = api.compatibility, !compatibility.warnings.isEmpty {
                    panel("Warnings") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(compatibility.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(api.compatibility?.workloads ?? []) { workload in
                        compatibilityCard(workload)
                    }
                }
            }
            .padding(24)
        }
        .task {
            await api.refreshCompatibility()
            setSystemTestLiveMode(liveSystemTest)
        }
        .onChange(of: liveSystemTest) {
            setSystemTestLiveMode(liveSystemTest)
        }
        .onDisappear {
            liveSystemTestTask?.cancel()
            liveSystemTestTask = nil
        }
    }

    private var storage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar(title: "NAS & Storage")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    metricTile("Detected Drives", value: "\(api.disks.count)", systemImage: "internaldrive")
                    metricTile("Import Drives", value: "\(api.ingestSources.filter(\.ready).count)", systemImage: "externaldrive.badge.plus")
                    metricTile("USB Drives", value: "\(api.disks.filter { $0.transport.lowercased() == "usb" || $0.removable }.count)", systemImage: "externaldrive.connected.to.line.below")
                    metricTile("Largest Drive", value: formatGb(api.disks.map(\.sizeGb).max() ?? 0), systemImage: "externaldrive")
                }

                panel("NAS Setup") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Start with the NAS preset, then add media apps from Apps.", systemImage: "folder.badge.gearshape")
                            .font(.headline)
                        Text("Plex, Jellyfin, Transmission, Samba shares, NFS shares, VPN, and Docker are installed from Apps so the server stays simple until you choose what you need.")
                            .foregroundStyle(.secondary)
                        HStack {
                            actionButton("Create NAS", icon: "plus.rectangle.on.folder") {
                                selectedPresetName = "nas"
                                vmName = "nas-01"
                                applySelectedPreset()
                                selection = .createVM
                            }
                            actionButton("Media Apps", icon: "play.tv", section: .store, category: .apps)
                            actionButton("File Sharing", icon: "person.2.wave.2", section: .store, category: .nas)
                        }
                    }
                }

                panel("Plugged-In Drives For Import") {
                    if api.ingestSources.isEmpty {
                        Text("No USB flash drives or external hard drives are ready for import yet. Plug a drive into the server, then refresh.")
                            .foregroundStyle(.secondary)
                    } else {
                        ingestSourceList(api.ingestSources)
                    }
                }

                panel("All Server Drives") {
                    if api.disks.isEmpty {
                        Text("No server disks detected yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        diskList(api.disks)
                    }
                }
            }
            .padding(24)
        }
        .task {
            await api.refreshCompatibility()
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "Internet & Remote")
            HStack(spacing: 14) {
                metricTile("Bridge", value: "vmbr0", systemImage: "point.3.connected.trianglepath.dotted")
                metricTile("Remote", value: api.remoteStatus?.authenticated == true ? "Ready" : "Off", systemImage: "lock.shield")
                metricTile("Console", value: "noVNC", systemImage: "display")
            }
            panel("Remote Access") {
                remoteAccessControls()
            }
        }
        .padding(24)
    }

    private var store: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "Apps")

            HStack {
                TextField("Search apps", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(ModuleCategory?.none)
                    ForEach(ModuleCategory.allCases) { category in
                        Text(category.rawValue).tag(ModuleCategory?.some(category))
                    }
                }
                .frame(width: 190)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(filteredModules) { module in
                        moduleCard(module)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
    }

    private var lockedModuleStore: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "Apps")
            panel("Server Required") {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Pair this Mac with a running VMnas server before installing Apps.", systemImage: "lock.shield")
                        .font(.headline)
                    Text("Apps install on the server, not on this Mac. Once the server is connected and paired, Apps will appear in the sidebar.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        selection = .settings
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
    }

    private var setupRequired: some View {
        panel("Pair Server") {
            VStack(alignment: .leading, spacing: 12) {
                Label(api.isServerReachable ? "Server found. Pair this Mac to continue." : "No paired server connection.", systemImage: api.isServerReachable ? "link.badge.plus" : "wifi.slash")
                    .font(.headline)
                Text("Hardware specs, VMs, OS downloads, benchmarks, and server modules stay hidden until this Mac is paired with the VMnas server.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Make Installer USB") {
                        selection = .usbMaker
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Settings") {
                        selection = .settings
                    }
                    Button("Refresh") {
                        Task { await refresh() }
                    }
                }
            }
        }
    }

    private var osStore: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "OS Store")

            HStack {
                TextField("Search operating systems", text: $osSearchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Family", selection: $selectedOsFamily) {
                    Text("All").tag(OsFamily?.none)
                    ForEach(OsFamily.allCases) { family in
                        Text(family.rawValue).tag(OsFamily?.some(family))
                    }
                }
                .frame(width: 180)
                Button("Refresh") {
                    Task { await api.refreshOsStore() }
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(filteredOperatingSystems) { item in
                        osCard(item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
    }

    private var windowsTuningControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable VMnas Windows tuning", isOn: $windowsTuningEnabled)
            TextField("Local admin account", text: $windowsLocalAccountName)
                .textFieldStyle(.roundedBorder)
                .disabled(!windowsTuningEnabled)
            Toggle("Skip Microsoft account screens when supported", isOn: $windowsSkipMicrosoftAccount)
                .disabled(!windowsTuningEnabled)
            Toggle("Hide privacy and voice prompts", isOn: $windowsHidePrivacyPrompts)
                .disabled(!windowsTuningEnabled)
            Toggle("Disable consumer app suggestions", isOn: $windowsDisableConsumerFeatures)
                .disabled(!windowsTuningEnabled)
            Toggle("Disable Widgets / news feed policy", isOn: $windowsDisableWidgets)
                .disabled(!windowsTuningEnabled)
            Toggle("Disable OneDrive startup entry", isOn: $windowsDisableOneDriveStartup)
                .disabled(!windowsTuningEnabled)
            Text("VMnas generates a Windows answer-file/test ISO and PowerShell script. It avoids license bypasses and only changes the options selected here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var usbCapacitySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if let device = selectedUSBDevice {
                LabeledContent("Selected drive", value: "\(device.name) · \(device.sizeLabel)")
                LabeledContent("Installer ISO", value: usbInstallerIsoSize > 0 ? formatBytes(usbInstallerIsoSize) : "Not built yet")
                if usbInstallerIsoSize == 0 {
                    Label("Required before writing: build the VMnas server ISO that boots first.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Guest media", value: "\(usbExtraIsoURLs.count) · \(formatBytes(usbExtraIsoTotalSize))")
                LabeledContent("Install reports", value: formatBytes(usbReportPartitionSize))
                LabeledContent("Reserved overhead", value: formatBytes(usbReservedOverhead))
                LabeledContent("Estimated required", value: formatBytes(usbRequiredSize))
                if let remaining = usbEstimatedRemainingSize {
                    LabeledContent("Estimated left", value: remaining >= 0 ? formatBytes(remaining) : "\(formatBytes(abs(remaining))) short")
                        .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                    Text("Estimate is based on selected file sizes plus VMnas library overhead before writing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a USB drive to see estimated remaining space.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usbMaker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar(title: "Installer USB")

                panel("Flash Media Utility") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Create bootable VMnas server installer media from this Mac.", systemImage: "externaldrive.badge.plus")
                            .font(.headline)
                        Text("This utility runs locally on the Mac and stays available before server pairing.")
                            .foregroundStyle(.secondary)
                        Text("The flash drive also gets a VMNAS_LOGS area so failed server installs can save reports for troubleshooting.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Full Disk Access") {
                                openFullDiskAccessSettings()
                            }
                            Button("Reveal VMnas Admin") {
                                revealVMnasAdminInFinder()
                            }
                            Button("Open Files & Folders") {
                                openFilesAndFoldersSettings()
                            }
                        }
                    }
                }

                panel("Installer ISO") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: usbInstallerIsoSize > 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(usbInstallerIsoSize > 0 ? .green : .orange)
                            Text(serverISOStatus)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("VMnas server ISO", text: $usbIsoPath)
                                .textFieldStyle(.roundedBorder)
                            HStack {
                                Button("Auto Load") {
                                    loadBundledServerISO()
                                }
                                Button("Choose ISO") {
                                    chooseUSBISO()
                                }
                                Button("Build Server ISO") {
                                    Task { await buildServerISO() }
                                }
                                .disabled(isBuildingServerISO)
                            }
                        }
                        if usbInstallerIsoSize > 0 {
                            LabeledContent("Installer size", value: formatBytes(usbInstallerIsoSize))
                        } else if isBuildingServerISO {
                            HStack {
                                ProgressView()
                                Text("Building the server ISO. This can take a while.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Expected project output: \(projectRootCandidate)/dist/vmnas-server-trixie-amd64.iso")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                panel("Server ISO Library") {
                    VStack(alignment: .leading, spacing: 10) {
                Text("Optional guest operating system images copied to the USB for the VMnas server to import after install.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if usbExtraIsoURLs.isEmpty {
                            Text("No extra guest media selected.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(usbExtraIsoURLs, id: \.self) { url in
                                HStack {
                                    Image(systemName: "opticaldisc")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(url.lastPathComponent)
                                            .lineLimit(2)
                                        Text(formatBytes(fileSize(atPath: url.path)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        usbExtraIsoURLs.removeAll { $0 == url }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .help("Remove")
                                }
                            }
                        }
                        HStack {
                            Button("Add Guest Media") {
                                chooseUSBExtraISOs()
                            }
                            Button("Clear") {
                                usbExtraIsoURLs = []
                            }
                            .disabled(usbExtraIsoURLs.isEmpty)
                        }
                        if !usbExtraIsoURLs.isEmpty {
                            LabeledContent("Guest media total", value: formatBytes(usbExtraIsoTotalSize))
                        }
                    }
                }

                panel("USB Drive") {
                    if usbDevices.isEmpty {
                        Text("No removable USB drives detected.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Target", selection: $selectedUSBDeviceID) {
                            ForEach(usbDevices) { device in
                                Text("\(device.name) · \(device.sizeLabel) · \(device.deviceNode)").tag(device.id)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    usbCapacitySummary
                    HStack {
                        Button("Refresh USB Drives") {
                            Task { await refreshUSBDevices() }
                        }
                        Button("Make Installer USB") {
                            prepareUSBConfirmation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canMakeInstallerUSB)
                        Button("Run in Terminal") {
                            Task { await openTerminalUSBWriter() }
                        }
                        .disabled(!canMakeInstallerUSB)
                    }
                }

                panel("Status") {
                    HStack {
                        if isWritingUSB {
                            ProgressView()
                        }
                        Text(usbStatus)
                            .foregroundStyle(isWritingUSB ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            loadBundledServerISO()
        }
        .task {
            loadBundledServerISO()
            await refreshUSBDevices()
        }
        .confirmationDialog("Erase USB drive?", isPresented: $showUSBConfirmation) {
            Button("Erase And Make Installer", role: .destructive) {
                Task { await makeUSBInstaller() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let device = selectedUSBDevice {
                Text("This erases \(device.name) at \(device.deviceNode), writes the VMnas boot installer first, creates a VMNAS_LOGS report area, then creates a VMNAS_ISOS partition for \(usbExtraIsoURLs.count) selected guest media file(s). Estimated required: \(formatBytes(usbRequiredSize)). Estimated left: \(formatBytes(max(0, usbEstimatedRemainingSize ?? 0))).")
            } else {
                Text("Select a removable USB drive first.")
            }
        }
    }

    private var downloads: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar(title: "Downloads")
            let activeOperatingSystems = api.osDownloads
            if activeOperatingSystems.isEmpty {
                panel("No Downloads") {
                    Text("Downloaded operating systems will appear here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                panel("Operating Systems") {
                    osDownloadList(activeOperatingSystems)
                }
            }
        }
        .padding(24)
    }

    private var firstRunSetup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Up VMnas Admin")
                        .font(.title2.weight(.semibold))
                    Text("Allow the Mac app to create bootable installer USB drives and read selected ISO files.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Full Disk Access",
                    detail: "Required for writing the VMnas installer directly to a flash drive. macOS will not add this entry automatically; open the pane, then use + or drag VMnas Admin from Finder into the list.",
                    icon: "lock.shield",
                    actionTitle: "Open Full Disk Access",
                    action: openFullDiskAccessSettings
                )
                permissionRow(
                    title: "Files, Folders, and Removable Volumes",
                    detail: "Needed when you choose ISO or IMG files from Desktop, Documents, Downloads, external drives, or iCloud locations.",
                    icon: "folder.badge.gearshape",
                    actionTitle: "Open Files & Folders",
                    action: openFilesAndFoldersSettings
                )
            }

            Text("After enabling permissions, quit and reopen VMnas Admin so macOS applies the changes.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Reveal VMnas Admin") {
                    revealVMnasAdminInFinder()
                }
                Button("Open Full Disk Access") {
                    openFullDiskAccessSettings()
                }
                Spacer()
                Button("Continue") {
                    hasCompletedFirstRunSetup = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func permissionRow(title: String, detail: String, icon: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(actionTitle, action: action)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var settings: some View {
        Form {
            Section("Server") {
                TextField("VMnas server address", text: $api.serverBaseURL)
                Text("Use the server's LAN IP from the VMnas screen, like 192.168.1.50. The app will add the secure VMnas port automatically.")
                    .foregroundStyle(.secondary)
                LabeledContent("Server", value: api.isServerReachable ? "Reachable" : "Not reachable")
                LabeledContent("Admin", value: api.isConnected ? "Paired and connected" : "Not paired")
                Button("Refresh Connection") {
                    Task { await refresh() }
                }
            }
            Section("Server Modules") {
                LabeledContent("Module Store", value: api.isModuleStoreAvailable ? "Unlocked" : "Locked")
                Text(api.moduleStoreStatusText)
                    .foregroundStyle(.secondary)
            }
            Section("Server Updates") {
                if let update = api.updateStatus {
                    LabeledContent("Status", value: update.running ? "Running" : update.status.capitalized)
                    if !update.startedAt.isEmpty {
                        LabeledContent("Started", value: update.startedAt)
                    }
                    if !update.finishedAt.isEmpty {
                        LabeledContent("Finished", value: update.finishedAt)
                    }
                    if update.exitCode != 0 {
                        LabeledContent("Exit code", value: "\(update.exitCode)")
                    }
                    Text(update.message)
                        .foregroundStyle(update.status == "failed" ? .red : .secondary)
                    if !update.logTail.isEmpty {
                        DisclosureGroup("Update Log") {
                            ScrollView {
                                Text(update.logTail.joined(separator: "\n"))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            }
                            .frame(minHeight: 120, maxHeight: 260)
                        }
                    }
                } else {
                    Text("Pair with the server to check or run server updates.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Check Status") {
                        Task { await api.refreshUpdateStatus() }
                    }
                    Button(isStartingServerUpdate || api.updateStatus?.running == true ? "Updating" : "Run Server Update") {
                        Task { await runServerUpdateFromClient() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!api.isConnected || isStartingServerUpdate || api.updateStatus?.running == true)
                }
            }
            Section("Pair This Device") {
                if let status = api.pairingStatus {
                    LabeledContent("Pairing", value: status.enabled ? "Enabled" : "Disabled")
                    LabeledContent("PIN hint", value: status.pinHint)
                    LabeledContent("Paired devices", value: "\(status.pairedDevices)")
                }
                TextField("Device name", text: $deviceName)
                SecureField("6-digit PIN", text: $pairingPin)
                Button(api.deviceToken == nil ? "Pair Device" : "Paired") {
                    Task {
                        await api.pair(deviceName: deviceName, pin: pairingPin)
                        pairingPin = ""
                    }
                }
                .disabled(pairingPin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || api.deviceToken != nil)
                if api.deviceToken != nil {
                    Label("Secure control token saved in Keychain", systemImage: "key.fill")
                        .foregroundStyle(.green)
                }
                HStack {
                    Button("New Pairing PIN") {
                        Task { await api.rotatePairingPin() }
                    }
                    Button("Show QR") {
                        showPairingQR.toggle()
                    }
                }
                if let pin = api.latestPairingPin {
                    LabeledContent("New PIN", value: pin)
                }
                if showPairingQR, let image = pairingQRCode() {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 160, height: 160)
                }
            }
            Section("Paired Devices") {
                if api.pairedDevices.isEmpty {
                    Text("No paired devices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(api.pairedDevices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Button("Revoke") {
                                Task { await api.revokeDevice(id: device.id) }
                            }
                        }
                    }
                }
            }
            Section("Advanced Fallback") {
                Button("Open Proxmox Recovery UI") {
                    if let url = api.proxmoxURL() {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("VMnas is the normal control interface. Use this only for low-level recovery or advanced troubleshooting.")
                    .foregroundStyle(.secondary)
                Toggle("Prefer noVNC browser console", isOn: .constant(true))
                Toggle("Use RDP for Windows VMs", isOn: .constant(true))
            }
            Section("Remote Access") {
                if let remote = api.remoteStatus {
                    LabeledContent("Provider", value: remote.provider.capitalized)
                    LabeledContent("Status", value: remote.authenticated ? "Ready" : remote.message)
                    if !remote.remoteIp.isEmpty {
                        LabeledContent("Remote IP", value: remote.remoteIp)
                    }
                    if !remote.adminUrl.isEmpty {
                        LabeledContent("Remote API", value: remote.adminUrl)
                    }
                }
                Button("Enable Remote Access") {
                    Task { await api.setRemoteAccess(enabled: true) }
                }
                Button("Disable Remote Access") {
                    Task { await api.setRemoteAccess(enabled: false) }
                }
            }
        }
        .padding(24)
        .navigationTitle("Settings")
    }

    private func refresh() async {
        await api.refresh()
        if let selected = selection, !availableSections.contains(selected) {
            selection = .overview
        }
        cpuVcpus = min(cpuVcpus, maxCpuVcpus)
        memoryGb = min(memoryGb, maxMemoryGb)
        if let preset = api.nasPreset {
            cpuVcpus = Double(preset.cpuVcpus)
            memoryGb = Double(preset.memoryGb)
            diskGb = Double(preset.diskGb)
        }
        if selectedPresetName.isEmpty {
            selectedPresetName = api.vmPresets.first?.name ?? "nas"
        }
    }

    private func applySelectedPreset() {
        guard let preset = selectedPreset else { return }
        cpuVcpus = Double(preset.cpuVcpus)
        memoryGb = Double(preset.memoryGb)
        diskGb = Double(preset.diskGb)
        gpuPassthrough = preset.gpuPassthrough
        if gpuPassthrough && selectedGpuPciAddress.isEmpty {
            selectedGpuPciAddress = api.gpus.first(where: { $0.passthroughReady })?.pciAddress ?? ""
        }
        if vmName.isEmpty || vmName == "nas-01" || vmName == "windows-01" || vmName == "linux-01" {
            vmName = "\(preset.name)-01"
        }
    }

    private func createSelectedVM() async {
        let preset = selectedPreset
        let cleanManualIso = isoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenIso = selectedIsoPath.isEmpty ? cleanManualIso : selectedIsoPath
        let request = VmCreateRequest(
            name: vmName.trimmingCharacters(in: .whitespacesAndNewlines),
            osType: preset?.osType ?? "linux",
            cpuVcpus: Int(cpuVcpus),
            memoryGb: Int(memoryGb),
            diskGb: Int(diskGb),
            isoPath: chosenIso.isEmpty ? nil : chosenIso,
            networkBridge: "vmbr0",
            gpuPassthrough: gpuPassthrough,
            gpuPciAddress: gpuPassthrough && !selectedGpuPciAddress.isEmpty ? selectedGpuPciAddress : nil,
            windowsTuning: windowsTuningConfig()
        )
        await api.createVM(request)
    }

    private func gpuPickerLabel(_ gpu: GpuDevice) -> String {
        let vendor = gpu.vendor.isEmpty ? "GPU" : "\(gpu.vendor) GPU"
        return "\(vendor) \(gpu.pciAddress)"
    }

    private func windowsTuningConfig() -> WindowsTuningConfig? {
        guard selectedPreset?.osType.lowercased().hasPrefix("win") == true else {
            return nil
        }
        return currentWindowsTuningConfig()
    }

    private func currentWindowsTuningConfig() -> WindowsTuningConfig {
        return WindowsTuningConfig(
            enabled: windowsTuningEnabled,
            localAccountName: windowsLocalAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "vmnas" : windowsLocalAccountName.trimmingCharacters(in: .whitespacesAndNewlines),
            skipMicrosoftAccount: windowsSkipMicrosoftAccount,
            hidePrivacyPrompts: windowsHidePrivacyPrompts,
            disableConsumerFeatures: windowsDisableConsumerFeatures,
            disableWidgets: windowsDisableWidgets,
            disableOneDriveStartup: windowsDisableOneDriveStartup
        )
    }

    private func attachWindowsTuningTestMedia() async {
        guard selectedWindowsTuningVMID != 0 else { return }
        await api.attachWindowsTuningTestMedia(vmid: selectedWindowsTuningVMID, config: currentWindowsTuningConfig())
    }

    private func chooseIso() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = installMediaTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await api.uploadIso(fileURL: url)
                selectedIsoPath = api.isos.first { $0.name == url.lastPathComponent }?.path ?? selectedIsoPath
            }
        }
    }

    private func chooseUSBISO() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "iso") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            usbIsoPath = url.path
        }
    }

    private func chooseUSBExtraISOs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = installMediaTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let existing = Set(usbExtraIsoURLs)
            usbExtraIsoURLs.append(contentsOf: panel.urls.filter { !existing.contains($0) })
        }
    }

    private func loadBundledServerISO() {
        if usbInstallerIsoSize > 0 {
            serverISOStatus = "Loaded VMnas server ISO: \(URL(fileURLWithPath: usbIsoPath).lastPathComponent)"
            return
        }
        if let path = serverISOCandidates.first(where: { fileSize(atPath: $0) > 0 }) {
            usbIsoPath = path
            serverISOStatus = "Loaded VMnas server ISO automatically."
            usbStatus = "Server ISO loaded automatically. Select a USB drive, then make the installer."
        } else {
            if usbIsoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                usbIsoPath = expectedServerISOPath
            }
            serverISOStatus = "VMnas server ISO path is loaded, but the ISO has not been built yet."
            if usbStatus == "Ready." || usbStatus.isEmpty {
                usbStatus = "Build the VMnas server ISO before making installer media."
            }
        }
    }

    private func buildServerISO() async {
        if usbInstallerIsoSize > 0 {
            serverISOStatus = "Loaded VMnas server ISO: \(URL(fileURLWithPath: usbIsoPath).lastPathComponent)"
            usbStatus = "Server ISO is ready. Select a USB drive, then make the installer."
            return
        }

        loadBundledServerISO()
        if usbInstallerIsoSize > 0 {
            serverISOStatus = "Loaded VMnas server ISO automatically."
            usbStatus = "Server ISO is ready. Select a USB drive, then make the installer."
            return
        }

        isBuildingServerISO = true
        serverISOStatus = "Building VMnas server ISO..."
        usbStatus = "Building the VMnas server ISO. Docker must be installed and running on this Mac."
        do {
            try await USBMaker.buildServerISO(projectRoot: projectRootCandidate)
            usbIsoPath = "\(projectRootCandidate)/dist/vmnas-server-trixie-amd64.iso"
            loadBundledServerISO()
        } catch {
            let message = error.localizedDescription
            serverISOStatus = "Server ISO build failed: \(message)"
            usbStatus = message
        }
        isBuildingServerISO = false
    }

    private var selectedUSBDevice: USBDevice? {
        usbDevices.first { $0.id == selectedUSBDeviceID }
    }

    private func refreshUSBDevices() async {
        do {
            let devices = try await USBMaker.removableDisks()
            usbDevices = devices
            if selectedUSBDeviceID.isEmpty || !devices.contains(where: { $0.id == selectedUSBDeviceID }) {
                selectedUSBDeviceID = devices.first?.id ?? ""
            }
            if usbInstallerIsoSize == 0 {
                usbStatus = "Build the VMnas server ISO before making installer media."
            } else {
                usbStatus = devices.isEmpty ? "Plug in a USB drive, then click Refresh USB Drives." : "Ready."
            }
        } catch {
            usbStatus = error.localizedDescription
        }
    }

    private func prepareUSBConfirmation() {
        guard selectedUSBDevice != nil else {
            usbStatus = "Select a removable USB drive first."
            return
        }
        guard usbInstallerIsoSize > 0 else {
            usbStatus = "The VMnas server ISO path is loaded, but the ISO file does not exist yet. Click Build Server ISO first."
            return
        }
        guard (usbEstimatedRemainingSize ?? -1) >= 0 else {
            usbStatus = "Selected media files are too large for this flash drive. Remove guest media or choose a larger drive."
            return
        }
        showUSBConfirmation = true
    }

    private func makeUSBInstaller() async {
        guard let device = selectedUSBDevice else { return }
        isWritingUSB = true
        usbStatus = "Writing VMnas boot installer first, then adding install reports and \(usbExtraIsoURLs.count) guest media file(s). macOS may ask for your password."
        do {
            try await USBMaker.makeInstaller(
                isoPath: usbIsoPath.trimmingCharacters(in: .whitespacesAndNewlines),
                extraIsoPaths: usbExtraIsoURLs.map(\.path),
                device: device
            )
            usbStatus = "Done. The VMnas installer boots first, VMNAS_LOGS will collect install reports, and \(usbExtraIsoURLs.count) guest media file(s) were staged for server import."
            await refreshUSBDevices()
        } catch {
            usbStatus = error.localizedDescription
        }
        isWritingUSB = false
    }

    private func openTerminalUSBWriter() async {
        guard let device = selectedUSBDevice else { return }
        isWritingUSB = true
        usbStatus = "Preparing a Terminal writer. This stages the installer and selected media before opening Terminal."
        do {
            let script = try await USBMaker.createTerminalWriter(
                isoPath: usbIsoPath.trimmingCharacters(in: .whitespacesAndNewlines),
                extraIsoPaths: usbExtraIsoURLs.map(\.path),
                device: device
            )
            NSWorkspace.shared.open(script)
            usbStatus = "Terminal writer opened. If macOS blocks disk access, give Terminal Full Disk Access, then run the script again."
        } catch {
            usbStatus = error.localizedDescription
        }
        isWritingUSB = false
    }

    private func openAccess(for vm: VmSummary, mode: String) async {
        guard let links = await api.accessLinks(vmid: vm.vmid) else { return }
        switch mode {
        case "console":
            if let url = URL(string: links.consoleUrl) {
                NSWorkspace.shared.open(url)
            }
        case "rdp":
            if let url = URL(string: links.rdpUrl), !links.rdpUrl.isEmpty {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func openLiveVM(_ vm: VmSummary) async {
        guard let links = await api.accessLinks(vmid: vm.vmid),
              let url = URL(string: links.consoleUrl)
        else {
            return
        }
        liveVM = vm
        liveURL = url
        liveViewerFullscreen = false
    }

    private func pairingQRCode() -> NSImage? {
        let baseURL = api.serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "type": "vmnas-pairing",
            "version": 1,
            "server_name": "VMnas Server",
            "api_url": baseURL,
            "urls": [baseURL],
            "pin": api.latestPairingPin ?? pairingPin,
            "pair_endpoint": "/pairing/pair",
            "status_endpoint": "/pairing/status",
            "discovery_endpoint": "/discovery"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            return nil
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func topBar(title: String) -> some View {
        HStack {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Spacer()
            TextField("Server", text: $api.serverBaseURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
    }

    private func metricTile(_ title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(value)
                .font(.title2.weight(.semibold))
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func controlCard(title: String, detail: String, icon: String, primary: String, section: AppSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Spacer()
            }
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(primary) {
                selection = section
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(16)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func formatGb(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func fileSize(atPath path: String) -> Int64 {
        guard !path.isEmpty else { return 0 }
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else {
            return 0
        }
        return Int64(size)
    }

    private var nasRecommendationText: String {
        guard let resources = api.resources else {
            return "VMnas will size the NAS preset after it detects the host CPU and memory."
        }
        let gpuText = resources.gpuSummary.isEmpty ? "No passthrough GPU detected yet." : "Detected GPU: \(resources.gpuSummary[0])"
        return "Detected \(resources.cpuModel) with \(resources.cpuLogical) logical threads and \(formatGb(resources.memoryTotalGb)) RAM. OpenMediaVault is the lightweight first NAS choice. \(gpuText)"
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func statusBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func liveVMOverlay(vm: VmSummary, url: URL) -> some View {
        let aspect = liveAspectValue
        let width = liveViewerFullscreen ? 1180.0 : liveViewerWidth
        let height = width / aspect
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("\(vm.name) Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Picker("Aspect", selection: $liveAspectRatio) {
                    Text("16:9").tag("16:9")
                    Text("16:10").tag("16:10")
                    Text("4:3").tag("4:3")
                    Text("1:1").tag("1:1")
                }
                .labelsHidden()
                .frame(width: 96)
                Picker("Performance", selection: $livePerformanceProfile) {
                    Text("Local 120").tag("local120")
                    Text("Remote 60-120").tag("remoteAdaptive")
                    Text("60 Hz").tag("balanced60")
                }
                .labelsHidden()
                .frame(width: 138)
                .onChange(of: livePerformanceProfile) {
                    if let vm = liveVM {
                        Task { await openLiveVM(vm) }
                    }
                }
                Slider(value: $liveViewerWidth, in: 480...1180, step: 20)
                    .frame(width: 140)
                    .disabled(liveViewerFullscreen)
                Button {
                    liveViewerFullscreen.toggle()
                } label: {
                    Image(systemName: liveViewerFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help(liveViewerFullscreen ? "Exit fullscreen size" : "Fullscreen size")
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open in browser")
                Button {
                    liveVM = nil
                    liveURL = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close live view")
            }
            .padding(10)

            HStack {
                Text(livePerformanceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            LiveVMWebView(url: tunedLiveURL(url))
                .frame(width: width, height: height)
                .background(.black)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
        .shadow(radius: 18)
    }

    private var liveAspectValue: Double {
        switch liveAspectRatio {
        case "16:10": return 16.0 / 10.0
        case "4:3": return 4.0 / 3.0
        case "1:1": return 1.0
        default: return 16.0 / 9.0
        }
    }

    private var livePerformanceDescription: String {
        switch livePerformanceProfile {
        case "remoteAdaptive":
            return "Remote adaptive target: 60-120 Hz with compression for outside-home links."
        case "balanced60":
            return "Balanced target: 60 Hz for lower bandwidth or battery use."
        default:
            return "Local target: 120 Hz, low compression, keyboard and mouse captured in the live view."
        }
    }

    private func tunedLiveURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        func set(_ name: String, _ value: String) {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        set("resize", "scale")
        set("keyboard", "1")
        set("mouse", "1")
        switch livePerformanceProfile {
        case "remoteAdaptive":
            set("vmnas_profile", "remote-adaptive")
            set("fps_min", "60")
            set("fps", "120")
            set("quality", "7")
            set("compression", "2")
        case "balanced60":
            set("vmnas_profile", "balanced-60")
            set("fps", "60")
            set("quality", "6")
            set("compression", "4")
        default:
            set("vmnas_profile", "local-120")
            set("fps", "120")
            set("quality", "9")
            set("compression", "0")
        }
        components.queryItems = items
        return components.url ?? url
    }

    private func vmTable(height: CGFloat?) -> some View {
        Table(api.vms) {
            TableColumn("ID") { vm in Text("\(vm.vmid)") }
            TableColumn("Name", value: \.name)
            TableColumn("Status", value: \.status)
            TableColumn("CPU") { vm in Text(vm.cpuVcpus.map(String.init) ?? "-") }
            TableColumn("RAM") { vm in Text(vm.memoryMb.map { "\($0 / 1024) GB" } ?? "-") }
            TableColumn("Actions") { vm in
                HStack(spacing: 6) {
                    Button {
                        Task { await api.performVMAction(vmid: vm.vmid, action: "start") }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Start")
                    .disabled(vm.status == "running")

                    Button {
                        Task { await api.performVMAction(vmid: vm.vmid, action: "shutdown") }
                    } label: {
                        Image(systemName: "power")
                    }
                    .help("Graceful shutdown")
                    .disabled(vm.status != "running")

                    Button {
                        Task { await api.performVMAction(vmid: vm.vmid, action: "stop") }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("Force stop")
                    .disabled(vm.status != "running")

                    Button {
                        Task { await api.performVMAction(vmid: vm.vmid, action: "reboot") }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reboot")
                    .disabled(vm.status != "running")

                    Button {
                        Task { await openLiveVM(vm) }
                    } label: {
                        Label("Live", systemImage: "play.rectangle")
                    }
                    .help("Open live console in VMnas")
                    .disabled(vm.status != "running")

                    Button {
                        Task { await openAccess(for: vm, mode: "console") }
                    } label: {
                        Image(systemName: "display")
                    }
                    .help("Open console")

                    Button {
                        Task { await openAccess(for: vm, mode: "rdp") }
                    } label: {
                        Image(systemName: "macwindow")
                    }
                    .help("Open RDP")

                    Button {
                        Task { await api.createSnapshot(vmid: vm.vmid, name: "snap-\(Int(Date().timeIntervalSince1970))") }
                    } label: {
                        Image(systemName: "camera")
                    }
                    .help("Create snapshot")

                    Button {
                        pendingDeleteVM = vm
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete VM")
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(height: height)
        .confirmationDialog("Delete VM?", isPresented: Binding(
            get: { pendingDeleteVM != nil },
            set: { if !$0 { pendingDeleteVM = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let vm = pendingDeleteVM {
                    Task { await api.deleteVM(vmid: vm.vmid) }
                }
                pendingDeleteVM = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteVM = nil
            }
        } message: {
            Text("This removes the VM from the server.")
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func moduleCard(_ module: StoreModule) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(module.name)
                        .font(.headline)
                    Text(module.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if module.required {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.green)
                        .help("Recommended security module")
                }
            }

            Text(module.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(module.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                ForEach(module.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text("\(module.sizeMb) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(buttonTitle(for: module)) {
                    startDownload(module)
                }
                .disabled(module.installState == .downloading || module.installState == .installed)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func compatibilityCard(_ workload: CompatibilityWorkload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workload.name)
                        .font(.headline)
                    Text(workload.status)
                        .font(.caption)
                        .foregroundStyle(compatibilityColor(workload.status))
                }
                Spacer()
                Image(systemName: compatibilityIcon(workload.status))
                    .foregroundStyle(compatibilityColor(workload.status))
            }
            Text(workload.summary)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(workload.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func diskList(_ disks: [HostDisk]) -> some View {
        VStack(spacing: 10) {
            ForEach(disks) { disk in
                HStack {
                    Image(systemName: disk.removable || disk.transport.lowercased() == "usb" ? "externaldrive" : "internaldrive")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(disk.model.isEmpty ? disk.name : disk.model)
                            .font(.headline)
                        Text("\(disk.path) - \(disk.driveKind) - \(disk.transport.isEmpty ? "unknown" : disk.transport)")
                            .foregroundStyle(.secondary)
                        if !disk.mountpoints.isEmpty {
                            Text("Mounted: \(disk.mountpoints.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(formatGb(disk.sizeGb))
                            .foregroundStyle(.secondary)
                        Text(disk.importEligible ? "Import source" : (disk.removable ? "Needs mount" : "Server drive"))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(disk.importEligible ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func ingestSourceList(_ sources: [StorageIngestSource]) -> some View {
        VStack(spacing: 10) {
            ForEach(sources) { source in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: source.ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(source.ready ? .green : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(source.name.isEmpty ? source.path : source.name)
                            .font(.headline)
                        Text("\(source.status) - \(source.sourceType) - \(formatGb(source.sizeGb)) - \(source.transport.isEmpty ? "unknown" : source.transport)")
                            .foregroundStyle(.secondary)
                        if !source.mountpoint.isEmpty {
                            Text("Mounted at \(source.mountpoint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(source.recommendedAction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(source.filesystem.isEmpty ? "Drive" : source.filesystem.uppercased())
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        Text(source.ready ? "Can import" : "Not ready")
                            .font(.caption)
                            .foregroundStyle(source.ready ? .green : .orange)
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func recommendationRow(_ recommendation: BenchmarkRecommendation) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.name)
                    .font(.headline)
                Text(recommendation.capacity)
                    .font(.subheadline.weight(.semibold))
                ForEach(recommendation.details, id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func osCard(_ item: OsStoreItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name)
                        .font(.headline)
                    Text("\(item.family.rawValue) · \(item.version.isEmpty ? item.architecture : item.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: item.downloadSupported ? "arrow.down.circle" : "safari")
                    .foregroundStyle(item.downloadSupported ? .blue : .secondary)
            }

            Text(item.summary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                ForEach(item.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(item.sizeMb > 0 ? "\(item.sizeMb) MB" : item.license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.installState == .downloading {
                    ProgressView(value: Double(item.progress), total: 100)
                        .frame(width: 80)
                }
                if item.installState == .installed, !item.isoPath.isEmpty {
                    Button("Create VM") {
                        createVMFromDownloadedOS(item)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(osButtonTitle(for: item)) {
                        startOSDownload(item)
                    }
                    .disabled(item.installState == .downloading || item.installState == .installed)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func osDownloadList(_ systems: [OsStoreItem]) -> some View {
        VStack(spacing: 10) {
            ForEach(systems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.summary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.installState.label)
                        .foregroundStyle(.secondary)
                    if item.installState == .downloading {
                        ProgressView(value: Double(item.progress), total: 100)
                            .frame(width: 90)
                    }
                    if item.installState == .installed, !item.isoPath.isEmpty {
                        Button("Create VM") {
                            createVMFromDownloadedOS(item)
                        }
                    } else {
                        Button(osButtonTitle(for: item)) {
                            startOSDownload(item)
                        }
                        .disabled(item.installState == .downloading || item.installState == .installed)
                    }
                }
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func remoteAccessControls() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let remote = api.remoteStatus {
                HStack {
                    Image(systemName: remote.authenticated ? "checkmark.circle.fill" : "lock.shield")
                        .foregroundStyle(remote.authenticated ? .green : .secondary)
                    Text(remote.message)
                    Spacer()
                }
                if !remote.remoteIp.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Remote IP")
                            Text(remote.remoteIp)
                        }
                        GridRow {
                            Text("Remote API")
                            Text(remote.adminUrl)
                        }
                    }
                }
            } else {
                Text("Remote access status has not loaded.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Enable") {
                    Task { await api.setRemoteAccess(enabled: true) }
                }
                Button("Disable") {
                    Task { await api.setRemoteAccess(enabled: false) }
                }
                Button("Refresh") {
                    Task { await api.refreshRemoteStatus() }
                }
            }
        }
    }

    private func compatibilityIcon(_ status: String) -> String {
        switch status {
        case "Excellent": "checkmark.circle.fill"
        case "Good": "checkmark.circle"
        case "Limited": "exclamationmark.circle"
        default: "wrench.and.screwdriver"
        }
    }

    private func compatibilityColor(_ status: String) -> Color {
        switch status {
        case "Excellent": .green
        case "Good": .blue
        case "Limited": .orange
        default: .secondary
        }
    }

    private func setSystemTestLiveMode(_ enabled: Bool) {
        liveSystemTestTask?.cancel()
        liveSystemTestTask = nil
        guard enabled else { return }
        liveSystemTestTask = Task {
            while !Task.isCancelled {
                await api.refreshCompatibility()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func runServerBenchmark() async {
        isRunningBenchmark = true
        await api.runBenchmark()
        isRunningBenchmark = false
    }

    private func runServerUpdateFromClient() async {
        isStartingServerUpdate = true
        await api.runServerUpdate()
        isStartingServerUpdate = false
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await api.refreshUpdateStatus()
    }

    private func openFullDiskAccessSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            revealVMnasAdminInFinder()
        }
    }

    private func openFilesAndFoldersSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    private func openSystemSettingsPane(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealVMnasAdminInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    private func actionButton(_ title: String, icon: String, section: AppSection, category: ModuleCategory? = nil) -> some View {
        actionButton(title, icon: icon) {
            selection = section
            selectedCategory = category
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buttonTitle(for module: StoreModule) -> String {
        switch module.installState {
        case .available: "Download"
        case .downloading: "Downloading"
        case .installed: "Installed"
        case .failed: "Retry"
        }
    }

    private func startDownload(_ module: StoreModule) {
        Task {
            await api.installModule(id: module.id)
        }
    }

    private func osButtonTitle(for item: OsStoreItem) -> String {
        if !item.downloadSupported {
            return "Open Page"
        }
        return switch item.installState {
        case .available: "Download"
        case .downloading: "Downloading"
        case .installed: "Downloaded"
        case .failed: "Retry"
        }
    }

    private func startOSDownload(_ item: OsStoreItem) {
        if !item.downloadSupported {
            if let url = URL(string: item.downloadPage), !item.downloadPage.isEmpty {
                NSWorkspace.shared.open(url)
            }
            return
        }
        Task {
            await api.downloadOS(id: item.id)
        }
    }

    private func createVMFromDownloadedOS(_ item: OsStoreItem) {
        selectedIsoPath = item.isoPath
        isoPath = ""
        switch item.family {
        case .windows:
            selectedPresetName = "windows"
            vmName = "windows-01"
        case .nas:
            selectedPresetName = "nas"
            vmName = "\(item.id.replacingOccurrences(of: "-iso", with: ""))-01"
        default:
            selectedPresetName = "linux"
            vmName = "\(item.id)-01"
        }
        applySelectedPreset()
        if !item.isoPath.isEmpty {
            selectedIsoPath = item.isoPath
        }
        selection = .createVM
    }
}
