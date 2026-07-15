import Foundation
import SwiftSyntax

public func getBaseExpression(from expr: ExprSyntax) -> ExprSyntax {
    if let call = expr.as(FunctionCallExprSyntax.self) {
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if let base = memberAccess.base {
                return getBaseExpression(from: base)
            }
        }
    } else if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
        if let base = memberAccess.base {
            return getBaseExpression(from: base)
        }
    }
    return expr
}

public func getViewName(from expr: ExprSyntax) -> String? {
    let base = getBaseExpression(from: expr)
    if let call = base.as(FunctionCallExprSyntax.self) {
        return getViewName(from: call.calledExpression)
    } else if let declRef = base.as(DeclReferenceExprSyntax.self) {
        return declRef.baseName.text
    } else if let member = base.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text
    }
    return base.trimmedDescription
}

public class SkeletonVisitor: SyntaxVisitor {
    private var indentLevel = 0
    
    public init(viewMode: SyntaxTreeViewMode, indentLevel: Int = 0) {
        self.indentLevel = indentLevel
        super.init(viewMode: viewMode)
    }
    
    private func printWithIndent(_ text: String) {
        let indent = String(repeating: "    ", count: indentLevel)
        print("\(indent)\(text)")
    }
    
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let viewName = getViewName(from: ExprSyntax(node)) else {
            return .visitChildren
        }
        
        if let closure = node.trailingClosure {
            printWithIndent("\(viewName) {")
            indentLevel += 1
            for stmt in closure.statements {
                walk(stmt.item)
            }
            indentLevel -= 1
            printWithIndent("}")
            return .skipChildren
        } else {
            printWithIndent(viewName)
            return .skipChildren
        }
    }
}

public class ViewSkeletonFinder: SyntaxVisitor {
    public var hasFoundView = false
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let conformsToView = node.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == "View" } ?? false
        if conformsToView {
            return .visitChildren
        }
        return .skipChildren
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isBody = node.bindings.contains { $0.pattern.trimmedDescription == "body" }
        if isBody {
            for binding in node.bindings {
                if let accessorBlock = binding.accessorBlock {
                    hasFoundView = true
                    let skeletonVisitor = SkeletonVisitor(viewMode: .sourceAccurate)
                    skeletonVisitor.walk(accessorBlock)
                } else if let initializer = binding.initializer {
                    hasFoundView = true
                    let skeletonVisitor = SkeletonVisitor(viewMode: .sourceAccurate)
                    skeletonVisitor.walk(initializer)
                }
            }
            return .skipChildren
        }
        return .skipChildren
    }
}
