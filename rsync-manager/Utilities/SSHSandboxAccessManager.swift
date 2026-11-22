import AppKit
import Darwin
import Foundation

@MainActor
final class SSHSandboxAccessManager {
    private let sshDirBookmarkKey = "io.cyberbison.rsync-manager.sshDirBookmark"
    private let fileBookmarksKey = "io.cyberbison.rsync-manager.sshFileBookmarks"
    private var activeSSHDirectoryURL: URL?
    private var activeFileURLs: [String: URL] = [:]

    static func realUserHomeDirectoryURL() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func realUserName() -> String {
        if let pw = getpwuid(getuid()), let name = pw.pointee.pw_name {
            return String(cString: name)
        }
        return NSUserName()
    }

    var realSSHDirectoryURL: URL {
        Self.realUserHomeDirectoryURL().appendingPathComponent(".ssh", isDirectory: true)
    }

    var realSSHDirectoryExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: realSSHDirectoryURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    func expandRealHomePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = Self.realUserHomeDirectoryURL().path
        if trimmed == "~" {
            return home
        }
        if trimmed.hasPrefix("~/") {
            return home + String(trimmed.dropFirst())
        }
        return trimmed
    }

    /// Resolves and activates any previously saved security-scoped bookmark for ~/.ssh without showing UI.
    @discardableResult
    func activateSavedSSHDirectoryAccess() -> Bool {
        if activeSSHDirectoryURL != nil {
            return true
        }
        guard let data = UserDefaults.standard.data(forKey: sshDirBookmarkKey) else {
            return false
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return false
        }
        guard isCoveredBySSHDirectory(url), url.startAccessingSecurityScopedResource() else {
            return false
        }
        activeSSHDirectoryURL = url
        if isStale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: sshDirBookmarkKey)
        }
        return true
    }

    /// Ensures ~/.ssh access and any matching external key/certificate files referenced in ~/.ssh/config
    /// are authorized before saving an SSH Agent profile. Calls `completion(false)` if access is denied or cancelled.
    func ensureSSHAgentAccess(host: String, user: String, port: Int?, completion: @escaping @MainActor (Bool) -> Void) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            completion(true)
            return
        }
        #endif

        let preferredWindow = NSApp.keyWindow
        let proceedToExternalCredentials = { [weak self] in
            guard let self, self.activeSSHDirectoryURL != nil else {
                completion(false)
                return
            }
            let missingURLs = self.externalConfigCredentialURLs(host: host, user: user, port: port).filter {
                !self.isFileAccessibleInSandbox($0)
            }
            self.promptNextExternalCredential(
                urls: missingURLs,
                index: 0,
                preferredWindow: preferredWindow,
                messageBuilder: { url in
                    "Your ~/.ssh/config references \"\(url.path)\" for this host and user. Choose this file to grant Rsync Manager read access."
                },
                completion: completion
            )
        }

        if activateSavedSSHDirectoryAccess() {
            proceedToExternalCredentials()
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Allow Access to ~/.ssh"
        panel.message = "Allow Rsync Manager to access your ~/.ssh folder so SSH Agent connections can read ~/.ssh/config, your keys inside ~/.ssh, and update known_hosts."
        panel.prompt = "Allow Access"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = realSSHDirectoryExists ? realSSHDirectoryURL : Self.realUserHomeDirectoryURL()

        presentOpenPanel(panel, preferredWindow: preferredWindow) { [weak self] response, url in
            guard let self else {
                completion(false)
                return
            }
            guard response == .OK, let url, self.isCoveredBySSHDirectory(url) else {
                completion(false)
                return
            }
            self.saveSSHDirectoryAccess(url)
            guard self.activeSSHDirectoryURL != nil else {
                completion(false)
                return
            }
            // Yield so AppKit finishes dismissing the directory panel before presenting any follow-up key panel.
            Task { @MainActor in
                proceedToExternalCredentials()
            }
        }
    }

    /// Ensures explicit key/certificate file paths (for Public Key or Certificate auth) have sandbox read access,
    /// prompting only for paths not already bookmarked or covered by an active `~/.ssh` folder bookmark.
    func ensureExplicitCredentialFilesAccess(paths: [String], completion: @escaping @MainActor (Bool) -> Void) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            completion(true)
            return
        }
        #endif

        _ = activateSavedSSHDirectoryAccess()

        var seen = Set<String>()
        let missingURLs = paths
            .map { standardizedExpandedPath($0) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { !isFileAccessibleInSandbox($0) }

        promptNextExternalCredential(
            urls: missingURLs,
            index: 0,
            preferredWindow: NSApp.keyWindow,
            messageBuilder: { url in
                "Choose \"\(url.path)\" to grant Rsync Manager read access to this SSH credential file."
            },
            completion: completion
        )
    }

    private func isFileAccessibleInSandbox(_ url: URL) -> Bool {
        isCoveredByActiveSSHDirectoryAccess(url) || hasBookmark(forFileAt: url.path)
    }

    private func promptNextExternalCredential(
        urls: [URL],
        index: Int,
        preferredWindow: NSWindow?,
        messageBuilder: @escaping @MainActor (URL) -> String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard index < urls.count else {
            completion(true)
            return
        }
        let targetURL = urls[index]
        let panel = NSOpenPanel()
        panel.title = "Allow Access to SSH Key"
        panel.message = messageBuilder(targetURL)
        panel.prompt = "Allow Access"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = targetURL.deletingLastPathComponent()

        presentOpenPanel(panel, preferredWindow: preferredWindow) { [weak self] response, selectedURL in
            guard let self else {
                completion(false)
                return
            }
            guard response == .OK, let selectedURL, self.urlsReferToSameFile(selectedURL, targetURL) else {
                completion(false)
                return
            }
            self.bookmarkFile(selectedURL, aliasPath: targetURL.standardizedFileURL.path)
            guard self.hasBookmark(forFileAt: targetURL.path) else {
                completion(false)
                return
            }
            Task { @MainActor in
                self.promptNextExternalCredential(
                    urls: urls,
                    index: index + 1,
                    preferredWindow: preferredWindow,
                    messageBuilder: messageBuilder,
                    completion: completion
                )
            }
        }
    }

    private func urlsReferToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
            || lhs.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path
    }

    private func presentOpenPanel(
        _ panel: NSOpenPanel,
        preferredWindow: NSWindow?,
        completion: @escaping @MainActor (NSApplication.ModalResponse, URL?) -> Void
    ) {
        let hostWindow = (preferredWindow?.isVisible == true ? preferredWindow : nil) ?? NSApp.keyWindow
        if let hostWindow {
            panel.beginSheetModal(for: hostWindow) { response in
                Task { @MainActor in
                    completion(response, panel.url)
                }
            }
        } else {
            let response = panel.runModal()
            completion(response, panel.url)
        }
    }

    /// Returns true if `url` equals `~/.ssh` or is an ancestor directory covering `~/.ssh`.
    private func isCoveredBySSHDirectory(_ url: URL) -> Bool {
        isURL(realSSHDirectoryURL, inside: url)
    }

    /// Returns true if `url` falls inside the currently active bookmarked SSH directory.
    private func isCoveredByActiveSSHDirectoryAccess(_ url: URL) -> Bool {
        guard let activeSSHDirectoryURL else {
            return false
        }
        return isURL(url, inside: activeSSHDirectoryURL)
    }

    private func isURL(_ url: URL, inside directoryURL: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let directory = directoryURL.standardizedFileURL.path
        if directory == "/" {
            return candidate.hasPrefix("/")
        }
        return candidate == directory || candidate.hasPrefix(directory + "/")
    }

    private func saveSSHDirectoryAccess(_ url: URL) {
        guard isCoveredBySSHDirectory(url) else { return }
        _ = url.startAccessingSecurityScopedResource()
        activeSSHDirectoryURL = url
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: sshDirBookmarkKey)
        }
    }

    func bookmarkFile(_ url: URL, aliasPath: String? = nil) {
        _ = url.startAccessingSecurityScopedResource()
        let path = url.standardizedFileURL.path
        activeFileURLs[path] = url
        if let aliasPath, !aliasPath.isEmpty {
            activeFileURLs[aliasPath] = url
        }
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var dict = (UserDefaults.standard.dictionary(forKey: fileBookmarksKey) as? [String: Data]) ?? [:]
            dict[path] = data
            if let aliasPath, !aliasPath.isEmpty {
                dict[aliasPath] = data
            }
            UserDefaults.standard.set(dict, forKey: fileBookmarksKey)
        }
    }

    func hasBookmark(forFileAt rawPath: String) -> Bool {
        let path = standardizedExpandedPath(rawPath)
        guard !path.isEmpty else { return false }
        activateBookmarkedFile(at: path)
        return activeFileURLs[path] != nil
    }

    func activateBookmarkedFile(at rawPath: String) {
        let expanded = expandRealHomePath(rawPath)
        guard !expanded.isEmpty else { return }
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if activeFileURLs[standardized] != nil { return }
        guard let dict = UserDefaults.standard.dictionary(forKey: fileBookmarksKey) as? [String: Data],
              let data = dict[standardized] ?? dict[expanded] else {
            return
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }
        if url.startAccessingSecurityScopedResource() {
            activeFileURLs[standardized] = url
            if isStale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                var updated = dict
                updated[standardized] = refreshed
                UserDefaults.standard.set(updated, forKey: fileBookmarksKey)
            }
        }
    }

    func activateBookmarkedConfigCredentials(host: String, user: String, port: Int?) {
        for url in externalConfigCredentialURLs(host: host, user: user, port: port) {
            activateBookmarkedFile(at: url.path)
        }
    }

    /// Reads `~/.ssh/config` and returns `IdentityFile`/`CertificateFile` URLs matching `host + user`
    /// that live outside `~/.ssh/` (so they are not already covered by the `~/.ssh` directory bookmark).
    func externalConfigCredentialURLs(host: String, user: String, port: Int?) -> [URL] {
        let configURL = realSSHDirectoryURL.appendingPathComponent("config")
        guard let configText = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }
        return matchingConfigCredentialPaths(inConfigText: configText, host: host, user: user, port: port)
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { !isURL($0, inside: realSSHDirectoryURL) && !isCoveredByActiveSSHDirectoryAccess($0) }
    }

    /// Returns expanded `IdentityFile` and `CertificateFile` paths from `~/.ssh/config` blocks
    /// that match the given `host + user` combination (falling back to `defaultUser` when `user` is empty).
    func matchingConfigCredentialPaths(
        inConfigText configText: String,
        host: String,
        user: String,
        port: Int?,
        defaultUser: String? = nil
    ) -> [String] {
        let normalizedHost = stripIPv6Brackets(host.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedHost.isEmpty else { return [] }

        let trimmedDefaultUser = (defaultUser ?? Self.realUserName()).trimmingCharacters(in: .whitespacesAndNewlines)
        let localUser = trimmedDefaultUser.isEmpty ? Self.realUserName() : trimmedDefaultUser
        let blocks = parseSSHConfigBlocks(from: configText)
        let effectiveUser = resolveEffectiveUser(
            explicitUser: user,
            defaultUser: localUser,
            blocks: blocks,
            host: normalizedHost
        )

        let matchedBlocks = blocks.filter {
            blockMatchesHost($0, host: normalizedHost, localUser: localUser)
                && blockMatchesUser($0, effectiveUser: effectiveUser, localUser: localUser)
        }
        let resolvedHostName = matchedBlocks.compactMap(\.hostName).first

        var seen = Set<String>()
        var results: [String] = []
        for block in matchedBlocks {
            let blockTargetHost = block.hostName ?? resolvedHostName ?? normalizedHost
            for rawPath in block.identityFiles + block.certificateFiles {
                let expanded = expandCredentialPath(
                    rawPath,
                    targetHost: blockTargetHost,
                    queryHost: normalizedHost,
                    remoteUser: effectiveUser,
                    localUser: localUser,
                    port: port
                )
                guard !expanded.isEmpty, seen.insert(expanded).inserted else { continue }
                results.append(expanded)
            }
        }
        return results
    }

    private func standardizedExpandedPath(_ rawPath: String) -> String {
        let expanded = expandRealHomePath(rawPath)
        guard !expanded.isEmpty else { return "" }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func stripIPv6Brackets(_ value: String) -> String {
        if value.hasPrefix("[") && value.hasSuffix("]") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    // MARK: - ~/.ssh/config Parsing & Matching

    private struct MatchCriterion {
        let negated: Bool
        let patterns: [String]
    }

    private struct SSHConfigBlock {
        enum Kind {
            case topLevel
            case host([String])
            case match(
                hostCriteria: [MatchCriterion],
                userCriteria: [MatchCriterion],
                localUserCriteria: [MatchCriterion],
                isAll: Bool
            )
        }

        let kind: Kind
        var hostName: String?
        var user: String?
        var identityFiles: [String] = []
        var certificateFiles: [String] = []
    }

    private func parseSSHConfigBlocks(from configText: String) -> [SSHConfigBlock] {
        var blocks: [SSHConfigBlock] = []
        var current = SSHConfigBlock(kind: .topLevel)

        for rawLine in configText.components(separatedBy: .newlines) {
            guard let (key, value) = parseDirective(rawLine) else { continue }
            switch key {
            case "host":
                if !isEmptyTopLevelBlock(current) {
                    blocks.append(current)
                }
                current = SSHConfigBlock(kind: .host(tokenizeConfigValues(value)))
            case "match":
                if !isEmptyTopLevelBlock(current) {
                    blocks.append(current)
                }
                current = SSHConfigBlock(kind: parseMatchKind(tokens: tokenizeConfigValues(value)))
            case "hostname":
                if current.hostName == nil, let token = tokenizeConfigValues(value).first {
                    current.hostName = token
                }
            case "user":
                if current.user == nil, let token = tokenizeConfigValues(value).first {
                    current.user = token
                }
            case "identityfile":
                if let token = tokenizeConfigValues(value).first {
                    current.identityFiles.append(token)
                }
            case "certificatefile":
                if let token = tokenizeConfigValues(value).first {
                    current.certificateFiles.append(token)
                }
            default:
                break
            }
        }
        if !isEmptyTopLevelBlock(current) {
            blocks.append(current)
        }
        return blocks
    }

    private func isEmptyTopLevelBlock(_ block: SSHConfigBlock) -> Bool {
        if case .topLevel = block.kind {
            return block.hostName == nil
                && block.user == nil
                && block.identityFiles.isEmpty
                && block.certificateFiles.isEmpty
        }
        return false
    }

    private func parseDirective(_ rawLine: String) -> (key: String, value: String)? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        guard let sepIndex = trimmed.firstIndex(where: { $0.isWhitespace || $0 == "=" }) else {
            return (trimmed.lowercased(), "")
        }
        let key = String(trimmed[..<sepIndex]).lowercased()
        var rest = trimmed[sepIndex...].drop(while: { $0.isWhitespace })
        if rest.first == "=" {
            rest = rest.dropFirst().drop(while: { $0.isWhitespace })
        }
        return (key, String(rest))
    }

    private func tokenizeConfigValues(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false

        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if ch.isWhitespace && !inQuotes {
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(ch)
                hasToken = true
            }
        }
        if hasToken {
            tokens.append(current)
        }
        return tokens
    }

    private func parseMatchKind(tokens: [String]) -> SSHConfigBlock.Kind {
        var hostCriteria: [MatchCriterion] = []
        var userCriteria: [MatchCriterion] = []
        var localUserCriteria: [MatchCriterion] = []
        var isAll = false

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawKeyword = String(parts[0])
            let inlineArg = parts.count == 2 ? String(parts[1]) : nil
            let negated = rawKeyword.hasPrefix("!")
            let keyword = (negated ? String(rawKeyword.dropFirst()) : rawKeyword).lowercased()

            func consumeArg() -> String? {
                if let inlineArg { return inlineArg }
                if index + 1 < tokens.count {
                    index += 1
                    return tokens[index]
                }
                return nil
            }

            switch keyword {
            case "all":
                isAll = true
            case "canonical", "final":
                break
            case "host", "originalhost":
                if let arg = consumeArg() {
                    let patterns = arg.split(separator: ",").map(String.init)
                    hostCriteria.append(MatchCriterion(negated: negated, patterns: patterns))
                }
            case "user":
                if let arg = consumeArg() {
                    let patterns = arg.split(separator: ",").map(String.init)
                    userCriteria.append(MatchCriterion(negated: negated, patterns: patterns))
                }
            case "localuser":
                if let arg = consumeArg() {
                    let patterns = arg.split(separator: ",").map(String.init)
                    localUserCriteria.append(MatchCriterion(negated: negated, patterns: patterns))
                }
            default:
                if inlineArg == nil, index + 1 < tokens.count {
                    index += 1
                }
            }
            index += 1
        }

        return .match(
            hostCriteria: hostCriteria,
            userCriteria: userCriteria,
            localUserCriteria: localUserCriteria,
            isAll: isAll
        )
    }

    private func resolveEffectiveUser(
        explicitUser: String,
        defaultUser: String,
        blocks: [SSHConfigBlock],
        host: String
    ) -> String {
        let trimmed = explicitUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let hostBlocks = blocks.filter { blockMatchesHost($0, host: host, localUser: defaultUser) }
        if hostBlocks.contains(where: { explicitlyMatchesDefaultUser($0, defaultUser: defaultUser) }) {
            return defaultUser
        }
        if hostBlocks.contains(where: { !isCatchAllBlock($0, host: host) && !hasExplicitUserFilter($0) }) {
            return defaultUser
        }
        if let specificUser = hostBlocks.first(where: { !isCatchAllBlock($0, host: host) })?.user,
           !specificUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return specificUser
        }
        if let fallbackUser = hostBlocks.compactMap(\.user).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return fallbackUser
        }
        return defaultUser
    }

    private func explicitlyMatchesDefaultUser(_ block: SSHConfigBlock, defaultUser: String) -> Bool {
        if let blockUser = block.user, blockUser.caseInsensitiveCompare(defaultUser) == .orderedSame {
            return true
        }
        if case .match(_, let userCriteria, _, _) = block.kind, !userCriteria.isEmpty {
            return userCriteria.allSatisfy { matchesPatternList($0.patterns, target: defaultUser) != $0.negated }
        }
        return false
    }

    private func hasExplicitUserFilter(_ block: SSHConfigBlock) -> Bool {
        if block.user != nil {
            return true
        }
        if case .match(_, let userCriteria, _, _) = block.kind {
            return !userCriteria.isEmpty
        }
        return false
    }

    private func blockMatchesHost(_ block: SSHConfigBlock, host: String, localUser: String) -> Bool {
        let hostNameMatches = block.hostName.map {
            stripIPv6Brackets($0).caseInsensitiveCompare(host) == .orderedSame
        } ?? false

        switch block.kind {
        case .topLevel:
            return true
        case .host(let patterns):
            return matchesPatternList(patterns, target: host) || hostNameMatches
        case .match(let hostCriteria, let userCriteria, let localUserCriteria, let isAll):
            guard localUserCriteria.allSatisfy({ matchesPatternList($0.patterns, target: localUser) != $0.negated }) else {
                return false
            }
            if !hostCriteria.isEmpty {
                return hostCriteria.allSatisfy { matchesPatternList($0.patterns, target: host) != $0.negated }
            }
            return isAll || !userCriteria.isEmpty || hostNameMatches
        }
    }

    private func isCatchAllBlock(_ block: SSHConfigBlock, host: String) -> Bool {
        let hostNameMatches = block.hostName.map {
            stripIPv6Brackets($0).caseInsensitiveCompare(host) == .orderedSame
        } ?? false
        if hostNameMatches {
            return false
        }
        switch block.kind {
        case .topLevel:
            return true
        case .host(let patterns):
            return patterns.allSatisfy { $0 == "*" || $0.hasPrefix("!") }
        case .match(let hostCriteria, _, _, _):
            return hostCriteria.isEmpty
        }
    }

    private func blockMatchesUser(_ block: SSHConfigBlock, effectiveUser: String, localUser: String) -> Bool {
        if let blockUser = block.user, blockUser.caseInsensitiveCompare(effectiveUser) != .orderedSame {
            return false
        }
        if case .match(_, let userCriteria, let localUserCriteria, _) = block.kind {
            let remoteOK = userCriteria.allSatisfy { matchesPatternList($0.patterns, target: effectiveUser) != $0.negated }
            let localOK = localUserCriteria.allSatisfy { matchesPatternList($0.patterns, target: localUser) != $0.negated }
            return remoteOK && localOK
        }
        return true
    }

    private func matchesPatternList(_ patterns: [String], target: String) -> Bool {
        var matchedPositive = false
        for rawPattern in patterns {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            if pattern.hasPrefix("!") {
                let negated = String(pattern.dropFirst())
                if matchesGlob(target, pattern: negated) {
                    return false
                }
            } else if matchesGlob(target, pattern: pattern) {
                matchedPositive = true
            }
        }
        return matchedPositive
    }

    private func matchesGlob(_ text: String, pattern: String) -> Bool {
        let s = Array(text.lowercased())
        let p = Array(pattern.lowercased())
        var si = 0
        var pi = 0
        var starIdx: Int?
        var matchIdx = 0

        while si < s.count {
            if pi < p.count && (p[pi] == "?" || p[pi] == s[si]) {
                si += 1
                pi += 1
            } else if pi < p.count && p[pi] == "*" {
                starIdx = pi
                matchIdx = si
                pi += 1
            } else if let star = starIdx {
                pi = star + 1
                matchIdx += 1
                si = matchIdx
            } else {
                return false
            }
        }
        while pi < p.count && p[pi] == "*" {
            pi += 1
        }
        return pi == p.count
    }

    private func expandCredentialPath(
        _ rawPath: String,
        targetHost: String,
        queryHost: String,
        remoteUser: String,
        localUser: String,
        port: Int?
    ) -> String {
        let resolvedHostToken = expandTokens(targetHost, tokens: ["h": queryHost, "%": "%"])
        let homeExpanded = expandRealHomePath(rawPath)
        guard !homeExpanded.isEmpty else { return "" }

        let tokenExpanded = expandTokens(
            homeExpanded,
            tokens: [
                "%": "%",
                "h": resolvedHostToken,
                "r": remoteUser,
                "u": localUser,
                "p": String(port ?? 22)
            ]
        )
        guard tokenExpanded.hasPrefix("/") else { return "" }
        return URL(fileURLWithPath: tokenExpanded).standardizedFileURL.path
    }

    private func expandTokens(_ input: String, tokens: [Character: String]) -> String {
        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            let ch = input[index]
            let next = input.index(after: index)
            if ch == "%", next < input.endIndex {
                let code = input[next]
                if let replacement = tokens[code] {
                    result.append(replacement)
                    index = input.index(after: next)
                    continue
                }
            }
            result.append(ch)
            index = next
        }
        return result
    }
}
