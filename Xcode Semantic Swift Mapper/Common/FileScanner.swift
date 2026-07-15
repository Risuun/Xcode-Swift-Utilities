import Foundation

public func findSwiftFiles(at path: String, excluding: [String]) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        return []
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
