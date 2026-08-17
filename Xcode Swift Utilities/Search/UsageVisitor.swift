// UsageVisitor.swift // Search

import Foundation
import SwiftSyntax
import SwiftParser

public struct UsageMatch: Codable {
    public var file: String
    public var line: Int
    public var lineContent: String
    
    public init(file: String, line: Int, lineContent: String) {
        self.file = file
        self.line = line
        self.lineContent = lineContent
    }
}

public class UsageVisitor: SyntaxVisitor {
    public var targetSymbol: String = ""
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    public var currentSourceLines: [String] = []
    public var matches: [UsageMatch] = []
    private var recordedLines: Set<Int> = []
    
    public init(viewMode: SyntaxTreeViewMode, targetSymbol: String = "") {
        self.targetSymbol = targetSymbol
        super.init(viewMode: viewMode)
    }
    
    public func resetForNewFile(filePath: String, converter: SourceLocationConverter, sourceContent: String) {
        self.currentFilePath = filePath
        self.currentLocationConverter = converter
        self.currentSourceLines = sourceContent.components(separatedBy: "\n")
        self.recordedLines.removeAll()
    }
    
    private func recordMatch(node: SyntaxProtocol) {
        guard let converter = currentLocationConverter, !targetSymbol.isEmpty else { return }
        let startLoc = node.startLocation(converter: converter)
        let line = startLoc.line
        guard !recordedLines.contains(line) else { return }
        recordedLines.insert(line)
        
        let lineIdx = line - 1
        let trimmedLine: String
        if lineIdx >= 0 && lineIdx < currentSourceLines.count {
            trimmedLine = currentSourceLines[lineIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            trimmedLine = node.trimmedDescription
        }
        
        matches.append(UsageMatch(file: currentFilePath, line: line, lineContent: trimmedLine))
    }
    
    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if node.baseName.text.lowercased().contains(targetSymbol.lowercased()) {
            recordMatch(node: node)
        }
        return .visitChildren
    }
    
    public override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if node.declName.baseName.text.lowercased().contains(targetSymbol.lowercased()) {
            recordMatch(node: node)
        }
        return .visitChildren
    }
}

public func runFindUsage(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap find-usage <symbol> [directory-or-file-path] [--json]")
        exit(0)
    }
    
    var isJSON = false
    var symbol: String? = nil
    var path: String = "."
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if symbol == nil && !arg.hasPrefix("-") {
            symbol = arg
        } else if !arg.hasPrefix("-") {
            path = arg
        } else {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        }
        idx += 1
    }
    
    guard let targetSymbol = symbol, !targetSymbol.isEmpty else {
        fputs("Usage: XCSwiftMap find-usage <symbol> [directory-or-file-path] [--json]\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: path, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(path)]\n", stderr)
        exit(1)
    }
    
    let baseURL = URL(fileURLWithPath: resolveOrExitTarget(path))
    
    let matches = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [UsageMatch] in
        guard FastFilter.shouldParse(fileURL: fileURL, subcommand: "find-usage", queryOrModel: targetSymbol) else {
            return []
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: content)
        let relPath = relativePath(of: fileURL, relativeTo: baseURL)
        let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        let visitor = UsageVisitor(viewMode: .sourceAccurate, targetSymbol: targetSymbol)
        visitor.resetForNewFile(filePath: relPath, converter: converter, sourceContent: content)
        visitor.walk(sourceFile)
        return visitor.matches
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(matches), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    } else {
        if matches.isEmpty {
            print("[OK: No active matches found for '\(targetSymbol)' across \(swiftFiles.count) scanned files]")
        } else {
            for match in matches {
                let leaf = URL(fileURLWithPath: match.file).lastPathComponent
                print("\(leaf):L\(match.line) | \(match.lineContent)")
            }
        }
    }
}
