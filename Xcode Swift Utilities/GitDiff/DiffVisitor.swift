// DiffVisitor.swift // Xcode Swift Utilities

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
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "class", name: "\(accessStr)class \(node.name.text)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "struct", name: "\(accessStr)struct \(node.name.text)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: StructDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "enum", name: "\(accessStr)enum \(node.name.text)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: EnumDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "protocol", name: "\(accessStr)protocol \(node.name.text)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ProtocolDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "actor", name: "\(accessStr)actor \(node.name.text)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ActorDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "extension", name: "\(accessStr)extension \(node.extendedType.trimmedDescription)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ExtensionDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let access = node.modifiers.trimmedDescription
        let accessStr = access.isEmpty ? "" : "\(access) "
        pushNode(kind: "function", name: "\(accessStr)func \(node.name.text)\(node.signature.trimmedDescription)", syntax: node)
        return .visitChildren
    }
    
    public override func visitPost(_ node: FunctionDeclSyntax) {
        popNode()
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if let parent = nodeStack.last {
            if parent.kind != "function" {
                let access = node.modifiers.trimmedDescription
                let accessStr = access.isEmpty ? "" : "\(access) "
                let specifier = node.bindingSpecifier.text
                let names = node.bindings.map { $0.pattern.trimmedDescription }.joined(separator: ", ")
                let type = node.bindings.first?.typeAnnotation?.type.trimmedDescription
                let typeStr = type.map { ": \($0)" } ?? ""
                pushNode(kind: "variable", name: "\(accessStr)\(specifier) \(names)\(typeStr)", syntax: node)
                popNode()
            }
        }
        return .skipChildren
    }
}

public func filterNode(_ node: DiffNode, modifiedLines: Set<Int>) -> DiffNode? {
    let nodeRange = node.lineRange
    let intersects = modifiedLines.contains { nodeRange.contains($0) }
    
    if !intersects {
        return nil
    }
    
    var filteredChildren: [DiffNode] = []
    for child in node.children {
        if let filteredChild = filterNode(child, modifiedLines: modifiedLines) {
            filteredChildren.append(filteredChild)
        }
    }
    
    let newNode = DiffNode(kind: node.kind, name: node.name, lineRange: node.lineRange)
    newNode.children = filteredChildren
    return newNode
}

public func runGitDiffProcess(args: [String], workspacePath: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = URL(fileURLWithPath: workspacePath)
    
    var gitArgs = ["diff", "-U0"]
    if let branchIdx = args.firstIndex(of: "--branch") {
        if branchIdx + 1 < args.count {
            gitArgs.append(args[branchIdx + 1])
        }
    } else if let branchArg = args.first(where: { $0.hasPrefix("--branch=") }) {
        gitArgs.append(String(branchArg.dropFirst(9)))
    } else {
        for arg in args {
            if !arg.hasPrefix("-") {
                gitArgs.append(arg)
            }
        }
    }
    
    process.arguments = gitArgs
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

public func parseGitDiffOutput(_ output: String) -> [FileDiff] {
    var diffs: [FileDiff] = []
    var currentFile: String? = nil
    var currentLines = Set<Int>()
    
    let lines = output.components(separatedBy: .newlines)
    for line in lines {
        if line.hasPrefix("diff --git a/") {
            if let file = currentFile, !currentLines.isEmpty {
                diffs.append(FileDiff(filepath: file, modifiedLines: currentLines))
            }
            currentLines = Set<Int>()
            currentFile = nil
            
            let remainder = line.dropFirst(13)
            let parts = remainder.components(separatedBy: " b/")
            if parts.count >= 2 {
                let bPath = parts[0]
                if bPath.hasSuffix(".swift") {
                    currentFile = String(bPath)
                }
            }
        } else if line.hasPrefix("@@ ") {
            let parts = line.components(separatedBy: " ")
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
    
    return diffs
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
