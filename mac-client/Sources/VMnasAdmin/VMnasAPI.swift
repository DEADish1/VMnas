import Darwin
import Foundation

@MainActor
final class VMnasAPI: ObservableObject {
    @Published var serverBaseURL = "https://vmnas.local:8765"
    @Published var resources: HostResources?
    @Published var compatibility: HostCompatibility?
    @Published var disks: [HostDisk] = []
    @Published var ingestSources: [StorageIngestSource] = []
    @Published var benchmark: SystemBenchmark?
    @Published var nasPreset: VmPreset?
    @Published var vmPresets: [VmPreset] = []
    @Published var vms: [VmSummary] = []
    @Published var isos: [IsoImage] = []
    @Published var osStore: [OsStoreItem] = []
    @Published var osDownloads: [OsStoreItem] = []
    @Published var remoteStatus: RemoteAccessStatus?
    @Published var updateStatus: ServerUpdateStatus?
    @Published var gpus: [GpuDevice] = []
    @Published var modules: [StoreModule] = []
    @Published var downloads: [StoreModule] = []
    @Published var pairingStatus: PairingStatus?
    @Published var pairedDevices: [PairedDevice] = []
    @Published var latestPairingPin: String?
    @Published var windowsTuningResult: WindowsTuningApplyResponse?
    @Published var deviceToken: String?
    @Published var isServerReachable = false
    @Published var isConnected = false
    @Published var isDiscoveringServer = false
    @Published var connectionMessage = "Click Find Server, then enter the pairing code shown on the VMnas server."
    @Published var discoveredURLs: [String] = []
    @Published var errorMessage: String?

    var isModuleStoreAvailable: Bool {
        isConnected && deviceToken != nil
    }

