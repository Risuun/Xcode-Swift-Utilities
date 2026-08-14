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

public func findSwiftFiles(at path: String, excluding: [String]) -> [URL] {
    let resolvedPath = resolveOrExitTarget(path)
    let url = URL(fileURLWithPath: resolvedPath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        fputs("[ERROR: Target not found: \(path)]\n", stderr)
        exit(1)
    }
    
    if !isDir.boolValue {
        return shouldExclude(url.path, patterns: excluding) ? [] : [url]
    }
    
    var swiftFiles: [URL] = []
    let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    
    while let fileURL = enumerator?.nextObject() as? URL {
        if shouldExclude(fileURL.path, patterns: excluding) {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator?.skipDescendants()
            }
            continue
        }
        if fileURL.pathExtension == "swift" {
            swiftFiles.append(fileURL)
        }
    }
    return swiftFiles
}

public func shouldExclude(_ path: String, patterns: [String]) -> Bool {
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
