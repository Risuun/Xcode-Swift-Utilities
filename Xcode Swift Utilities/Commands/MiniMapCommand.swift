// MiniMapCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

public struct MiniMapEntry {
    public let line: Int
    public let declaration: String
}

public class MiniMapVisitor: SyntaxVisitor {
    public let locationConverter: SourceLocationConverter
    public var entries: [MiniMapEntry] = []
    
    public init(locationConverter: SourceLocationConverter) {
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: locationConverter).line
        entries.append(MiniMapEntry(line: line, declaration: "struct \(node.name.text)"))
        return .visitChildren
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: locationConverter).line
        entries.append(MiniMapEntry(line: line, declaration: "class \(node.name.text)"))
        return .visitChildren
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: locationConverter).line
        entries.append(MiniMapEntry(line: line, declaration: "enum \(node.name.text)"))
        return .visitChildren
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: locationConverter).line
        entries.append(MiniMapEntry(line: line, declaration: "actor \(node.name.text)"))
        return .visitChildren
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let line = node.startLocation(converter: locationConverter).line
        let signature = node.signature.trimmedDescription
        entries.append(MiniMapEntry(line: line, declaration: "func \(node.name.text)\(signature)"))
        return .visitChildren
    }
}

public func runMiniMap(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap mini-map <file-path>")
        exit(0)
    }
    
    guard !args.isEmpty else {
        fputs("Usage: XCSwiftMap mini-map <file-path>\n", stderr)
        exit(1)
    }
    
    let rawPath = args[0]
    let sanitizedPath = sanitizePath(rawPath)
    let resolvedPath = resolveOrExitTarget(sanitizedPath)
    let fileURL = URL(fileURLWithPath: resolvedPath)
    
    guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(sanitizedPath)]\n", stderr)
        exit(1)
    }
    
    let sourceFile = Parser.parse(source: fileContent)
    let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
    let visitor = MiniMapVisitor(locationConverter: converter)
    visitor.walk(sourceFile)
    
    if visitor.entries.isEmpty {
        print("[OK: No struct/class/func declarations in \(fileURL.lastPathComponent)]")
    } else {
        let sorted = visitor.entries.sorted { $0.line < $1.line }
        for entry in sorted {
            print("Line \(entry.line): \(entry.declaration)")
        }
    }
}