    var moduleStoreStatusText: String {
        if !isServerReachable {
            return "Connect to a VMnas server first."
        }
        if deviceToken == nil {
            return "Pair this Mac with the server to unlock server Apps."
        }
        if !isConnected {
            return "Refresh the paired server connection to load server Apps."
        }
        return "Ready. Apps will install on the connected VMnas server."
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    private let session: URLSession = {
        let delegate = VMnasURLSessionDelegate()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()
    private let discoverySession: URLSession = {
        let delegate = VMnasURLSessionDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.85
        configuration.timeoutIntervalForResource = 1.2
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }()

    func refresh() async {
        loadTokenIfNeeded()
        normalizeServerAddress()
        do {
            let pairing: PairingStatus = try await get("/pairing/status")
            self.pairingStatus = pairing
            self.isServerReachable = true
            self.connectionMessage = deviceToken == nil ? "Server found. Enter the pairing code to connect this Mac." : "Server found."

            guard deviceToken != nil else {
                clearAdminData()
                self.errorMessage = nil
                return
            }

            let resources: HostResources = try await get("/host/resources")
            self.resources = resources
            self.isConnected = true
            self.connectionMessage = "Paired and connected."
            self.errorMessage = nil

            async let compatibility: HostCompatibility? = getOptional("/host/compatibility")
            async let disks: [HostDisk]? = getOptional("/host/disks")
            async let ingestSources: [StorageIngestSource]? = getOptional("/storage/ingest-sources")
            async let benchmark: SystemBenchmark? = getOptional("/host/benchmark/latest")
            async let preset: VmPreset? = getOptional("/presets/nas")
            async let presets: [VmPreset]? = getOptional("/presets/vms")
            async let isos: [IsoImage]? = getOptional("/isos")
            async let osStore: [OsStoreItem]? = getOptional("/os-store/systems")
            async let osDownloads: [OsStoreItem]? = getOptional("/os-store/downloads")
            async let remote: RemoteAccessStatus? = getOptional("/remote/status")
            async let updateStatus: ServerUpdateStatus? = getOptional("/system/update/status")
            async let gpus: [GpuDevice]? = getOptional("/host/gpus")
            async let devices: [PairedDevice]? = getOptional("/pairing/devices")
            self.compatibility = await compatibility
            self.disks = await disks ?? []
            self.ingestSources = await ingestSources ?? []
            self.benchmark = await benchmark
            self.nasPreset = await preset ?? defaultNasPreset(resources: resources)
            self.vmPresets = await presets ?? [self.nasPreset].compactMap { $0 }
            self.isos = await isos ?? []
            self.osStore = await osStore ?? []
            self.osDownloads = await osDownloads ?? []
            self.remoteStatus = await remote
            self.updateStatus = await updateStatus
            self.gpus = await gpus ?? []
            self.pairedDevices = await devices ?? []

            do {
                let vms: [VmSummary] = try await get("/vms")
                self.vms = vms
            } catch {
                self.vms = []
                self.errorMessage = "Paired with server. VM inventory is not available yet: \(error.localizedDescription)"
            }

            if isModuleStoreAvailable {
                await refreshStore()
            } else {
                self.modules = []
                self.downloads = []
            }
            if self.errorMessage?.hasPrefix("Paired with server. VM inventory is not available yet:") != true {
                self.errorMessage = nil
            }
        } catch {
            self.isServerReachable = false
            clearAdminData()
            if !isDiscoveringServer {
                self.connectionMessage = "Could not reach a VMnas server. Click Find Server or type the server address from the VMnas screen."
            }
            self.errorMessage = error.localizedDescription
        }
    }

    func findServer() async {
        isDiscoveringServer = true
        connectionMessage = "Looking for VMnas on this network..."
        errorMessage = nil
        defer { isDiscoveringServer = false }

        let candidates = discoveryCandidates()
        discoveredURLs = candidates

        if let found = await firstReachableServer(in: candidates) {
            serverBaseURL = found
            deviceToken = KeychainStore.readToken(serverURL: serverBaseURL)
            connectionMessage = "Server found at \(serverBaseURL). Enter the pairing code to connect."
            await refresh()
            return
        }

        isServerReachable = false
        clearAdminData()
        connectionMessage = "No VMnas server was found automatically. Make sure this Mac is on the same network, or type the address shown on the server."
    }

    func proxmoxURL() -> URL? {
        guard let base = normalizedBaseURL(), let host = base.host else {
            return nil
        }
        return URL(string: "https://\(host):8006")
    }

    func normalizeServerAddress() {
        guard let normalized = normalizedBaseURL()?.absoluteString else {
            return
        }
        serverBaseURL = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func refreshCompatibility() async {
        guard isConnected else {
            clearAdminData()
            return
        }
        do {
            async let resources: HostResources = get("/host/resources")
            async let compatibility: HostCompatibility = get("/host/compatibility")
            async let gpus: [GpuDevice] = get("/host/gpus")
            async let disks: [HostDisk] = get("/host/disks")
            async let ingestSources: [StorageIngestSource] = get("/storage/ingest-sources")
            async let benchmark: SystemBenchmark = get("/host/benchmark/latest")
            self.resources = try await resources
            self.compatibility = try await compatibility
            self.gpus = try await gpus
            self.disks = try await disks
            self.ingestSources = try await ingestSources
            self.benchmark = try await benchmark
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func runBenchmark() async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before running the server benchmark."
            return
        }
        do {
            let benchmark: SystemBenchmark = try await postEmpty("/host/benchmark/run")
            self.benchmark = benchmark
            await refreshCompatibility()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func performVMAction(vmid: Int, action: String) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before controlling VMs."
            return
        }
        do {
            try await post("/vms/\(vmid)/\(action)")
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func pair(deviceName: String, pin: String) async {
        do {
            if !isServerReachable {
                await findServer()
            }
            let response: PairingResponse = try await postJSON(
                "/pairing/pair",
                body: ["device_name": deviceName, "pin": pin]
            )
            self.deviceToken = response.token
            KeychainStore.saveToken(response.token, serverURL: serverBaseURL)
            self.connectionMessage = "Paired. This Mac can now control the VMnas server."
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
            self.connectionMessage = "Pairing did not work. Check the code shown on the server and try again."
        }
    }

    func rotatePairingPin() async {
        do {
            let response: PairingPinResponse = try await postEmpty("/pairing/rotate")
            self.latestPairingPin = response.pin
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func revokeDevice(id: String) async {
        do {
            try await delete("/pairing/devices/\(id)")
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func installModule(id: String) async {
        guard isModuleStoreAvailable else {
            self.errorMessage = "Pair and connect to a VMnas server before installing server modules."
            return
        }
        do {
            try await post("/store/modules/\(id)/install")
            await refreshStore()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func createVM(_ request: VmCreateRequest) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before creating VMs."
            return
        }
        do {
            let _: VmSummary = try await postJSON("/vms", body: request)
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshIsos() async {
        guard isConnected else {
            self.isos = []
            return
        }
        do {
            let isos: [IsoImage] = try await get("/isos")
            self.isos = isos
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func uploadIso(fileURL: URL) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before uploading installer media."
            return
        }
        do {
            let _: IsoImage = try await uploadFile("/isos/upload", fileURL: fileURL, fieldName: "file")
            await refreshIsos()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func downloadOS(id: String) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before downloading operating systems to the server."
            return
        }
        do {
            let _: OsDownloadResponse = try await postEmpty("/os-store/systems/\(id)/download")
            await refreshOsStore()
            await refreshIsos()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshOsStore() async {
        guard isConnected else {
            self.osStore = []
            self.osDownloads = []
            return
        }
        do {
            async let systems: [OsStoreItem] = get("/os-store/systems")
            async let downloads: [OsStoreItem] = get("/os-store/downloads")
            self.osStore = try await systems
            self.osDownloads = try await downloads
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshRemoteStatus() async {
        guard isConnected else {
            self.remoteStatus = nil
            return
        }
        do {
            let status: RemoteAccessStatus = try await get("/remote/status")
            self.remoteStatus = status
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func setRemoteAccess(enabled: Bool) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before changing remote access."
            return
        }
        do {
            let path = enabled ? "/remote/enable" : "/remote/disable"
            let status: RemoteAccessStatus = try await postEmpty(path)
            self.remoteStatus = status
            await refreshStore()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshUpdateStatus() async {
        guard isConnected else {
            self.updateStatus = nil
            return
        }
        do {
            let status: ServerUpdateStatus = try await get("/system/update/status")
            self.updateStatus = status
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func runServerUpdate() async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before updating server software."
            return
        }
        do {
            let status: ServerUpdateStatus = try await postEmpty("/system/update/run")
            self.updateStatus = status
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func deleteVM(vmid: Int) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before deleting VMs."
            return
        }
        do {
            try await delete("/vms/\(vmid)")
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func accessLinks(vmid: Int) async -> VmAccessLinks? {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before opening VM access."
            return nil
        }
        do {
            let links: VmAccessLinks = try await get("/vms/\(vmid)/access")
            return links
        } catch {
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    func createSnapshot(vmid: Int, name: String) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before creating snapshots."
            return
        }
        do {
            let _: SnapshotSummary = try await postJSON("/vms/\(vmid)/snapshots", body: SnapshotRequest(name: name))
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func attachWindowsTuningTestMedia(vmid: Int, config: WindowsTuningConfig) async {
        guard isConnected else {
            self.errorMessage = "Pair and connect to a VMnas server before testing Windows tuning settings."
            return
        }
        do {
            let response: WindowsTuningApplyResponse = try await postJSON("/vms/\(vmid)/windows-tuning/test-media", body: config)
            self.windowsTuningResult = response
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshStore() async {
        guard isModuleStoreAvailable else {
            self.modules = []
            self.downloads = []
            return
        }
        do {
            async let modules: [StoreModule] = get("/store/modules")
            async let downloads: [StoreModule] = get("/store/downloads")
            self.modules = try await modules
            self.downloads = try await downloads
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func clearAdminData() {
        resources = nil
        compatibility = nil
        disks = []
        ingestSources = []
        benchmark = nil
        nasPreset = nil
        vmPresets = []
        vms = []
        isos = []
        osStore = []
        osDownloads = []
        remoteStatus = nil
        updateStatus = nil
        gpus = []
        modules = []
        downloads = []
        pairedDevices = []
        windowsTuningResult = nil
        isConnected = false
    }

    private func firstReachableServer(in candidates: [String]) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            for candidate in candidates {
                group.addTask { [discoverySession, decoder] in
                    guard let url = URL(string: "/pairing/status", relativeTo: Self.normalizedURL(from: candidate)) else {
                        return nil
                    }
                    do {
                        let (data, response) = try await discoverySession.data(from: url)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            return nil
                        }
                        _ = try decoder.decode(PairingStatus.self, from: data)
                        return Self.normalizedURL(from: candidate)?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private func discoveryCandidates() -> [String] {
        var candidates = [
            serverBaseURL,
            "https://vmnas.local:8765",
            "https://vmnas:8765",
            "https://10.0.0.2:8765",
            "https://10.0.2.15:8765"
        ]
        for prefix in localIPv4Prefixes() {
            candidates.append("https://\(prefix).1:8765")
            for host in 2...254 {
                candidates.append("https://\(prefix).\(host):8765")
            }
        }
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let normalized = Self.normalizedURL(from: candidate)?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
                return nil
            }
            guard !seen.contains(normalized) else {
                return nil
            }
            seen.insert(normalized)
            return normalized
        }
    }

    private func localIPv4Prefixes() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var prefixes: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            guard let address = pointer?.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = Int32(pointer?.pointee.ifa_flags ?? 0)
            guard (flags & IFF_LOOPBACK) == 0 else {
                continue
            }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }
            let ip = String(cString: hostname)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else {
                continue
            }
            let parts = ip.split(separator: ".")
            guard parts.count == 4 else {
                continue
            }
            prefixes.append(parts.prefix(3).joined(separator: "."))
        }
        return Array(Set(prefixes)).sorted()
    }

    private func getOptional<T: Decodable>(_ path: String) async -> T? {
        do {
            return try await get(path)
        } catch {
            return nil
        }
    }

    private func defaultNasPreset(resources: HostResources) -> VmPreset {
        let usableMemory = max(1, Int(resources.memoryTotalGb) - resources.hostReservedGb)
        return VmPreset(
            name: "nas",
            label: "NAS",
            osType: "linux",
            cpuVcpus: max(1, resources.cpuLogical / 4),
            memoryGb: max(1, min(usableMemory, Int(resources.memoryTotalGb) / 4)),
            diskGb: 128,
            gpuPassthrough: false,
            notes: [
                "Safe NAS starting point based on detected server hardware.",
                "Install Plex, Jellyfin, Transmission, file sharing, VPN, and Docker from Apps."
            ]
        )
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        addAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(to: &request)
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
    }

    private func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return try decoder.decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuth(to: &request)
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return try decoder.decode(T.self, from: data)
    }

    private func postJSON<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return try decoder.decode(T.self, from: data)
    }

    private func uploadFile<T: Decodable>(_ path: String, fileURL: URL, fieldName: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: normalizedBaseURL()) else {
            throw URLError(.badURL)
        }
        let boundary = "VMnasBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuth(to: &request)

        var data = Data()
        let filename = fileURL.lastPathComponent
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(contentType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "VMnasAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode)."])
        }
        return try decoder.decode(T.self, from: responseData)
    }

    private func contentType(for fileURL: URL) -> String {
        let name = fileURL.lastPathComponent.lowercased()
        if name.hasSuffix(".img.bz2") {
            return "application/x-bzip2"
        }
        if name.hasSuffix(".img") {
            return "application/octet-stream"
        }
        return "application/x-iso9660-image"
    }

    private func loadTokenIfNeeded() {
        if deviceToken == nil {
            deviceToken = KeychainStore.readToken(serverURL: serverBaseURL)
        }
    }

    private func addAuth(to request: inout URLRequest) {
        loadTokenIfNeeded()
        if let token = deviceToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-VMnas-Token")
        }
    }

    private func normalizedBaseURL() -> URL? {
        Self.normalizedURL(from: serverBaseURL)
    }

    nonisolated private static func normalizedURL(from rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard var components = URLComponents(string: value) else {
            return nil
        }
        if components.port == nil {
            components.port = 8765
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

final class VMnasURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
