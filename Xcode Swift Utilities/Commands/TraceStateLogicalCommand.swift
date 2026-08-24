// TraceStateLogicalCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

public class StatePropertyInfo {
    public let name: String
    public let wrapper: String
    public let type: String
    public var steps: [String] = ["Init"]
    
    public init(name: String, wrapper: String, type: String) {
        self.name = name
        self.wrapper = wrapper
        self.type = type
    }
}

public class TraceStateLogicalVisitor: SyntaxVisitor {
    public var stateProperties: [String: StatePropertyInfo] = [:]
    public var propertyOrder: [String] = []
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        var wrapperName: String? = nil
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                let name = attr.attributeName.trimmedDescription
                if name == "State" || name == "Binding" || name == "Environment" {
                    wrapperName = name
                    break
                }
            }
        }
        
        if let wrapper = wrapperName {
            for binding in node.bindings {
                let varName = binding.pattern.trimmedDescription
                let type = binding.typeAnnotation?.type.trimmedDescription ?? "Implicit"
                if stateProperties[varName] == nil {
                    let info = StatePropertyInfo(name: varName, wrapper: wrapper, type: type)
                    stateProperties[varName] = info
                    propertyOrder.append(varName)
                }
            }
        }
        return .visitChildren
    }
    
    private func getContextName(from node: SyntaxProtocol) -> String {
        var current: Syntax? = node.parent
        while let p = current {
            if let call = p.as(FunctionCallExprSyntax.self) {
                let callee = call.calledExpression.trimmedDescription
                if callee == "Button" || callee.hasSuffix(".Button") {
                    return "Button Action"
                }
                if callee.hasSuffix(".onChange") {
                    return "onChange"
                }
                if callee.hasSuffix(".task") {
                    return "task"
                }
                if callee.hasSuffix(".onAppear") {
                    return "onAppear"
                }
            } else if let funcDecl = p.as(FunctionDeclSyntax.self) {
                return "\(funcDecl.name.text)()"
            }
            current = p.parent
        }
        return "Action"
    }
    
    private func extractVarName(from expr: ExprSyntax) -> String? {
        let trimmed = expr.trimmedDescription
        if let prop = stateProperties.keys.first(where: { trimmed == $0 || trimmed == "self.\($0)" }) {
            return prop
        }
        return nil
    }
    
    private func isAssignmentOperator(_ text: String) -> Bool {
        return text == "=" || text == "+=" || text == "-=" || text == "*=" || text == "/="
    }
    
    public override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        if let parentSeq = node.parent?.as(SequenceExprSyntax.self) {
            let elements = Array(parentSeq.elements)
            if let idx = elements.firstIndex(where: { $0.id == node.id }), idx > 0 {
                if let varName = extractVarName(from: elements[idx - 1]), let info = stateProperties[varName] {
                    let context = getContextName(from: node)
                    let step = "Mutated in \(context)"
                    info.steps.append(step)
                }
            }
        }
        return .visitChildren
    }
    
    public override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let op = node.operator.as(BinaryOperatorExprSyntax.self) {
            if isAssignmentOperator(op.operator.text) {
                if let varName = extractVarName(from: node.leftOperand), let info = stateProperties[varName] {
                    let context = getContextName(from: node)
                    let step = "Mutated in \(context)"
                    info.steps.append(step)
                }
            }
        } else if node.operator.is(AssignmentExprSyntax.self) {
            if let varName = extractVarName(from: node.leftOperand), let info = stateProperties[varName] {
                let context = getContextName(from: node)
                let step = "Mutated in \(context)"
                info.steps.append(step)
            }
        }
        return .visitChildren
    }
    
    public override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        for (idx, elem) in elements.enumerated() {
            var isAssign = false
            if elem.is(AssignmentExprSyntax.self) {
                isAssign = true
            } else if let op = elem.as(BinaryOperatorExprSyntax.self), isAssignmentOperator(op.operator.text) {
                isAssign = true
            }
            
            if isAssign && idx > 0 {
                if let varName = extractVarName(from: elements[idx - 1]), let info = stateProperties[varName] {
                    let context = getContextName(from: node)
                    let step = "Mutated in \(context)"
                    info.steps.append(step)
                }
            }
        }
        return .visitChildren
    }
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calleeName = node.calledExpression.trimmedDescription
        
        for arg in node.arguments {
            let argText = arg.expression.trimmedDescription
            for (varName, info) in stateProperties {
                if argText == varName || argText == "$\(varName)" || argText == "self.\(varName)" || argText == "$self.\(varName)" {
                    let step = "Passed to \(calleeName)"
                    info.steps.append(step)
                }
            }
        }
        return .visitChildren
    }
}

public func runTraceStateLogical(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap trace-state-logical <file-path>")
        exit(0)
    }
    
    guard !args.isEmpty else {
        fputs("Usage: XCSwiftMap trace-state-logical <file-path>\n", stderr)
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
    let visitor = TraceStateLogicalVisitor(viewMode: .sourceAccurate)
    visitor.walk(sourceFile)
    
    if visitor.propertyOrder.isEmpty {
        print("[OK: No @State, @Binding, or @Environment properties in \(fileURL.lastPathComponent)]")
    } else {
        for varName in visitor.propertyOrder {
            if let info = visitor.stateProperties[varName] {
                let sequence = info.steps.joined(separator: " -> ")
                print("@\(info.wrapper) var \(info.name): \(sequence)")
            }
        }
    }
}
