import AppKit
import Darwin
import Foundation

private let pluginName = "Side Feather.plugin"
private let pluginIdentifier = "com.mathewharwich.EdgeFeather"

private struct InstallerFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct Outcome {
    let message: String
    let destination: String
    let backup: String?
}

private final class Installer {
    private let files = FileManager.default
    let home: URL
    let source: URL
    let mediaCore: URL
    let storage: URL
    var destination: URL { mediaCore.appendingPathComponent(pluginName, isDirectory: true) }
    var legacy: URL { mediaCore.appendingPathComponent("Edge Feather.plugin", isDirectory: true) }

    init(home: URL, source: URL) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
        self.source = source.standardizedFileURL
        mediaCore = self.home.appendingPathComponent("Library/Application Support/Adobe/Common/Plug-ins/7.0/MediaCore", isDirectory: true)
        storage = self.home.appendingPathComponent("Library/Application Support/Side Feather", isDirectory: true)
    }

    private func kind(_ url: URL) throws -> FileAttributeType? {
        do {
            return try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    private func directory(_ url: URL) throws {
        guard try kind(url) == .typeDirectory else {
            throw InstallerFailure(message: "A required folder is missing, is a symbolic link, or is not a folder:\n\(url.path)\nNo existing item was replaced.")
        }
    }

    // Walk each component rather than following a surprising symlink through a
    // pre-existing Adobe, MediaCore, staging or backup path.
    private func folders(_ url: URL, create: Bool) throws {
        guard url.path.hasPrefix(home.path + "/") else {
            throw InstallerFailure(message: "The installation path is outside the selected user folder.")
        }
        try directory(home)
        let relative = url.pathComponents.dropFirst(home.pathComponents.count)
        var current = home
        var parentMissing = false
        for component in relative {
            current.appendPathComponent(component, isDirectory: true)
            if parentMissing { continue }
            if let type = try kind(current) {
                guard type == .typeDirectory else {
                    throw InstallerFailure(message: "An installation folder is a symbolic link or another file type:\n\(current.path)\nIt was left untouched.")
                }
            } else if create {
                try files.createDirectory(at: current, withIntermediateDirectories: false)
            } else {
                parentMissing = true
            }
        }
    }

    private func identifier(_ url: URL) throws -> String? {
        guard try kind(url) == .typeDirectory else { return nil }
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        guard try kind(contents) == .typeDirectory else { return nil }
        let info = contents.appendingPathComponent("Info.plist")
        guard try kind(info) == .typeRegular else { return nil }
        let data = try Data(contentsOf: info)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    private func validatePayload(_ url: URL) throws {
        try directory(url)
        guard try identifier(url) == pluginIdentifier else {
            throw InstallerFailure(message: "The bundled Side Feather effect could not be verified. Download a fresh installer.")
        }
        var enumerationError: Error?
        guard let entries = files.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else {
            throw InstallerFailure(message: "The bundled effect could not be read.")
        }
        for case let entry as URL in entries {
            guard let type = try kind(entry), type == .typeDirectory || type == .typeRegular else {
                throw InstallerFailure(message: "The bundled effect contains a symbolic link or unsupported file. Nothing was installed.")
            }
        }
        if let error = enumerationError { throw error }
        let executable = url.appendingPathComponent("Contents/MacOS/Edge Feather")
        // The stable executable name is retained by the native plug-in bundle.
        let info = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
        let executableName = plist?["CFBundleExecutable"] as? String
        if let name = executableName {
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
                throw InstallerFailure(message: "The bundled effect executable name is invalid.")
            }
        }
        let namedExecutable = executableName.map {
            url.appendingPathComponent("Contents/MacOS").appendingPathComponent($0)
        } ?? executable
        guard try kind(namedExecutable) == .typeRegular else {
            throw InstallerFailure(message: "The bundled effect executable is missing. Nothing was installed.")
        }
    }

    private func uniqueFolder(in parent: URL) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return parent.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
    }

    // Exclusive, same-volume rename: never fall back to copying a partially
    // published bundle across a mounted volume or overwrite a concurrent item.
    private func move(_ source: URL, to destination: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                renamex_np(from!, to!, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code, userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    private func restore(_ moves: [(original: URL, backup: URL)]) -> [String] {
        var failures: [String] = []
        for move in moves.reversed() {
            do {
                guard try kind(move.original) == nil else {
                    throw InstallerFailure(message: "The original path is occupied.")
                }
                try self.move(move.backup, to: move.original)
            } catch {
                failures.append("\(move.backup.path): \(error.localizedDescription)")
            }
        }
        return failures
    }

    private func failure(_ error: Error, moves: [(original: URL, backup: URL)]) -> InstallerFailure {
        let failures = restore(moves)
        let recovery = failures.isEmpty ? "Any previous installation was restored." :
            "Some originals remain safely in their backup folders:\n" + failures.joined(separator: "\n")
        return InstallerFailure(message: "\(error.localizedDescription)\n\n\(recovery)")
    }

    func install(dryRun: Bool = false) throws -> Outcome {
        try validatePayload(source)
        try folders(mediaCore, create: false)
        try folders(storage, create: false)
        let existing = try kind(destination)
        guard existing == nil || existing == .typeDirectory else {
            throw InstallerFailure(message: "The destination contains a symbolic link or another file type. It was left untouched:\n\(destination.path)")
        }
        let knownLegacy = try identifier(legacy) == pluginIdentifier
        if dryRun {
            return Outcome(message: "Dry run: the payload and destination passed checks. No files changed.", destination: destination.path, backup: nil)
        }
        try folders(mediaCore, create: true)
        try folders(storage, create: true)
        let stagingParent = storage.appendingPathComponent("Staging", isDirectory: true)
        let backupsParent = storage.appendingPathComponent("Backups", isDirectory: true)
        try folders(stagingParent, create: true)
        try folders(backupsParent, create: true)
        let transaction = uniqueFolder(in: stagingParent)
        try files.createDirectory(at: transaction, withIntermediateDirectories: false)
        let staged = transaction.appendingPathComponent(pluginName, isDirectory: true)
        defer { try? files.removeItem(at: transaction) }
        try files.copyItem(at: source, to: staged)
        try validatePayload(staged)

        let backup = uniqueFolder(in: backupsParent)
        var moves: [(original: URL, backup: URL)] = []
        if existing != nil || knownLegacy {
            try files.createDirectory(at: backup, withIntermediateDirectories: false)
        }
        do {
            if existing != nil {
                let saved = backup.appendingPathComponent(pluginName, isDirectory: true)
                try move(destination, to: saved)
                moves.append((destination, saved))
            }
            if knownLegacy {
                let saved = backup.appendingPathComponent("Edge Feather.plugin", isDirectory: true)
                try move(legacy, to: saved)
                moves.append((legacy, saved))
            }
            // Both staging and destination live in this user's Library. Rename
            // publishes the complete bundle; no partially copied effect is scanned.
            try move(staged, to: destination)
        } catch {
            throw failure(error, moves: moves)
        }
        return Outcome(message: "Side Feather is installed. Restart Premiere Pro, then search Effects for Side Feather.\n\nPrevious versions, when present, were saved outside Adobe's plug-in folder.", destination: destination.path,
                       backup: moves.isEmpty ? nil : backup.path)
    }

    func remove(dryRun: Bool = false) throws -> Outcome {
        try folders(mediaCore, create: false)
        try folders(storage, create: false)
        var candidates: [URL] = []
        if try kind(destination) != nil {
            guard try identifier(destination) == pluginIdentifier else {
                throw InstallerFailure(message: "The item named Side Feather.plugin is not a recognized Side Feather installation. It was left untouched.")
            }
            candidates.append(destination)
        }
        if try identifier(legacy) == pluginIdentifier { candidates.append(legacy) }
        guard !candidates.isEmpty else {
            return Outcome(message: "No Side Feather installation was found in this user's plug-in folder.", destination: destination.path, backup: nil)
        }
        if dryRun {
            return Outcome(message: "Dry run: recognized installed effects would be moved to a backup. No files changed.", destination: destination.path, backup: nil)
        }
        let backups = storage.appendingPathComponent("Backups", isDirectory: true)
        try folders(backups, create: true)
        let backup = uniqueFolder(in: backups)
        try files.createDirectory(at: backup, withIntermediateDirectories: false)
        var moves: [(original: URL, backup: URL)] = []
        do {
            for candidate in candidates {
                let saved = backup.appendingPathComponent(candidate.lastPathComponent, isDirectory: true)
                try move(candidate, to: saved)
                moves.append((candidate, saved))
            }
        } catch {
            throw failure(error, moves: moves)
        }
        return Outcome(message: "Side Feather was removed from this user's plug-in folder and saved in a backup. Restart Premiere Pro to finish.", destination: destination.path, backup: backup.path)
    }
}

private final class InstallerDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private var installButton: NSButton!
    private var removeButton: NSButton!
    private var closeButton: NSButton!
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 500),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Install Side Feather"
        window.delegate = self
        window.center()
        let title = NSTextField(labelWithString: "Side Feather")
        title.font = .systemFont(ofSize: 27, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "Independent edge feathering for Adobe Premiere Pro.\nA CPU effect with optional links between sides.")
        description.font = .systemFont(ofSize: 14)
        let location = NSTextField(wrappingLabelWithString: "Installs for your user account. No administrator password is needed.\nRestart Premiere Pro after installing or removing the effect.")
        location.font = .systemFont(ofSize: 13)
        location.textColor = .secondaryLabelColor
        status = NSTextField(wrappingLabelWithString: "Ready to install.")
        status.font = .systemFont(ofSize: 13)
        status.isSelectable = true
        status.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        installButton = NSButton(title: "Install", target: self, action: #selector(install))
        removeButton = NSButton(title: "Remove…", target: self, action: #selector(remove))
        closeButton = NSButton(title: "Close", target: self, action: #selector(close))
        for button in [installButton!, removeButton!, closeButton!] { button.bezelStyle = .rounded }
        installButton.keyEquivalent = "\r"
        closeButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [removeButton, NSView(), closeButton, installButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let stack = NSStackView(views: [title, description, location, status, NSView(), buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            location.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func engine() throws -> Installer {
        guard let resources = Bundle.main.resourceURL else {
            throw InstallerFailure(message: "Installer resources are missing. Download a fresh installer.")
        }
        return Installer(home: FileManager.default.homeDirectoryForCurrentUser,
                         source: resources.appendingPathComponent(pluginName, isDirectory: true))
    }

    private func run(_ action: String) {
        busy = true
        [installButton, removeButton, closeButton].forEach { $0?.isEnabled = false }
        status.stringValue = action == "install" ? "Installing…" : "Removing…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> Outcome in
                let installer = try self.engine()
                return try action == "install" ? installer.install() : installer.remove()
            }
            DispatchQueue.main.async {
                self.busy = false
                [self.installButton, self.removeButton, self.closeButton].forEach { $0?.isEnabled = true }
                switch result {
                case .success(let outcome):
                    self.status.stringValue = outcome.message + (outcome.backup.map { "\n\nBackup: " + $0 } ?? "")
                case .failure(let error):
                    self.status.stringValue = "The operation did not complete."
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Side Feather could not finish"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    alert.beginSheetModal(for: self.window)
                }
            }
        }
    }

    @objc private func install() { run("install") }
    @objc private func remove() {
        let alert = NSAlert()
        alert.messageText = "Remove Side Feather?"
        alert.informativeText = "The installed effect will be moved to a backup outside Adobe's plug-in folder. Premiere Pro will keep running. Restart it afterward."
        alert.addButton(withTitle: "Back Up and Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { self.run("remove") }
        }
    }
    @objc private func close() { NSApp.terminate(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        busy ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Explicit test roots simulate a home directory in temporary storage. This path
// never changes HOME and cannot point at the real user's home/install location.
private func testCLI(_ arguments: [String]) -> Int32 {
    do {
        var options: [String: String] = [:]
        var dryRun = false
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--dry-run" { dryRun = true; index += 1; continue }
            guard ["--test-root", "--test-plugin", "--test-action"].contains(key), index + 1 < arguments.count,
                  options[key] == nil else {
                throw InstallerFailure(message: "Use --test-root ABSOLUTE_TEMP_FOLDER --test-plugin ABSOLUTE_PLUGIN --test-action install|remove [--dry-run].")
            }
            options[key] = arguments[index + 1]
            index += 2
        }
        guard let rootPath = options["--test-root"], rootPath.hasPrefix("/"),
              let payloadPath = options["--test-plugin"], payloadPath.hasPrefix("/"),
              let action = options["--test-action"], ["install", "remove"].contains(action) else {
            throw InstallerFailure(message: "An explicit absolute temporary test root, payload and action are required.")
        }
        let givenRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let attributes = try FileManager.default.attributesOfItem(atPath: givenRoot.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw InstallerFailure(message: "The test root must be an existing directory, not a symbolic link.")
        }
        let root = givenRoot.resolvingSymlinksInPath()
        let tempRoots = [FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/tmp", isDirectory: true)]
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        guard tempRoots.contains(where: { root.path.hasPrefix($0.path + "/") }),
              root.path != FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path else {
            throw InstallerFailure(message: "Test roots must be strictly inside system temporary storage.")
        }
        let installer = Installer(home: root, source: URL(fileURLWithPath: payloadPath, isDirectory: true))
        let outcome = try action == "install" ? installer.install(dryRun: dryRun) : installer.remove(dryRun: dryRun)
        let object: [String: Any] = ["ok": true, "action": action, "dry_run": dryRun,
                                   "message": outcome.message, "destination": outcome.destination,
                                   "backup": outcome.backup.map { $0 as Any } ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        return 0
    } catch {
        let data = try? JSONSerialization.data(withJSONObject: ["ok": false, "error": error.localizedDescription], options: [.sortedKeys])
        if let data { FileHandle.standardError.write(data); FileHandle.standardError.write(Data([10])) }
        return 1
    }
}

if CommandLine.arguments.count > 1 {
    exit(testCLI(Array(CommandLine.arguments.dropFirst())))
}
let application = NSApplication.shared
private let applicationDelegate = InstallerDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()
