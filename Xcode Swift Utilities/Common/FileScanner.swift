// FileScanner.swift // XCEdit //

import Foundation

public func sanitizePath(_ rawPath: String) -> String {
    var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    while (path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2) ||
          (path.hasPrefix("'") && path.hasSuffix("'") && path.count >= 2) {
        path = String(path.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    path = (path as NSString).expandingTildeInPath
    return path
}

public func normalizePath(_ rawPath: String, relativeTo basePath: String = FileManager.default.currentDirectoryPath) -> String {
    let sanitized = sanitizePath(rawPath)
    if sanitized.isEmpty || sanitized == "." || sanitized == "./" {
        return URL(fileURLWithPath: sanitizePath(basePath)).standardizedFileURL.path
    }
    if sanitized.hasPrefix("/") {
        return URL(fileURLWithPath: sanitized).standardizedFileURL.path
    }
    let baseURL = URL(fileURLWithPath: sanitizePath(basePath))
    return URL(fileURLWithPath: sanitized, relativeTo: baseURL).standardizedFileURL.path
}

public func findProjectRoot(from startPath: String = FileManager.default.currentDirectoryPath) -> URL {
    let sanitized = sanitizePath(startPath)
    var current = URL(fileURLWithPath: sanitized).standardizedFileURL
    while current.path != "/" && current.pathComponents.count > 1 {
        let gitPath = current.appendingPathComponent(".git").path
        if FileManager.default.fileExists(atPath: gitPath) {
            return current
        }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path) {
            if contents.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") || $0 == "Package.swift" }) {
                return current
            }
        }
        current = current.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: sanitized).standardizedFileURL
}

public func resolveTargetFileOrDirectory(_ inputPath: String) -> String? {
    let sanitized = sanitizePath(inputPath)
    guard !sanitized.isEmpty else { return nil }
    
    let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
    let directURL: URL
    if sanitized.hasPrefix("/") {
        directURL = URL(fileURLWithPath: sanitized).standardizedFileURL
    } else {
        directURL = URL(fileURLWithPath: sanitized, relativeTo: currentDir).standardizedFileURL
    }
    
    if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL.path
    }
    
    let rootURL = findProjectRoot(from: currentDir.path)
    let leafName = URL(fileURLWithPath: sanitized).lastPathComponent
    
    guard let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        return nil
    }
    
    while let fileURL = enumerator.nextObject() as? URL {
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let name = fileURL.lastPathComponent
        if isDir {
            if FileDiscovery.isIgnoredDirectory(name: name, path: fileURL.path) {
                enumerator.skipDescendants()
                continue
            }
        }
        if fileURL.lastPathComponent == leafName || fileURL.lastPathComponent == sanitized {
            return fileURL.standardizedFileURL.path
        }
    }
    
    return nil
}

public func resolveOrExitTarget(_ inputPath: String) -> String {
    let sanitized = sanitizePath(inputPath)
    guard let resolved = resolveTargetFileOrDirectory(sanitized) else {
        fputs("[ERROR: Target not found: \(inputPath)]\n", stderr)
        exit(1)
    }
    return resolved
}

public struct FileDiscovery {
    public static let ignoredDirectories: Set<String> = [
        "DerivedData", ".build", ".git", ".swiftpm", ".xcodeproj", ".xcworkspace",
        "Pods", "Carthage", "Preview Content", "Tests", "UITests", "build"
    ]
    
    public static func isIgnoredDirectory(name: String, path: String = "") -> Bool {
        if ignoredDirectories.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
            return true
        }
        if !path.isEmpty && shouldExclude(path, patterns: []) {
            return true
        }
        return false
    }
    
    public static func discoverSwiftFiles(at path: String, excluding: [String] = []) -> [URL] {
        let resolvedPath = resolveOrExitTarget(path)
        let url = URL(fileURLWithPath: resolvedPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        
        if !isDir.boolValue {
            if url.pathExtension == "swift" && !shouldExclude(url.path, patterns: excluding) {
                return [url]
            }
            return []
        }
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        
        var swiftFiles = [URL]()
        for case let fileURL as URL in enumerator {
            let isSubDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isSubDir {
                let name = fileURL.lastPathComponent
                if isIgnoredDirectory(name: name, path: fileURL.path) || shouldExclude(fileURL.path, patterns: excluding) {
                    enumerator.skipDescendants()
                    continue
                }
            } else if fileURL.pathExtension == "swift" {
                if !shouldExclude(fileURL.path, patterns: excluding) {
                    swiftFiles.append(fileURL)
                }
            }
        }
        return swiftFiles
    }
}

