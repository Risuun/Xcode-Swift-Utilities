// CodeChunker.swift // Search
//
// AST-based Swift source code declaration chunker.
//

import Foundation
import SwiftSyntax
import SwiftParser

public struct CodeChunk: Codable, Sendable {
    public let id: String
    public let leafName: String
    public let filePath: String
    public let lineStart: Int
    public let lineEnd: Int
    public let kind: String
    public let name: String
    public let signature: String
    public let embeddingText: String
}

public class CodeChunkerVisitor: SyntaxVisitor {
    public let filePath: String
    public let leafName: String
    public let converter: SourceLocationConverter
    public var chunks: [CodeChunk] = []
    
    public init(filePath: String, leafName: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.leafName = leafName
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }
    
    private func cleanSignature(from raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        let singleLine = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        if let braceIndex = singleLine.firstIndex(of: "{") {
            return String(singleLine[..<braceIndex]).trimmingCharacters(in: .whitespaces)
        }
        return singleLine.trimmingCharacters(in: .whitespaces)
    }
    
    private func makeEmbeddingText(kind: String, name: String, signature: String) -> String {
        return "\(kind) \(name) \(signature)"
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        // Ignore empty / trivial inits or accessors if body is purely empty
        if let body = node.body, body.statements.isEmpty {
            return .visitChildren
        }
        
        // Build clean signature
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        sigParts.append("func \(name)\(node.genericParameterClause?.trimmedDescription ?? "")\(node.signature.trimmedDescription)")
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "func",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "func", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        var decl = "struct \(name)\(node.genericParameterClause?.trimmedDescription ?? "")"
        if let inheritance = node.inheritanceClause?.trimmedDescription {
            decl += " \(inheritance)"
        }
        sigParts.append(decl)
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "struct",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "struct", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        var decl = "class \(name)\(node.genericParameterClause?.trimmedDescription ?? "")"
        if let inheritance = node.inheritanceClause?.trimmedDescription {
            decl += " \(inheritance)"
        }
        sigParts.append(decl)
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "class",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "class", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        var decl = "actor \(name)\(node.genericParameterClause?.trimmedDescription ?? "")"
        if let inheritance = node.inheritanceClause?.trimmedDescription {
            decl += " \(inheritance)"
        }
        sigParts.append(decl)
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "actor",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "actor", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        var decl = "enum \(name)\(node.genericParameterClause?.trimmedDescription ?? "")"
        if let inheritance = node.inheritanceClause?.trimmedDescription {
            decl += " \(inheritance)"
        }
        sigParts.append(decl)
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "enum",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "enum", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
    
    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let startLoc = node.startLocation(converter: converter)
        let endLoc = node.endLocation(converter: converter)
        let name = node.name.text
        
        var sigParts: [String] = []
        if !node.attributes.isEmpty {
            let attrs = node.attributes.trimmedDescription
            if !attrs.isEmpty { sigParts.append(attrs) }
        }
        if !node.modifiers.isEmpty {
            let mods = node.modifiers.trimmedDescription
            if !mods.isEmpty { sigParts.append(mods) }
        }
        var decl = "protocol \(name)"
        if let inheritance = node.inheritanceClause?.trimmedDescription {
            decl += " \(inheritance)"
        }
        sigParts.append(decl)
        let signature = sigParts.joined(separator: " ")
        
        let chunk = CodeChunk(
            id: "\(filePath):\(startLoc.line)-\(endLoc.line):\(name)",
            leafName: leafName,
            filePath: filePath,
            lineStart: startLoc.line,
            lineEnd: endLoc.line,
            kind: "protocol",
            name: name,
            signature: signature,
            embeddingText: makeEmbeddingText(kind: "protocol", name: name, signature: signature)
        )
        chunks.append(chunk)
        return .visitChildren
    }
}

public enum CodeChunker {
    public static func chunk(fileURL: URL, relativeTo baseURL: URL? = nil) -> [CodeChunk] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: content)
        let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        let relPath: String
        if let baseURL = baseURL {
            relPath = relativePath(of: fileURL, relativeTo: baseURL)
        } else {
            relPath = fileURL.lastPathComponent
        }
        let visitor = CodeChunkerVisitor(filePath: relPath, leafName: fileURL.lastPathComponent, converter: converter)
        visitor.walk(sourceFile)
        return visitor.chunks
    }
}
