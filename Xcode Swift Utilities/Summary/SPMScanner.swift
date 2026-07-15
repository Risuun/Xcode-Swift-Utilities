// SPMScanner.swift // Xcode Swift Utilities

import Foundation

public func findPackageResolvedFiles(at path: String) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        return []
    }
    
    if !isDir.boolValue {
        return url.lastPathComponent == "Package.resolved" ? [url] : []
    }
    
    var resolvedFiles: [URL] = []
    let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    
    while let fileURL = enumerator?.nextObject() as? URL {
        if fileURL.lastPathComponent == "Package.resolved" {
            resolvedFiles.append(fileURL)
        }
    }
    return resolvedFiles
}

public func parsePackageResolved(at url: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    
    var dependencies: [String: String] = [:]
    
    // Check for V2/V3 structure
    if let pins = json["pins"] as? [[String: Any]] {
        for pin in pins {
            let identity = pin["identity"] as? String ?? (pin["package"] as? String ?? "")
            if let state = pin["state"] as? [String: Any], let version = state["version"] as? String {
                dependencies[identity] = version
            }
        }
    }
    // Check for V1 structure
    else if let object = json["object"] as? [String: Any], let pins = object["pins"] as? [[String: Any]] {
        for pin in pins {
            let package = pin["package"] as? String ?? (pin["identity"] as? String ?? "")
            if let state = pin["state"] as? [String: Any], let version = state["version"] as? String {
                dependencies[package] = version
            }
        }
    }
    
    return dependencies
}
