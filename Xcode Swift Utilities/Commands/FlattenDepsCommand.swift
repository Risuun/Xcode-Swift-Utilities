// FlattenDepsCommand.swift // Commands

import Foundation
import SwiftSyntax
import SwiftParser

private class FunctionCallExtractor: SyntaxVisitor {
    var calledNames: Set<String> = []
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledNames.insert(declRef.baseName.text)
        } else if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            calledNames.insert(member.declName.baseName.text)
        }
        return .visitChildren
    }
}

private class FunctionDefinitionCollector: SyntaxVisitor {
    var functions: [String: FunctionDeclSyntax] = [:]
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if functions[name] == nil {
            functions[name] = node
        }
        return .visitChildren
    }
}

public func runFlattenDeps(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap flatten-deps --symbol <symbol> [--directory <path>]")
        exit(0)
    }
    
    var symbol: String? = nil
    var directory: String = "."
    
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
        } else if arg == "--directory" || arg == "-d" {
            if idx + 1 < args.count {
                directory = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--directory=") {
            directory = String(arg.dropFirst("--directory=".count))
        } else if !arg.hasPrefix("-") {
            if symbol == nil {
                symbol = arg
            } else {
                directory = arg
            }
        }
        idx += 1
    }
    
    guard let targetSymbol = symbol, !targetSymbol.isEmpty else {
        fputs("Usage: XCSwiftMap flatten-deps --symbol <symbol> [--directory <path>]\n", stderr)
        exit(1)
    }
    
    let resolvedDir = resolveOrExitTarget(directory)
    let swiftFiles = findSwiftFiles(at: resolvedDir, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(directory)]\n", stderr)
        exit(1)
    }
    
    // Index all function definitions in the directory
    var allFunctions: [String: FunctionDeclSyntax] = [:]
    for fileURL in swiftFiles {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        let sourceFile = Parser.parse(source: content)
        let collector = FunctionDefinitionCollector(viewMode: .sourceAccurate)
        collector.walk(sourceFile)
        for (name, decl) in collector.functions {
            if allFunctions[name] == nil {
                allFunctions[name] = decl
            }
        }
    }
    
    guard let rootFunc = allFunctions[targetSymbol] else {
        fputs("[ERROR: Symbol not found: \(targetSymbol)]\n", stderr)
        exit(1)
    }
    
    // BFS resolve dependencies
    var queue: [String] = [targetSymbol]
    var visited: Set<String> = []
    var orderedFunctions: [FunctionDeclSyntax] = []
    
    while !queue.isEmpty {
        let currentName = queue.removeFirst()
        if visited.contains(currentName) { continue }
        visited.insert(currentName)
        
        guard let currentDecl = allFunctions[currentName] else { continue }
        orderedFunctions.append(currentDecl)
        
        if let body = currentDecl.body {
            let extractor = FunctionCallExtractor(viewMode: .sourceAccurate)
            extractor.walk(body)
            for call in extractor.calledNames {
                if allFunctions[call] != nil && !visited.contains(call) {
                    queue.append(call)
                }
            }
        }
    }
    
    let concatenated = orderedFunctions.map { $0.trimmedDescription }.joined(separator: "\n\n")
    print(concatenated)
}
