// PackContextCommand.swift // Commands

import Foundation
import SwiftSyntax
import SwiftParser

public class PackContextVisitor: SyntaxVisitor {
    public var tokens: [String] = []
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func stripWhitespace(_ str: String) -> String {
        return str.filter { !$0.isWhitespace }
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        tokens.append("Struct:\(stripWhitespace(node.name.text))")
        return .visitChildren
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        tokens.append("Class:\(stripWhitespace(node.name.text))")
        return .visitChildren
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        tokens.append("Enum:\(stripWhitespace(node.name.text))")
        return .visitChildren
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        tokens.append("Actor:\(stripWhitespace(node.name.text))")
        return .visitChildren
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let name = stripWhitespace(binding.pattern.trimmedDescription)
            let type: String
            if let typeAnnotation = binding.typeAnnotation {
                type = stripWhitespace(typeAnnotation.type.trimmedDescription)
            } else if let initializer = binding.initializer {
                type = "Inferred(\(stripWhitespace(initializer.value.trimmedDescription)))"
            } else {
                type = "Inferred"
            }
            tokens.append("Var:\(name):\(type)")
        }
        return .visitChildren
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let funcName = stripWhitespace(node.name.text)
        
        let params = node.signature.parameterClause.parameters.map { param -> String in
            let label = param.firstName.text
            let name = param.secondName?.text ?? label
            let type = stripWhitespace(param.type.trimmedDescription)
            if label != name && label != "_" {
                return "\(label)\(name):\(type)"
            } else if label == "_" {
                return "\(name):\(type)"
            } else {
                return "\(name):\(type)"
            }
        }.joined(separator: ",")
        
        let returnType: String
        if let returnClause = node.signature.returnClause {
            returnType = stripWhitespace(returnClause.type.trimmedDescription)
        } else {
            returnType = "Void"
        }
        
        tokens.append("Func:\(funcName)(\(params))->\(returnType)")
        return .visitChildren
    }
}

public func runPackContext(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap pack-context <file-path>")
        exit(0)
    }
    
    guard !args.isEmpty else {
        fputs("Usage: XCSwiftMap pack-context <file-path>\n", stderr)
        exit(1)
    }
    
    let targetPath = args[0]
    let resolvedPath = resolveOrExitTarget(targetPath)
    let fileURL = URL(fileURLWithPath: resolvedPath)
    
    guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    let sourceFile = Parser.parse(source: fileContent)
    let visitor = PackContextVisitor(viewMode: .sourceAccurate)
    visitor.walk(sourceFile)
    
    if visitor.tokens.isEmpty {
        print("[OK: No AST declarations found in \(fileURL.lastPathComponent)]")
    } else {
        print(visitor.tokens.joined(separator: "|"))
    }
}