public struct FastFilter {
    public static func shouldParse(rawText: String, subcommand: String, queryOrModel: String?) -> Bool {
        switch subcommand {
        case "audit-filters":
            if let model = queryOrModel {
                let containsModel = rawText.localizedCaseInsensitiveContains(model) || rawText.contains(model)
                let containsFilterToken = rawText.contains("filter") || rawText.contains("@Query") || rawText.contains("Predicate")
                return containsModel && containsFilterToken
            }
            return rawText.contains("filter") || rawText.contains("@Query")
            
        case "find-usage":
            if let symbol = queryOrModel {
                return rawText.localizedCaseInsensitiveContains(symbol)
            }
            return true
            
        case "locate":
            if let symbol = queryOrModel {
                return rawText.localizedCaseInsensitiveContains(symbol)
            }
            return true
            
        case "extract-schema":
            return rawText.contains("@Model") || rawText.contains("@Query")
            
        case "audit-memory":
            return rawText.contains("self")
            
        case "trace-state", "scope-check":
            return rawText.contains("@State") || rawText.contains("@Binding") || rawText.contains("@Query") || rawText.contains("@Bindable") || rawText.contains("@StateObject") || rawText.contains("@ObservedObject") || rawText.contains("View")
            
        default:
            return true
        }
    }

    public static func shouldParse(fileURL: URL, subcommand: String, queryOrModel: String?) -> Bool {
        guard let rawText = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        return shouldParse(rawText: rawText, subcommand: subcommand, queryOrModel: queryOrModel)
    }
}

public struct ParallelASTScanner {
    private final class ResultCollector<T>: @unchecked Sendable {
        var items = [T]()
        let lock = NSLock()
        
        func append(_ newItems: [T]) {
            lock.lock()
            items.append(contentsOf: newItems)
            lock.unlock()
        }
    }
    
    public static func scan<T>(files: [URL], block: @Sendable @escaping (URL) -> [T]) -> [T] {
        let collector = ResultCollector<T>()
        
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let fileURL = files[index]
            let fileResults = block(fileURL)
            
            if !fileResults.isEmpty {
                collector.append(fileResults)
            }
        }
        return collector.items
    }
}

public func findSwiftFiles(at path: String, excluding: [String] = []) -> [URL] {
    return FileDiscovery.discoverSwiftFiles(at: path, excluding: excluding)
}

public func shouldExclude(_ path: String, patterns: [String]) -> Bool {
    let defaultIgnores = [
        "DerivedData", ".build", ".git", ".swiftpm", ".xcodeproj", ".xcworkspace",
        "Pods", "Carthage", "/Pods/", "/Carthage/", "/.git/", "/DerivedData/", "/.build/", "/.swiftpm/"
    ]
    for ignore in defaultIgnores {
        if path.contains(ignore) {
            return true
        }
    }
    for pattern in patterns {
        if path.lowercased().contains(pattern.lowercased()) {
            return true
        }
    }
    return false
}

public func relativePath(of fileURL: URL, relativeTo baseURL: URL) -> String {
    let baseParts = baseURL.standardizedFileURL.pathComponents
    let fileParts = fileURL.standardizedFileURL.pathComponents
    
    var commonCount = 0
    while commonCount < baseParts.count && commonCount < fileParts.count && baseParts[commonCount] == fileParts[commonCount] {
        commonCount += 1
    }
    
    let remaining = fileParts.suffix(from: commonCount)
    if remaining.isEmpty {
        return fileURL.lastPathComponent
    }
    return remaining.joined(separator: "/")
}

public func getBaseTypeName(from typeStr: String) -> String {
    var result = typeStr.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.hasSuffix("?") || result.hasSuffix("!") {
        result = String(result.dropLast())
    }
    if result.hasPrefix("[") && result.hasSuffix("]") {
        result = String(result.dropFirst().dropLast())
    }
    if result.hasSuffix("?") || result.hasSuffix("!") {
        result = String(result.dropLast())
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}