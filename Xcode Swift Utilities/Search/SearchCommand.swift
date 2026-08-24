// SearchCommand.swift // XCEdit //

import Foundation

public func runSearch(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap search \"<query>\" [path] [--limit <n>] [--json]")
        exit(0)
    }
    
    var query: String? = nil
    var targetPath: String = "."
    var limit: Int = 5
    var isJSON: Bool = false
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg == "--limit" || arg == "-l" {
            if idx + 1 < args.count, let parsedLimit = Int(args[idx + 1]), parsedLimit > 0 {
                limit = parsedLimit
                idx += 1
            }
        } else if query == nil {
            query = arg
        } else if targetPath == "." {
            targetPath = arg
        }
        idx += 1
    }
    
    guard let rawConcept = query else {
        fputs("[ERROR: Missing search query concept]\n", stderr)
        exit(1)
    }
    let searchConcept = sanitizePath(rawConcept)
    guard !searchConcept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fputs("[ERROR: Missing search query concept]\n", stderr)
        exit(1)
    }
    
    let sanitizedPath = sanitizePath(targetPath)
    let modelPath = ModelResolver.resolveModelPathOrExit()
    
    guard let engine = try? EmbeddingEngine(modelPath: modelPath) else {
        fputs("[ERROR: Failed to initialize EmbeddingEngine with model at \(URL(fileURLWithPath: modelPath).lastPathComponent)]\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: sanitizedPath, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found or contains no Swift files: \(sanitizedPath)]\n", stderr)
        exit(1)
    }
    
    let index = CodeVectorIndex(engine: engine, targetPath: sanitizedPath)
    index.indexFiles(swiftFiles)
    
    let results = index.search(query: searchConcept, threshold: 0.55, limit: limit)
    
    if results.isEmpty {
        fputs("[MISSING: No semantic code matches found for '\(searchConcept)']\n", stderr)
        exit(1)
    }
    
    if isJSON {
        struct JSONResult: Encodable {
            let score: Float
            let location: String
            let kind: String
            let signature: String
        }
        let mapped = results.map { res in
            JSONResult(
                score: res.score,
                location: "\(res.chunk.leafName):\(res.chunk.lineStart)",
                kind: res.chunk.kind,
                signature: res.chunk.signature
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(mapped), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    } else {
        for res in results {
            let scoreStr = String(format: "%.2f", res.score)
            let loc = "\(res.chunk.leafName):\(res.chunk.lineStart)"
            print("\(scoreStr)|\(loc)|\(res.chunk.kind)|\(res.chunk.signature)")
        }
    }
    exit(0)
}

public func runIndex(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap index [path]")
        exit(0)
    }
    
    var targetPath: String = "."
    for arg in args {
        if !arg.hasPrefix("-") {
            targetPath = arg
            break
        }
    }
    
    let sanitizedPath = sanitizePath(targetPath)
    let modelPath = ModelResolver.resolveModelPathOrExit()
    
    guard let engine = try? EmbeddingEngine(modelPath: modelPath) else {
        fputs("[ERROR: Failed to initialize EmbeddingEngine with model at \(URL(fileURLWithPath: modelPath).lastPathComponent)]\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: sanitizedPath, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found or contains no Swift files: \(sanitizedPath)]\n", stderr)
        exit(1)
    }
    
    let index = CodeVectorIndex(engine: engine, targetPath: sanitizedPath)
    let stats = index.indexFiles(swiftFiles)
    let root = findProjectRoot(from: sanitizedPath)
    let leafProject = root.lastPathComponent
    
    print("[OK: Indexed \(stats.totalChunks) chunks across \(stats.fileCount) files in \(leafProject)]")
    exit(0)
}