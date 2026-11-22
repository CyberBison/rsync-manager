import AppKit
import Darwin
import Foundation

@MainActor
final class FolderSandboxAccessManager {
    private let bookmarksKey = "io.cyberbison.rsync-manager.folderBookmarks"
    private let userDefaults: UserDefaults
    private let bypassPermissionPrompts: Bool
    private var activeDirectoryURLs: [String: URL] = [:]

    init(userDefaults: UserDefaults = .standard, bypassPermissionPrompts: Bool = false) {
        self.userDefaults = userDefaults
        self.bypassPermissionPrompts = bypassPermissionPrompts
    }

    static func realUserHomeDirectoryURL() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func isLocalPath(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.lowercased().hasPrefix("rsync://") {
            return false
        }
        if trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/") {
            return true
        }
        if let colonIndex = trimmed.firstIndex(of: ":") {
            if let slashIndex = trimmed.firstIndex(of: "/") {
                if colonIndex < slashIndex {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }

    func expandRealHomePath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = Self.realUserHomeDirectoryURL().path
        if trimmed == "~" {
            return home
        }
        if trimmed.hasPrefix("~/") {
            let suffix = String(trimmed.dropFirst())
            return home == "/" ? suffix : home + suffix
        }
        return trimmed
    }

    func normalizePath(_ rawPath: String) -> String {
        let expanded = expandRealHomePath(rawPath)
        guard !expanded.isEmpty else { return "" }
        return stripTrailingSlashes(URL(fileURLWithPath: expanded).standardizedFileURL.path)
    }

    func resolvedCommandPath(for rawPath: String) -> String {
        guard Self.isLocalPath(rawPath) else { return rawPath }
        let home = Self.realUserHomeDirectoryURL().path
        if rawPath == "~" {
            return home
        }
        if rawPath.hasPrefix("~/") {
            let suffix = String(rawPath.dropFirst())
            return home == "/" ? suffix : home + suffix
        }
        return rawPath
    }

    func isPath(_ targetPath: String, coveredBy directoryPath: String) -> Bool {
        let target = normalizePath(targetPath)
        let directory = normalizePath(directoryPath)
        guard !target.isEmpty, !directory.isEmpty else { return false }
        if isContained(target, in: directory) {
            return true
        }
        return isContained(
            resolveExistingPrefixSymlinks(target),
            in: resolveExistingPrefixSymlinks(directory)
        )
    }

    func bookmarkDirectory(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        let key = normalizePath(standardizedURL.path)
        guard !key.isEmpty else { return }
        _ = standardizedURL.startAccessingSecurityScopedResource()
        activeDirectoryURLs[key] = standardizedURL
        if let data = try? standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            var stored = loadBookmarks()
            stored[key] = data
            saveBookmarks(stored)
        }
    }

