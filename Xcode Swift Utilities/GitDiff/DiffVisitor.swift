// DiffVisitor.swift // GitDiff

import Foundation
import SwiftSyntax

public class DeclarationCollector: SyntaxVisitor {
    public var rootNodes: [DiffNode] = []
    private var nodeStack: [DiffNode] = []
    private var locationConverter: SourceLocationConverter
    
    public init(viewMode: SyntaxTreeViewMode, locationConverter: SourceLocationConverter) {
        self.locationConverter = locationConverter
        super.init(viewMode: viewMode)
    }
    
    private func pushNode(kind: String, name: String, syntax: SyntaxProtocol) {
        let start = syntax.startLocation(converter: locationConverter).line
        let end = syntax.endLocation(converter: locationConverter).line
        let node = DiffNode(kind: kind, name: name, lineRange: start...end)
        
        if let parent = nodeStack.last {
            parent.children.append(node)
        } else {
            rootNodes.append(node)
        }
        nodeStack.append(node)
    }
    
    private func popNode() {
        _ = nodeStack.popLast()
    }
    
    // MARK: - Types
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "class", name: "\(accessStr)class \(node.name.text)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: ClassDeclSyntax) { popNode() }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "struct", name: "\(accessStr)struct \(node.name.text)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: StructDeclSyntax) { popNode() }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "enum", name: "\(accessStr)enum \(node.name.text)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: EnumDeclSyntax) { popNode() }
    
    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "protocol", name: "\(accessStr)protocol \(node.name.text)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: ProtocolDeclSyntax) { popNode() }
    
    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushNode(kind: "extension", name: "extension \(node.extendedType.trimmedDescription)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: ExtensionDeclSyntax) { popNode() }
    
    // MARK: - Functions & Initializers
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let signature = "\(node.name.text)\(node.signature.trimmedDescription)"
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "func", name: "\(accessStr)func \(signature)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: FunctionDeclSyntax) { popNode() }
    
    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let signature = "init\(node.signature.trimmedDescription)"
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "init", name: "\(accessStr)\(signature)", syntax: node)
        return .visitChildren
    }
    public override func visitPost(_ node: InitializerDeclSyntax) { popNode() }
    
    // MARK: - Properties & Enum Cases
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.bindings.compactMap { $0.pattern.trimmedDescription }.joined(separator: ", ")
        let typeStr = node.bindings.first?.typeAnnotation?.type.trimmedDescription ?? ""
        let fullType = typeStr.isEmpty ? "" : ": \(typeStr)"
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        let bindingSpec = node.bindingSpecifier.text
        pushNode(kind: "var", name: "\(accessStr)\(bindingSpec) \(names)\(fullType)", syntax: node)
        return .skipChildren
    }
    public override func visitPost(_ node: VariableDeclSyntax) { popNode() }
    
    public override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let elements = node.elements.map { $0.trimmedDescription }.joined(separator: ", ")
        pushNode(kind: "case", name: "case \(elements)", syntax: node)
        return .skipChildren
    }
    public override func visitPost(_ node: EnumCaseDeclSyntax) { popNode() }
}

public func filterNode(_ node: DiffNode, modifiedLines: Set<Int>) -> DiffNode? {
    let directHit = node.lineRange.contains { modifiedLines.contains($0) }
    
    var filteredChildren: [DiffNode] = []
    for child in node.children {
        if let filteredChild = filterNode(child, modifiedLines: modifiedLines) {
            filteredChildren.append(filteredChild)
        }
    }
    
    if directHit || !filteredChildren.isEmpty {
        let newNode = DiffNode(kind: node.kind, name: node.name, lineRange: node.lineRange)
        newNode.children = filteredChildren
        return newNode
    }
    
    return nil
}

public func parseGitDiffOutput(_ diffOutput: String) -> [FileDiff] {
    var diffs: [FileDiff] = []
    let lines = diffOutput.components(separatedBy: "\n")
    
    var currentFile: String?
    var currentLines = Set<Int>()
    
    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.hasPrefix("+++ b/") {
            if let file = currentFile, !currentLines.isEmpty {
                diffs.append(FileDiff(filepath: file, modifiedLines: currentLines))
            }
            currentFile = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            currentLines = Set<Int>()
        } else if trimmedLine.hasPrefix("@@") {
            let parts = trimmedLine.components(separatedBy: " ")
            if parts.count >= 3 {
                let newRangePart = parts[2]
                if newRangePart.hasPrefix("+") {
                    let rangeStr = newRangePart.dropFirst()
                    let rangeParts = rangeStr.components(separatedBy: ",")
                    if let startLine = Int(rangeParts[0]) {
                        let count = rangeParts.count > 1 ? (Int(rangeParts[1]) ?? 1) : 1
                        if count > 0 {
                            for l in startLine..<(startLine + count) {
                                currentLines.insert(l)
                            }
                        } else {
                            currentLines.insert(startLine)
                        }
                    }
                }
            }
        }
    }
    
    if let file = currentFile, !currentLines.isEmpty {
        diffs.append(FileDiff(filepath: file, modifiedLines: currentLines))
    }
    
    return diffs.filter { $0.filepath.hasSuffix(".swift") }
}

public func convertToModelNode(_ node: DiffNode) -> DiffNodeModel {
    let childrenModels = node.children.map { convertToModelNode($0) }
    let rangeStr = "\(node.lineRange.lowerBound)-\(node.lineRange.upperBound)"
    return DiffNodeModel(kind: node.kind, name: node.name, lineRange: rangeStr, children: childrenModels)
}

public func printDiffTree(node: DiffNode, indent: String = "") {
    print("\(indent)└── \(node.name)")
    let nextIndent = indent + "    "
    for child in node.children {
        printDiffTree(node: child, indent: nextIndent)
    }
}
