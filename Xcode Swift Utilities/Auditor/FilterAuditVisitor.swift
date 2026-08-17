// FilterAuditVisitor.swift // Auditor

import Foundation
import SwiftSyntax
import SwiftParser

public struct FilterAuditResult: Codable {
    public var file: String
    public var line: Int
    public var kind: String
    public var model: String
    public var condition: String
    
    public init(file: String, line: Int, kind: String, model: String, condition: String) {
        self.file = file
        self.line = line
        self.kind = kind
        self.model = model
        self.condition = condition
    }
}

public class FilterAuditVisitor: SyntaxVisitor {
    public var targetModel: String = ""
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    public var results: [FilterAuditResult] = []
    
    private var recordedLines: Set<Int> = []
    private var enclosingTypes: [String] = []
    
    public init(viewMode: SyntaxTreeViewMode, targetModel: String = "") {
        self.targetModel = targetModel
        super.init(viewMode: viewMode)
    }
    
    public func resetForNewFile(filePath: String, converter: SourceLocationConverter) {
        self.currentFilePath = filePath
        self.currentLocationConverter = converter
        self.recordedLines.removeAll()
        self.enclosingTypes.removeAll()
    }
    
    private func recordMatch(kind: String, model: String, condition: String, node: SyntaxProtocol) {
        guard let converter = currentLocationConverter else { return }
        let startLoc = node.startLocation(converter: converter)
        let line = startLoc.line
        guard !recordedLines.contains(line) else { return }
        recordedLines.insert(line)
        
        let cleanedCondition = condition
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        results.append(FilterAuditResult(
            file: currentFilePath,
            line: line,
            kind: kind,
            model: model,
            condition: cleanedCondition
        ))
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enclosingTypes.append(node.name.text)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        if !enclosingTypes.isEmpty { enclosingTypes.removeLast() }
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enclosingTypes.append(node.name.text)
        return .visitChildren
    }
    
    public override func visitPost(_ node: StructDeclSyntax) {
        if !enclosingTypes.isEmpty { enclosingTypes.removeLast() }
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let modelLower = targetModel.lowercased()
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Query" {
                    let attrDesc = attr.trimmedDescription
                    var inferredModel = targetModel
                    
                    for binding in node.bindings {
                        if let typeAnnotation = binding.typeAnnotation {
                            let baseType = getBaseTypeName(from: typeAnnotation.type.trimmedDescription)
                            if !baseType.isEmpty {
                                inferredModel = baseType
                            }
                        }
                    }
                    
                    let matchesModel = targetModel.isEmpty
                        || inferredModel.lowercased().contains(modelLower)
                        || attrDesc.lowercased().contains(modelLower)
                        || node.trimmedDescription.lowercased().contains(modelLower)
                    
                    if matchesModel {
                        var condition = attrDesc
                        if let args = attr.arguments {
                            condition = args.trimmedDescription
                        }
                        recordMatch(kind: "@Query", model: inferredModel, condition: condition, node: node)
                    }
                }
            }
        }
        return .visitChildren
    }
    
    public override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        let modelLower = targetModel.lowercased()
        if node.macroName.text == "Predicate" {
            var predicateModel = targetModel
            var matched = targetModel.isEmpty
            
            if let genericClause = node.genericArgumentClause {
                for arg in genericClause.arguments {
                    let argType = arg.argument.trimmedDescription
                    predicateModel = argType
                    if targetModel.isEmpty || argType.lowercased().contains(modelLower) {
                        matched = true
                        break
                    }
                }
            }
            
            if !matched && node.trimmedDescription.lowercased().contains(modelLower) {
                matched = true
            }
            
            if matched {
                let condition: String
                if let trailing = node.trailingClosure {
                    condition = trailing.trimmedDescription
                } else if let firstArg = node.arguments.first {
                    condition = firstArg.expression.trimmedDescription
                } else {
                    condition = node.trimmedDescription
                }
                recordMatch(kind: "#Predicate<\(predicateModel)>", model: predicateModel, condition: condition, node: node)
            }
        }
        return .visitChildren
    }
    
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "filter" else {
            return .visitChildren
        }
        
        let modelLower = targetModel.lowercased()
        let baseDesc = memberAccess.base?.trimmedDescription ?? ""
        let fullCallDesc = node.trimmedDescription
        
        var matches = targetModel.isEmpty
        var matchedModel = targetModel
        
        if !matches {
            if baseDesc.lowercased().contains(modelLower) {
                matches = true
            } else if let trailing = node.trailingClosure {
                if let sig = trailing.signature, sig.trimmedDescription.lowercased().contains(modelLower) {
                    matches = true
                } else if trailing.statements.trimmedDescription.lowercased().contains(modelLower) {
                    matches = true
                }
            } else if fullCallDesc.lowercased().contains(modelLower) {
                matches = true
            }
        }
        
        if matchedModel.isEmpty {
            matchedModel = baseDesc.isEmpty ? "Collection" : baseDesc
        }
        
        if matches {
            let condition: String
            if let trailing = node.trailingClosure {
                condition = trailing.trimmedDescription
            } else if let firstArg = node.arguments.first {
                condition = firstArg.expression.trimmedDescription
            } else {
                condition = fullCallDesc
            }
            recordMatch(kind: "Collection.filter", model: matchedModel, condition: condition, node: node)
        }
        
        return .visitChildren
    }
}

