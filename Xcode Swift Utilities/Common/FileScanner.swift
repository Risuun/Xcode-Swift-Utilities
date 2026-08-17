// FileScanner.swift // Common

import Foundation

public func findProjectRoot(from startPath: String = FileManager.default.currentDirectoryPath) -> URL {
    var current = URL(fileURLWithPath: startPath).standardizedFileURL
    while current.path != "/" {
        let gitPath = current.appendingPathComponent(".git").path
        if FileManager.default.fileExists(atPath: gitPath) {
            return current
        }
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path) {
            if contents.contains(where: { $0.hasSuffix(".xcodeproj") || $0 == "Package.swift" }) {
                return current
            }
        }
        current = current.deletingLastPathComponent()
    }
    return URL(fileURLWithPath: startPath).standardizedFileURL
}

public func resolveTargetFileOrDirectory(_ inputPath: String) -> String? {
    let directURL = URL(fileURLWithPath: inputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
    if FileManager.default.fileExists(atPath: directURL.path) {
        return directURL.path
    }
    
    let rootURL = findProjectRoot()
    let leafName = URL(fileURLWithPath: inputPath).lastPathComponent
    
    let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    
    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.lastPathComponent == leafName || fileURL.lastPathComponent == inputPath {
            return fileURL.standardizedFileURL.path
        }
    }
    
    return nil
}

public func resolveOrExitTarget(_ inputPath: String) -> String {
    guard let resolved = resolveTargetFileOrDirectory(inputPath) else {
        fputs("[ERROR: Target not found: \(inputPath)]\n", stderr)
        exit(1)
    }
    return resolved
}

public struct FileDiscovery {
    public static let ignoredDirectories: Set<String> = [
        ".build", "DerivedData", ".git", "Pods", "Carthage", 
        "Preview Content", "Tests", "UITests", "build"
    ]
    
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
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var swiftFiles = [URL]()
        for case let fileURL as URL in enumerator {
            if let isSubDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isSubDir {
                if ignoredDirectories.contains(fileURL.lastPathComponent) || shouldExclude(fileURL.path, patterns: excluding) {
                    enumerator.skipDescendants()
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
    let defaultIgnores = [".build", "DerivedData", ".xcodeproj", ".xcworkspace", ".swiftpm", "/Pods/", "/Carthage/", "/.git/"]
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
