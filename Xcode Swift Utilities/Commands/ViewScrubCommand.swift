// ViewScrubCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

public final class ViewScrubHelper {
    public static let knownStylingModifiers: Set<String> = [
        "padding", "font", "fontWeight", "bold", "italic", "underline", "strikethrough",
        "background", "backgroundStyle", "foregroundStyle", "foregroundColor", "tint", "accentColor",
        "frame", "fixedSize", "layoutPriority", "opacity", "hidden", "clipped", "clipShape",
        "cornerRadius", "shadow", "border", "overlay", "offset", "position", "scaleEffect",
        "rotationEffect", "aspectRatio", "scaledToFit", "scaledToFill", "lineLimit",
        "multilineTextAlignment", "truncationMode", "allowsHitTesting", "disabled",
        "interactiveDismissDisabled", "badge", "listRowBackground", "listRowInsets",
        "listRowSeparator", "listStyle", "pickerStyle", "buttonStyle", "toggleStyle",
        "textFieldStyle", "controlSize", "labelsHidden", "navigationTitle", "navigationBarTitleDisplayMode",
        "toolbar", "toolbarBackground", "toolbarColorScheme", "sheet", "fullScreenCover",
        "popover", "alert", "confirmationDialog", "task", "onAppear", "onDisappear",
        "onChange", "onSubmit", "refreshable", "searchable", "animation", "transition",
        "tag", "id", "sensoryFeedback", "help", "accessibilityLabel", "accessibilityHint"
    ]
    
    /// Unwraps chained styling modifier calls to find the base structural view expression.
    public static func unwrapModifiers(from expr: ExprSyntax) -> ExprSyntax {
        if let call = expr.as(FunctionCallExprSyntax.self) {
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                let modifierName = member.declName.baseName.text
                if let base = member.base {
                    if knownStylingModifiers.contains(modifierName) {
                        return unwrapModifiers(from: base)
                    }
                }
            }
        } else if let member = expr.as(MemberAccessExprSyntax.self) {
            let memberName = member.declName.baseName.text
            if let base = member.base {
                if knownStylingModifiers.contains(memberName) {
                    return unwrapModifiers(from: base)
                }
            }
        }
        return expr
    }
}

public class ViewScrubVisitor: SyntaxVisitor {
    private var indentLevel: Int = 0
    
    public init(viewMode: SyntaxTreeViewMode, indentLevel: Int = 0) {
        self.indentLevel = indentLevel
        super.init(viewMode: viewMode)
    }
    
    private func printIndented(_ text: String) {
        let indent = String(repeating: "    ", count: indentLevel)
        print("\(indent)\(text)")
    }
    
    public func scrubAndPrint(expr: ExprSyntax) {
        let unwrapped = ViewScrubHelper.unwrapModifiers(from: expr)
        
        if let call = unwrapped.as(FunctionCallExprSyntax.self) {
            if let trailingClosure = call.trailingClosure {
                // Structural node with trailing closure: e.g. VStack { ... } or ForEach(items) { item in ... }
                let calleeWithoutClosure = getCallSignatureWithoutTrailingClosure(call)
                printIndented("\(calleeWithoutClosure) {")
                indentLevel += 1
                for stmt in trailingClosure.statements {
                    if let childExpr = stmt.item.as(ExprSyntax.self) {
                        scrubAndPrint(expr: childExpr)
                    } else {
                        printIndented(stmt.item.trimmedDescription)
                    }
                }
                indentLevel -= 1
                printIndented("}")
            } else {
                // Leaf view call: e.g. Text("Hello"), Image(systemName: "star")
                printIndented(call.trimmedDescription)
            }
        } else if let member = unwrapped.as(MemberAccessExprSyntax.self) {
            printIndented(member.trimmedDescription)
        } else if let declRef = unwrapped.as(DeclReferenceExprSyntax.self) {
            printIndented(declRef.baseName.text)
        } else {
            printIndented(unwrapped.trimmedDescription)
        }
    }
    
    private func getCallSignatureWithoutTrailingClosure(_ call: FunctionCallExprSyntax) -> String {
        var baseText = call.calledExpression.trimmedDescription
        let args = call.arguments.trimmedDescription
        if !args.isEmpty {
            baseText += "(\(args))"
        }
        return baseText
    }
}

public class ViewScrubFinder: SyntaxVisitor {
    public var hasFoundView: Bool = false
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let conformsToView = node.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == "View" } ?? false
        if conformsToView {
            return .visitChildren
        }
        return .visitChildren
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isBody = node.bindings.contains { $0.pattern.trimmedDescription == "body" }
        if isBody {
            for binding in node.bindings {
                if let accessorBlock = binding.accessorBlock {
                    hasFoundView = true
                    let scrubber = ViewScrubVisitor(viewMode: .sourceAccurate)
                    switch accessorBlock.accessors {
                    case .getter(let codeBlocks):
                        for stmt in codeBlocks {
                            if let expr = stmt.item.as(ExprSyntax.self) {
                                scrubber.scrubAndPrint(expr: expr)
                            }
                        }
                    case .accessors(let accessorList):
                        for accessor in accessorList {
                            if let body = accessor.body {
                                for stmt in body.statements {
                                    if let expr = stmt.item.as(ExprSyntax.self) {
                                        scrubber.scrubAndPrint(expr: expr)
                                    }
                                }
                            }
                        }
                    }
                } else if let initializer = binding.initializer {
                    hasFoundView = true
                    let scrubber = ViewScrubVisitor(viewMode: .sourceAccurate)
                    scrubber.scrubAndPrint(expr: initializer.value)
                }
            }
            return .skipChildren
        }
        return .skipChildren
    }
}

public func runViewScrub(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap view-scrub <file-path>")
        exit(0)
    }
    
    guard !args.isEmpty else {
        fputs("Usage: XCSwiftMap view-scrub <file-path>\n", stderr)
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
    let finder = ViewScrubFinder(viewMode: .sourceAccurate)
    finder.walk(sourceFile)
    
    if !finder.hasFoundView {
        let leaf = fileURL.lastPathComponent
        fputs("[ERROR: No SwiftUI view body in \(leaf)]\n", stderr)
        exit(1)
    }
}