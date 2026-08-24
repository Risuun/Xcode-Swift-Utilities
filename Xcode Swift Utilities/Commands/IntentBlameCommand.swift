// IntentBlameCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

private class FunctionLocationFinder: SyntaxVisitor {
    let targetName: String
    var targetFunction: FunctionDeclSyntax? = nil
    
    init(targetName: String) {
        self.targetName = targetName
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == targetName {
            if targetFunction == nil {
                targetFunction = node
            }
        }
        return .visitChildren
    }
}

public func runIntentBlame(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap intent-blame <symbol> <file-path>")
        exit(0)
    }
    
    var symbol: String? = nil
    var filePath: String? = nil
    var positional: [String] = []
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--symbol" || arg == "-s" {
            if idx + 1 < args.count {
                symbol = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--symbol=") {
            symbol = String(arg.dropFirst("--symbol=".count))
        } else if arg == "--file" || arg == "-f" {
            if idx + 1 < args.count {
                filePath = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--file=") {
            filePath = String(arg.dropFirst("--file=".count))
        } else if !arg.hasPrefix("-") {
            positional.append(arg)
        }
        idx += 1
    }
    
    if symbol == nil && positional.count > 0 {
        symbol = positional[0]
    }
    if filePath == nil && positional.count > 1 {
        filePath = positional[1]
    }
    
    guard let rawSymbol = symbol, let rawPath = filePath else {
        fputs("Usage: XCSwiftMap intent-blame <symbol> <file-path>\n", stderr)
        exit(1)
    }
    
    let targetSymbol = sanitizePath(rawSymbol)
    let targetPath = sanitizePath(rawPath)
    
    let resolvedPath = resolveOrExitTarget(targetPath)
    let fileURL = URL(fileURLWithPath: resolvedPath)
    
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    let sourceFile = Parser.parse(source: content)
    let finder = FunctionLocationFinder(targetName: targetSymbol)
    finder.walk(sourceFile)
    
    guard let funcDecl = finder.targetFunction else {
        fputs("[ERROR: Function '\(targetSymbol)' not found in \(fileURL.lastPathComponent)]\n", stderr)
        exit(1)
    }
    
    let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
    let startLine = funcDecl.startLocation(converter: converter).line
    let endLine = funcDecl.endLocation(converter: converter).line
    
    // Execute git blame --porcelain with non-blocking pipe reads
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["blame", "-L", "\(startLine),\(endLine)", "--porcelain", fileURL.path]
    process.currentDirectoryURL = fileURL.deletingLastPathComponent()
    
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    
    final class DataBuffer: @unchecked Sendable {
        var data = Data()
    }
    let outputBuffer = DataBuffer()
    let group = DispatchGroup()
    
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        outputBuffer.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    
    do {
        try process.run()
        process.waitUntilExit()
        group.wait()
        
        let stdoutData = outputBuffer.data
        guard let output = String(data: stdoutData, encoding: .utf8), !output.isEmpty else {
            fputs("[ERROR: Git blame returned no output for \(fileURL.lastPathComponent):\(startLine)-\(endLine)]\n", stderr)
            exit(1)
        }
        struct CommitEntry {
            let hash: String
            let timestamp: Int
            let summary: String
        }
        
        var commits: [String: CommitEntry] = [:]
        var currentHash: String? = nil
        var currentTimestamp: Int = 0
        var currentSummary: String? = nil
        
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("author-time ") {
                let tsStr = String(line.dropFirst("author-time ".count)).trimmingCharacters(in: .whitespaces)
                currentTimestamp = Int(tsStr) ?? 0
            } else if line.hasPrefix("summary ") {
                currentSummary = String(line.dropFirst("summary ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("\t") {
                if let hash = currentHash, let summary = currentSummary {
                    if commits[hash] == nil {
                        commits[hash] = CommitEntry(hash: hash, timestamp: currentTimestamp, summary: summary)
                    }
                }
                currentHash = nil
                currentSummary = nil
                currentTimestamp = 0
            } else if !line.isEmpty && !line.contains(" ") {
                // Initial 40-character commit hash line or start of header
                let parts = line.split(separator: " ")
                if let first = parts.first, first.count >= 8 {
                    currentHash = String(first)
                }
            } else if !line.isEmpty {
                let parts = line.split(separator: " ")
                if let first = parts.first, first.count >= 8, parts.count >= 4 {
                    currentHash = String(first)
                }
            }
        }
        
        // Sort chronologically by timestamp
        let sortedCommits = commits.values.sorted { $0.timestamp < $1.timestamp }
        
        // Deduplicate messages in chronological order
        var uniqueSummaries: [String] = []
        for commit in sortedCommits {
            if !uniqueSummaries.contains(commit.summary) && !commit.summary.isEmpty {
                uniqueSummaries.append(commit.summary)
            }
        }
        
        if uniqueSummaries.isEmpty {
            print("[OK: No commit history found for \(targetSymbol)]")
        } else {
            for summary in uniqueSummaries {
                print(summary)
            }
        }
    } catch {
        fputs("[ERROR: Failed to run git blame: \(error.localizedDescription)]\n", stderr)
        exit(1)
    }
}