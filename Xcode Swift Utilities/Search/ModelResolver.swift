// ModelResolver.swift // Search
//
// Resolves the path to the bge-small-en-v1.5-q4_k_m.gguf model file.
//

import Foundation

public enum ModelResolver {
    public static let modelFilename = "bge-small-en-v1.5-q4_k_m.gguf"
    
    public static func resolveModelPath() -> String? {
        let fileManager = FileManager.default
        var candidateURLs: [URL] = []
        
        // 1. Sibling Resources/ directory relative to the running binary (CommandLine.arguments[0])
        let binaryPath = CommandLine.arguments[0]
        let binaryURL = URL(fileURLWithPath: binaryPath).standardizedFileURL
        let binaryDir = binaryURL.deletingLastPathComponent()
        candidateURLs.append(binaryDir.appendingPathComponent("Resources/\(modelFilename)"))
        candidateURLs.append(binaryDir.appendingPathComponent(modelFilename))
        candidateURLs.append(binaryDir.deletingLastPathComponent().appendingPathComponent("Resources/\(modelFilename)"))
        
        // 2. Sibling bundle path: Bundle.main.bundleURL.appendingPathComponent("Resources/bge-small-en-v1.5-q4_k_m.gguf")
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent("Resources/\(modelFilename)"))
        candidateURLs.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/\(modelFilename)"))
        if let resourceURL = Bundle.main.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(modelFilename))
            candidateURLs.append(resourceURL.appendingPathComponent("Resources/\(modelFilename)"))
        }
        if let execURL = Bundle.main.executableURL {
            let execDir = execURL.deletingLastPathComponent()
            candidateURLs.append(execDir.appendingPathComponent("Resources/\(modelFilename)"))
            candidateURLs.append(execDir.appendingPathComponent(modelFilename))
            candidateURLs.append(execDir.deletingLastPathComponent().appendingPathComponent("Resources/\(modelFilename)"))
        }
        
        // 3. Global cache: ~/.antigravity/models/bge-small-en-v1.5-q4_k_m.gguf
        let homeDir = fileManager.homeDirectoryForCurrentUser
        candidateURLs.append(homeDir.appendingPathComponent(".antigravity/models/\(modelFilename)"))
        candidateURLs.append(homeDir.appendingPathComponent(".antigravity/\(modelFilename)"))
        
        // 4. Development fallback: Local .build or workspace project resources
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath).standardizedFileURL
        candidateURLs.append(currentDir.appendingPathComponent("Resources/\(modelFilename)"))
        candidateURLs.append(currentDir.appendingPathComponent(modelFilename))
        candidateURLs.append(currentDir.appendingPathComponent(".build/\(modelFilename)"))
        
        let rootURL = findProjectRoot(from: currentDir.path)
        candidateURLs.append(rootURL.appendingPathComponent("Resources/\(modelFilename)"))
        candidateURLs.append(rootURL.appendingPathComponent(".build/\(modelFilename)"))
        
        for url in candidateURLs {
            if fileManager.fileExists(atPath: url.path) {
                return url.path
            }
        }
        
        return nil
    }
    
    public static func resolveModelPathOrExit() -> String {
        if let path = resolveModelPath() {
            return path
        }
        fputs("[ERROR: Missing embedding model \(modelFilename) in Resources/ or ~/.antigravity/models/]\n", stderr)
        exit(1)
    }
}
