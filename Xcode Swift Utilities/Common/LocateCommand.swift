// LocateCommand.swift // Common

import Foundation
import SwiftSyntax
import SwiftParser

public struct SymbolLocationModel: Codable {
    public var kind: String
    public var name: String
    public var file: String
    public var line: Int
    public var declarationSnippet: String
}

public class SymbolLocatorVisitor: SyntaxVisitor {
    public var symbolQuery: String = ""
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    public var results: [SymbolLocationModel] = []

    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }

    private func recordMatch(kind: String, name: String, node: SyntaxProtocol) {
        guard let converter = currentLocationConverter else { return }
        let startLoc = node.startLocation(converter: converter)
        let snippet = node.trimmedDescription.components(separatedBy: "\n").first ?? ""
        let model = SymbolLocationModel(
            kind: kind,
            name: name,
            file: currentFilePath,
            line: startLoc.line,
            declarationSnippet: snippet
        )
        results.append(model)
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text.localizedCaseInsensitiveContains(symbolQuery) {
            recordMatch(kind: "struct", name: node.name.text, node: node)
        }
        return .visitChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text.localizedCaseInsensitiveContains(symbolQuery) {
            recordMatch(kind: "class", name: node.name.text, node: node)
        }
        return .visitChildren
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text.localizedCaseInsensitiveContains(symbolQuery) {
            recordMatch(kind: "enum", name: node.name.text, node: node)
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text.localizedCaseInsensitiveContains(symbolQuery) {
            recordMatch(kind: "func", name: node.name.text, node: node)
        }
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let varName = binding.pattern.trimmedDescription
            if varName.localizedCaseInsensitiveContains(symbolQuery) {
                recordMatch(kind: "var", name: varName, node: node)
            }
        }
        return .visitChildren
    }
}

func runLocate(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap locate <symbol-query> [directory-or-file-path] [--json]")
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
        } else if symbol == nil {
            symbol = arg
        } else {
            path = arg
        }
        idx += 1
    }

    guard let targetSymbol = symbol else {
        fputs("Usage: XCSwiftMap locate <symbol-query> [directory-or-file-path] [--json]\n", stderr)
        exit(1)
    }

    let swiftFiles = findSwiftFiles(at: path, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(path)]\n", stderr)
        exit(1)
    }

    let baseURL = URL(fileURLWithPath: resolveOrExitTarget(path))

    let results = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [SymbolLocationModel] in
        guard FastFilter.shouldParse(fileURL: fileURL, subcommand: "locate", queryOrModel: targetSymbol) else {
            return []
        }
        guard let content = try? String(contentsOfFile: fileURL.path, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: content)
        let visitor = SymbolLocatorVisitor(viewMode: .sourceAccurate)
        visitor.symbolQuery = targetSymbol
        visitor.currentFilePath = relativePath(of: fileURL, relativeTo: baseURL)
        visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        visitor.walk(sourceFile)
        return visitor.results
    }

    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(results), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    } else {
        if results.isEmpty {
            print("[OK: No active matches found for '\(targetSymbol)' across \(swiftFiles.count) scanned files]")
        } else {
            for res in results {
                let leaf = URL(fileURLWithPath: res.file).lastPathComponent
                print("\(res.name)|\(res.kind)|\(leaf):\(res.line)")
            }
        }
    }
}