    @discardableResult
    func activateSavedAccess(forPath rawPath: String) -> Bool {
        guard Self.isLocalPath(rawPath) else { return true }
        let normalizedTarget = normalizePath(rawPath)
        guard !normalizedTarget.isEmpty else { return true }

        if activeDirectoryURLs.contains(where: { key, activeURL in
            isPath(normalizedTarget, coveredBy: key) || isPath(normalizedTarget, coveredBy: activeURL.path)
        }) {
            return true
        }

        var stored = loadBookmarks()
        let matchingEntries = stored
            .filter { isPath(normalizedTarget, coveredBy: $0.key) }
            .sorted { $0.key.count > $1.key.count }

        for (key, data) in matchingEntries {
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            guard isPath(normalizedTarget, coveredBy: resolvedURL.path) else {
                continue
            }
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                continue
            }
            let resolvedKey = normalizePath(resolvedURL.path)
            let storeKey = resolvedKey.isEmpty ? key : resolvedKey
            activeDirectoryURLs[storeKey] = resolvedURL
            if isStale, let refreshed = try? resolvedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                if storeKey != key {
                    stored.removeValue(forKey: key)
                }
                stored[storeKey] = refreshed
                saveBookmarks(stored)
            }
            return true
        }

        return false
    }

    func ensureDirectoriesAccess(paths: [String], completion: @escaping @MainActor (Bool) -> Void) {
        if bypassPermissionPrompts {
            completion(true)
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            completion(true)
            return
        }
        #endif

        var seen = Set<String>()
        let localPaths = paths.compactMap { rawPath -> String? in
            guard Self.isLocalPath(rawPath) else { return nil }
            let normalized = normalizePath(rawPath)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }

        let uncovered = localPaths.filter { !activateSavedAccess(forPath: $0) }
        if uncovered.isEmpty {
            completion(true)
            return
        }

        let preferredWindow = NSApp.keyWindow
        promptNextDirectory(
            paths: uncovered,
            index: 0,
            preferredWindow: preferredWindow,
            completion: completion
        )
    }

    private func promptNextDirectory(
        paths: [String],
        index: Int,
        preferredWindow: NSWindow?,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard index < paths.count else {
            completion(true)
            return
        }
        let targetPath = paths[index]
        if activateSavedAccess(forPath: targetPath) {
            promptNextDirectory(
                paths: paths,
                index: index + 1,
                preferredWindow: preferredWindow,
                completion: completion
            )
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Allow Access to Folder"
        panel.message = "Allow Rsync Manager to access \"\(targetPath)\" (or choose a parent folder that contains it)."
        panel.prompt = "Allow Access"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: targetPath, isDirectory: true)

        presentOpenPanel(panel, preferredWindow: preferredWindow) { [weak self] response, selectedURL in
            guard let self else {
                completion(false)
                return
            }
            guard response == .OK, let selectedURL, self.isPath(targetPath, coveredBy: selectedURL.path) else {
                completion(false)
                return
            }
            self.bookmarkDirectory(selectedURL)
            // Yield so AppKit finishes dismissing the current panel before presenting the next one.
            Task { @MainActor in
                self.promptNextDirectory(
                    paths: paths,
                    index: index + 1,
                    preferredWindow: preferredWindow,
                    completion: completion
                )
            }
        }
    }

    private func presentOpenPanel(
        _ panel: NSOpenPanel,
        preferredWindow: NSWindow?,
        completion: @escaping @MainActor (NSApplication.ModalResponse, URL?) -> Void
    ) {
        let hostWindow = (preferredWindow?.isVisible == true ? preferredWindow : nil) ?? NSApp.keyWindow
        if let hostWindow {
            panel.beginSheetModal(for: hostWindow) { response in
                let selectedURL = panel.url
                Task { @MainActor in
                    completion(response, selectedURL)
                }
            }
        } else {
            let response = panel.runModal()
            completion(response, panel.url)
        }
    }

    private func isContained(_ candidate: String, in parent: String) -> Bool {
        if parent == "/" {
            return candidate.hasPrefix("/")
        }
        return candidate == parent || candidate.hasPrefix(parent + "/")
    }

    private func resolveExistingPrefixSymlinks(_ normalizedPath: String) -> String {
        var current = normalizedPath
        var trailingComponents: [String] = []
        let fileManager = FileManager.default

        while current != "/" && !fileManager.fileExists(atPath: current) {
            let resolvedProbe = URL(fileURLWithPath: current).resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedProbe != current {
                break
            }
            let component = (current as NSString).lastPathComponent
            let parent = (current as NSString).deletingLastPathComponent
            if component.isEmpty || parent.isEmpty || parent == current {
                break
            }
            trailingComponents.append(component)
            current = parent
        }

        var resolvedURL = URL(fileURLWithPath: current).resolvingSymlinksInPath().standardizedFileURL
        for component in trailingComponents.reversed() {
            resolvedURL.appendPathComponent(component)
        }
        return stripTrailingSlashes(resolvedURL.standardizedFileURL.path)
    }

    private func stripTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private func loadBookmarks() -> [String: Data] {
        guard let raw = userDefaults.dictionary(forKey: bookmarksKey) else { return [:] }
        var result: [String: Data] = [:]
        for (key, value) in raw {
            if let data = value as? Data {
                result[key] = data
            }
        }
        return result
    }

    private func saveBookmarks(_ bookmarks: [String: Data]) {
        userDefaults.set(bookmarks, forKey: bookmarksKey)
    }
}

extension SyncTaskViewModel {
    func ensureLocalPathsAccess(_ paths: [String], completion: @escaping @MainActor (Bool) -> Void) {
        guard !isRequestingFolderAccess else {
            completion(false)
            return
        }
        isRequestingFolderAccess = true
        folderAccessManager.ensureDirectoriesAccess(paths: paths) { [weak self] granted in
            guard let self else { return }
            self.isRequestingFolderAccess = false
            completion(granted)
        }
    }

    func resolvedLocalPath(_ path: String) -> String {
        folderAccessManager.resolvedCommandPath(for: path)
    }
}