public func runAuditFilters(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap audit-filters --model <ModelName> [directory-or-file-path] [--json]")
        exit(0)
    }
    
    var isJSON = false
    var modelName: String? = nil
    var path: String = "."
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg == "--model" || arg == "-m" {
            idx += 1
            if idx < args.count {
                modelName = args[idx]
            }
        } else if arg.hasPrefix("--model=") {
            modelName = String(arg.dropFirst("--model=".count))
        } else if !arg.hasPrefix("-") {
            path = arg
        } else {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        }
        idx += 1
    }
    
    guard let targetModel = modelName, !targetModel.isEmpty else {
        fputs("Usage: XCSwiftMap audit-filters --model <ModelName> [directory-or-file-path] [--json]\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: path, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(path)]\n", stderr)
        exit(1)
    }
    
    let visitor = FilterAuditVisitor(viewMode: .sourceAccurate, targetModel: targetModel)
    let baseURL = URL(fileURLWithPath: path)
    
    for fileURL in swiftFiles {
        if let content = try? String(contentsOfFile: fileURL.path, encoding: .utf8) {
            let sourceFile = Parser.parse(source: content)
            let relPath = relativePath(of: fileURL, relativeTo: baseURL)
            let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
            visitor.resetForNewFile(filePath: relPath, converter: converter)
            visitor.walk(sourceFile)
        }
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(visitor.results), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    } else {
        if visitor.results.isEmpty {
            print("[OK: 0 filters found for \(targetModel)]")
        } else {
            // Formatted clean tabular output
            var locWidth = 8      // "Location"
            var kindWidth = 4     // "Kind"
            var modelWidth = 5    // "Model"
            
            var rowData: [(loc: String, kind: String, model: String, cond: String)] = []
            for item in visitor.results {
                let leaf = URL(fileURLWithPath: item.file).lastPathComponent
                let loc = "\(leaf):\(item.line)"
                locWidth = max(locWidth, loc.count)
                kindWidth = max(kindWidth, item.kind.count)
                modelWidth = max(modelWidth, item.model.count)
                rowData.append((loc: loc, kind: item.kind, model: item.model, cond: item.condition))
            }
            
            let headerLoc = "Location".padding(toLength: locWidth, withPad: " ", startingAt: 0)
            let headerKind = "Kind".padding(toLength: kindWidth, withPad: " ", startingAt: 0)
            let headerModel = "Model".padding(toLength: modelWidth, withPad: " ", startingAt: 0)
            
            print("\(headerLoc) | \(headerKind) | \(headerModel) | Filter Condition")
            let divider = "\(String(repeating: "-", count: locWidth))+-+\(String(repeating: "-", count: kindWidth))+-+\(String(repeating: "-", count: modelWidth))+-+----------------------------------------"
            print(divider)
            
            for row in rowData {
                let pLoc = row.loc.padding(toLength: locWidth, withPad: " ", startingAt: 0)
                let pKind = row.kind.padding(toLength: kindWidth, withPad: " ", startingAt: 0)
                let pModel = row.model.padding(toLength: modelWidth, withPad: " ", startingAt: 0)
                print("\(pLoc) | \(pKind) | \(pModel) | \(row.cond)")
            }
        }
    }
}
