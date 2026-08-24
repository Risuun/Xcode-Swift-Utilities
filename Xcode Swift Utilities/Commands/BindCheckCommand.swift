// BindCheckCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

private class ModelPropertyExtractor: SyntaxVisitor {
    var mutableProperties: [String] = []
    private var isInsideModelDecl: Bool = false
    private var foundAnyModelAttribute: Bool = false
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func hasModelAttribute(attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Model" {
                    return true
                }
            }
        }
        return false
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isModel = hasModelAttribute(attributes: node.attributes)
        if isModel {
            foundAnyModelAttribute = true
            isInsideModelDecl = true
            return .visitChildren
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        isInsideModelDecl = false
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let isModel = hasModelAttribute(attributes: node.attributes)
        if isModel {
            foundAnyModelAttribute = true
            isInsideModelDecl = true
            return .visitChildren
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        isInsideModelDecl = false
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let modifiers = node.modifiers.trimmedDescription
        if modifiers.contains("static") || modifiers.contains("class") {
            return .skipChildren
        }
        
        if node.bindingSpecifier.text == "let" {
            return .skipChildren
        }
        
        for binding in node.bindings {
            if let accessorBlock = binding.accessorBlock {
                switch accessorBlock.accessors {
                case .getter:
                    continue
                case .accessors(let list):
                    let hasSetter = list.contains { $0.accessorSpecifier.text == "set" }
                    if !hasSetter {
                        continue
                    }
                }
            }
            
            let propName = binding.pattern.trimmedDescription
            if !propName.isEmpty && !mutableProperties.contains(propName) {
                mutableProperties.append(propName)
            }
        }
        return .skipChildren
    }
}

private class ViewIdentifierCollector: SyntaxVisitor {
    var identifiers: Set<String> = []
    private var isInsideView: Bool = false
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let conformsToView = node.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == "View" } ?? false
        if conformsToView {
            isInsideView = true
            return .visitChildren
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        isInsideView = false
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.baseName.text)
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }
    
    override func visit(_ node: KeyPathPropertyComponentSyntax) -> SyntaxVisitorContinueKind {
        identifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }
}

public func runBindCheck(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap bind-check --model-path <path> --view-path <path>")
        exit(0)
    }
    
    var modelPath: String? = nil
    var viewPath: String? = nil
    var positional: [String] = []
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--model-path" || arg == "--model" || arg == "-m" {
            if idx + 1 < args.count {
                modelPath = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--model-path=") {
            modelPath = String(arg.dropFirst("--model-path=".count))
        } else if arg == "--view-path" || arg == "--view" || arg == "-v" {
            if idx + 1 < args.count {
                viewPath = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--view-path=") {
            viewPath = String(arg.dropFirst("--view-path=".count))
        } else if !arg.hasPrefix("-") {
            positional.append(arg)
        }
        idx += 1
    }
    
    if modelPath == nil && positional.count > 0 {
        modelPath = positional[0]
    }
    if viewPath == nil && positional.count > 1 {
        viewPath = positional[1]
    }
    
    guard let mPath = modelPath, let vPath = viewPath else {
        fputs("Usage: XCSwiftMap bind-check --model-path <path> --view-path <path>\n", stderr)
        exit(1)
    }
    
    let sanitizedModel = sanitizePath(mPath)
    let sanitizedView = sanitizePath(vPath)
    
    let resolvedModelPath = resolveOrExitTarget(sanitizedModel)
    let resolvedViewPath = resolveOrExitTarget(sanitizedView)
    
    guard let modelContent = try? String(contentsOfFile: resolvedModelPath, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(sanitizedModel)]\n", stderr)
        exit(1)
    }
    guard let viewContent = try? String(contentsOfFile: resolvedViewPath, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(sanitizedView)]\n", stderr)
        exit(1)
    }
    
    // Extract mutable properties from model
    let modelAST = Parser.parse(source: modelContent)
    let modelExtractor = ModelPropertyExtractor(viewMode: .sourceAccurate)
    modelExtractor.walk(modelAST)
    
    // Extract identifier references from view
    let viewAST = Parser.parse(source: viewContent)
    let viewCollector = ViewIdentifierCollector(viewMode: .sourceAccurate)
    viewCollector.walk(viewAST)
    
    var missingBindings: [String] = []
    for prop in modelExtractor.mutableProperties {
        if !viewCollector.identifiers.contains(prop) {
            missingBindings.append(prop)
        }
    }
    
    if missingBindings.isEmpty {
        print("[OK: All model bindings present]")
    } else {
        for missing in missingBindings {
            print("[MISSING BINDING: \(missing)]")
        }
    }
}