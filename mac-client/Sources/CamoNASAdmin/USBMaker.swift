import Foundation

struct USBDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let deviceNode: String

    var rawDeviceNode: String {
        deviceNode.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk")
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum USBMaker {
    private static let reportPartitionSizeBytes: Int64 = 536_870_912
    private static let isoLibraryOverheadBytes: Int64 = 1_073_741_824

    static func buildServerISO(projectRoot: String) async throws {
        let root = URL(fileURLWithPath: projectRoot)
        let buildScript = root.appendingPathComponent("server-os/build-iso.sh")
        guard FileManager.default.fileExists(atPath: buildScript.path) else {
            throw NSError(domain: "USBMaker", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not find server-os/build-iso.sh at \(projectRoot)."])
        }
        _ = try await run("/bin/bash", arguments: [buildScript.path], currentDirectory: root, timeout: 0)
        let isoPath = root.appendingPathComponent("dist/camonas-server-trixie-amd64.iso").path
        guard FileManager.default.fileExists(atPath: isoPath) else {
            throw NSError(domain: "USBMaker", code: 11, userInfo: [NSLocalizedDescriptionKey: "The build finished, but dist/camonas-server-trixie-amd64.iso was not created."])
        }
    }

    static func removableDisks() async throws -> [USBDevice] {
        let plist = try await run("/usr/sbin/diskutil", arguments: ["list", "-plist", "external", "physical"])
        guard
            let data = plist.data(using: .utf8),
            let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let disks = root["AllDisksAndPartitions"] as? [[String: Any]]
        else {
            return []
        }

        var devices: [USBDevice] = []
        for disk in disks {
            guard let identifier = disk["DeviceIdentifier"] as? String else { continue }
            let info = try await diskInfo(identifier)
            let removable = info["RemovableMedia"] as? Bool ?? false
            let ejectable = info["Ejectable"] as? Bool ?? false
            guard removable || ejectable else { continue }
            let node = info["DeviceNode"] as? String ?? "/dev/\(identifier)"
            let name = info["MediaName"] as? String ?? info["VolumeName"] as? String ?? identifier
            let size = info["TotalSize"] as? Int64 ?? disk["Size"] as? Int64 ?? 0
            devices.append(USBDevice(id: identifier, name: name, sizeBytes: size, deviceNode: node))
        }
        return devices.sorted {
            if $0.sizeBytes != $1.sizeBytes {
                return $0.sizeBytes < $1.sizeBytes
            }
            return $0.id < $1.id
        }
    }

    static func makeInstaller(isoPath: String, extraIsoPaths: [String], device: USBDevice) async throws {
        let source = URL(fileURLWithPath: isoPath)
        let prepared = try prepareWriteInputs(source: source, extraIsoPaths: extraIsoPaths, device: device)
        defer {
            try? FileManager.default.removeItem(at: prepared.stagingRoot)
        }

        let shell = writeShell(
            source: prepared.stagedSource,
            extras: prepared.stagedExtras,
            manifestNames: prepared.manifestNames,
            device: device,
            needsSudo: false,
            cleanupPath: nil
        )
        let scriptURL = prepared.stagingRoot.appendingPathComponent("write-camonas-installer.command")
        try shell.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let command = "/bin/bash \(shellQuote(scriptURL.path))"
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        do {
            _ = try await run("/usr/bin/osascript", arguments: ["-e", script], timeout: 0)
        } catch {
            throw NSError(
                domain: "USBMaker",
                code: (error as NSError).code,
                userInfo: [NSLocalizedDescriptionKey: usbWriteFailureMessage(fallback: error.localizedDescription)]
            )
        }
    }

    static func createTerminalWriter(isoPath: String, extraIsoPaths: [String], device: USBDevice) async throws -> URL {
        let source = URL(fileURLWithPath: isoPath)
        let extraSources = try validateWriteInputs(source: source, extraIsoPaths: extraIsoPaths, device: device)
        let scriptsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CamoNAS/Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        let scriptURL = scriptsDirectory.appendingPathComponent("write-camonas-installer-\(device.id).command")
        let shell = writeShell(
            source: source,
            extras: extraSources,
            manifestNames: extraSources.map(\.lastPathComponent),
            device: device,
            needsSudo: true,
            cleanupPath: nil
        )
        try shell.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private struct PreparedWriteInputs {
        let stagingRoot: URL
        let stagedSource: URL
        let stagedExtras: [URL]
        let manifestNames: [String]
    }

    private static func prepareWriteInputs(source: URL, extraIsoPaths: [String], device: USBDevice, persistent: Bool = false) throws -> PreparedWriteInputs {
        let extraSources = try validateWriteInputs(source: source, extraIsoPaths: extraIsoPaths, device: device)

        let stagingBase = persistent
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CamoNAS/USBStaging", isDirectory: true)
            : FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: stagingBase, withIntermediateDirectories: true)
        let stagingRoot = stagingBase
            .appendingPathComponent("camonas-usb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let stagedSource = stagingRoot.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: stagedSource)

        let stagedExtras = try extraSources.map { extra in
            let staged = stagingRoot.appendingPathComponent(extra.lastPathComponent)
            try FileManager.default.copyItem(at: extra, to: staged)
            return staged
        }
        return PreparedWriteInputs(
            stagingRoot: stagingRoot,
            stagedSource: stagedSource,
            stagedExtras: stagedExtras,
            manifestNames: extraSources.map(\.lastPathComponent)
        )
    }

    private static func validateWriteInputs(source: URL, extraIsoPaths: [String], device: USBDevice) throws -> [URL] {
        guard source.pathExtension.lowercased() == "iso" else {
            throw NSError(domain: "USBMaker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a .iso file."])
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "USBMaker", code: 2, userInfo: [NSLocalizedDescriptionKey: "The selected ISO file does not exist."])
        }
        let extraSources = extraIsoPaths.map { URL(fileURLWithPath: $0) }
        for extra in extraSources {
            guard isSupportedInstallMedia(extra) else {
                throw NSError(domain: "USBMaker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Extra installer files must be .iso, .img, or .img.bz2 files."])
            }
            guard FileManager.default.fileExists(atPath: extra.path) else {
                throw NSError(domain: "USBMaker", code: 4, userInfo: [NSLocalizedDescriptionKey: "\(extra.lastPathComponent) does not exist."])
            }
        }
        try validateSpace(serverIso: source, extraIsos: extraSources, device: device)
        return extraSources
    }

    private static func writeShell(source stagedSource: URL, extras stagedExtras: [URL], manifestNames: [String], device: USBDevice, needsSudo: Bool, cleanupPath: String?) -> String {
        let sudo = needsSudo ? "sudo " : ""
        let copyExtra = stagedExtras.map {
            """
            echo "Copying \($0.lastPathComponent)"
            cp \(shellQuote($0.path)) "$DEST/isos/"
            """
        }.joined(separator: "\n")
        let manifest = manifestNames.joined(separator: "\\n")
        let reportScript = """
        echo "Creating CAMONAS_LOGS report partition"
        \(sudo)/usr/sbin/diskutil unmountDisk force \(shellQuote(device.deviceNode)) || true
        \(sudo)/usr/sbin/diskutil addPartition \(shellQuote(device.deviceNode)) ExFAT CAMONAS_LOGS 512m
        \(sudo)/usr/sbin/diskutil mountDisk \(shellQuote(device.deviceNode)) || true
        REPORT_DEST="$(/usr/sbin/diskutil info -plist CAMONAS_LOGS | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null || true)"
        if [ -z "$REPORT_DEST" ]; then
          REPORT_DEST="/Volumes/CAMONAS_LOGS"
        fi
        if [ ! -d "$REPORT_DEST" ]; then
          echo "CAMONAS_LOGS report partition was not mounted." >&2
          exit 1
        fi
        mkdir -p "$REPORT_DEST/reports"
        cat > "$REPORT_DEST/README.txt" <<'EOF'
        Camo NAS install reports

        If a server install fails, booted Camo NAS installer logs will be saved in the reports folder on this partition.
        Plug this USB drive back into your Mac and share the newest report folder so the issue can be diagnosed.
        EOF
        echo "CAMONAS_LOGS is ready at $REPORT_DEST"
        """
        let extraScript = stagedExtras.isEmpty ? "" : """
        echo "Creating CAMONAS_ISOS data partition for guest media"
        \(sudo)/usr/sbin/diskutil unmountDisk force \(shellQuote(device.deviceNode)) || true
        \(sudo)/usr/sbin/diskutil addPartition \(shellQuote(device.deviceNode)) ExFAT CAMONAS_ISOS 0b
        \(sudo)/usr/sbin/diskutil mountDisk \(shellQuote(device.deviceNode)) || true
        DEST="$(/usr/sbin/diskutil info -plist CAMONAS_ISOS | /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null || true)"
        if [ -z "$DEST" ]; then
          DEST="/Volumes/CAMONAS_ISOS"
        fi
        if [ ! -d "$DEST" ]; then
          echo "CAMONAS_ISOS data partition was not mounted." >&2
          exit 1
        fi
        echo "Copying guest media to $DEST/isos"
        mkdir -p "$DEST/isos"
        \(copyExtra)
        cat > "$DEST/camonas-iso-library.txt" <<'EOF'
        \(manifest)
        EOF
        echo "Guest media copy completed"
        """
        let sudoPrimeScript = needsSudo ? """
        echo "Requesting administrator access for disk writing"
        sudo -v
        """ : ""
        let cleanupScript = cleanupPath.map {
            """
            echo "Cleaning staging files"
            rm -rf \(shellQuote($0))
            """
        } ?? ""

        return """
        #!/bin/bash
        set -eu
        LOG_DIR="$HOME/Library/Logs/CamoNAS"
        LOG_FILE="$LOG_DIR/usb-maker.log"
        mkdir -p "$LOG_DIR"
        if [ -e "$LOG_FILE" ] && [ ! -w "$LOG_FILE" ]; then
          LOG_FILE="$LOG_DIR/usb-maker-terminal.log"
        fi
        touch "$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
        echo "---- Camo NAS USB write started $(date) ----"
        echo "Target: \(device.deviceNode)"
        echo "Source: \(stagedSource.path)"
        echo "This will erase \(device.deviceNode). Press Control-C now to cancel."
        sleep 5
        \(sudoPrimeScript)
        if [ ! -e \(shellQuote(stagedSource.path)) ]; then
          echo "Selected ISO does not exist." >&2
          exit 2
        fi
        if [ ! -e \(shellQuote(device.deviceNode)) ]; then
          echo "Selected USB device is no longer connected: \(device.deviceNode)" >&2
          exit 3
        fi
        run_dd_with_progress() {
          local output_device="$1"
          \(sudo)/bin/dd if=\(shellQuote(stagedSource.path)) of="$output_device" bs=4m &
          local dd_pid=$!
          (
            while kill -0 "$dd_pid" 2>/dev/null; do
              sleep 10
              kill -INFO "$dd_pid" 2>/dev/null || true
            done
          ) &
          local info_pid=$!
          wait "$dd_pid"
          local dd_status=$?
          kill "$info_pid" 2>/dev/null || true
          wait "$info_pid" 2>/dev/null || true
          return "$dd_status"
        }
        \(sudo)/usr/sbin/diskutil unmountDisk force \(shellQuote(device.deviceNode))
        if ! run_dd_with_progress \(shellQuote(device.rawDeviceNode)); then
          echo "Raw device write failed; retrying slower buffered device path \(device.deviceNode)"
          \(sudo)/usr/sbin/diskutil unmountDisk force \(shellQuote(device.deviceNode)) || true
          run_dd_with_progress \(shellQuote(device.deviceNode))
        fi
        /bin/sync
        \(reportScript)
        \(extraScript)
        \(sudo)/usr/sbin/diskutil eject \(shellQuote(device.deviceNode))
        \(cleanupScript)
        echo "---- Camo NAS USB write completed $(date) ----"
        echo "Done. You can close this Terminal window."
        """
    }

    private static func validateSpace(serverIso: URL, extraIsos: [URL], device: USBDevice) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        let serverSize = try serverIso.resourceValues(forKeys: keys).fileSize ?? 0
        let extrasSize = try extraIsos.reduce(0) { total, url in
            total + (try url.resourceValues(forKeys: keys).fileSize ?? 0)
        }
        let extraOverhead = extraIsos.isEmpty ? Int64(0) : isoLibraryOverheadBytes
        let required = Int64(serverSize + extrasSize) + reportPartitionSizeBytes + extraOverhead
        guard required < device.sizeBytes else {
            throw NSError(domain: "USBMaker", code: 5, userInfo: [NSLocalizedDescriptionKey: "The USB drive is too small for the Camo NAS installer plus selected ISO library."])
        }
    }

    private static func diskInfo(_ identifier: String) async throws -> [String: Any] {
        let plist = try await run("/usr/sbin/diskutil", arguments: ["info", "-plist", identifier])
        guard
            let data = plist.data(using: .utf8),
            let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return [:]
        }
        return root
    }

    private static func run(_ launchPath: String, arguments: [String], currentDirectory: URL? = nil, timeout: TimeInterval = 30) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardOutput = output
            process.standardError = error
            try process.run()

            if timeout > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }

            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                let stdout = String(data: data, encoding: .utf8) ?? ""
                let message = [stderr, stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? "Command failed."
                throw NSError(domain: "USBMaker", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
            }
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func isSupportedInstallMedia(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".iso") || name.hasSuffix(".img") || name.hasSuffix(".img.bz2")
    }

    private static func usbWriteFailureMessage(fallback: String) -> String {
        let logURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CamoNAS/usb-maker.log")
        guard let log = try? String(contentsOf: logURL, encoding: .utf8) else {
            return fallback
        }
        let tail = log
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(24)
            .joined(separator: "\n")
        if tail.contains("Operation not permitted") {
            return """
            macOS blocked writing to the USB device. Give Camo NAS Admin Full Disk Access in System Settings > Privacy & Security > Full Disk Access, relaunch the app, then try again.

            Latest writer log:
            \(tail)
            """
        }
        return """
        \(fallback)

        Latest writer log:
        \(tail)
        """
    }
}
