// AuditMemoryCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

func runAuditMemory(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap audit-memory [--json] <directory-or-file-path>")
        exit(0)
    }
    
    var isJSON = false
    var path: String? = nil
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        } else {
            path = arg
        }
        idx += 1
    }
    
    guard let rawPath = path else {
        fputs("Usage: XCSwiftMap audit-memory [--json] <directory-or-file-path>\n", stderr)
        exit(1)
    }
    
    let targetPath = sanitizePath(rawPath)
    let swiftFiles = findSwiftFiles(at: targetPath, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    let baseFolderURL = URL(fileURLWithPath: resolveOrExitTarget(targetPath))
    
    let violations = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [MemoryViolation] in
        guard FastFilter.shouldParse(fileURL: fileURL, subcommand: "audit-memory", queryOrModel: nil) else {
            return []
        }
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: fileContent)
        let visitor = MemoryAuditVisitor(viewMode: .sourceAccurate)
        let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
        visitor.currentFilePath = relPath
        visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        visitor.walk(sourceFile)
        return visitor.violations
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(violations), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        if violations.isEmpty {
            print("[OK: No active matches found for 'RetainCycles' across \(swiftFiles.count) scanned files]")
        } else {
            for violation in violations {
                let leaf = URL(fileURLWithPath: violation.location.file).lastPathComponent
                print("\(leaf):\(violation.location.line):\(violation.location.column): warning: strong self capture in closure")
            }
        }
    }
}