import Foundation
import SwiftSyntax

public struct MemoryViolation: Codable {
    public var location: SourceLocationModel
    
    public init(location: SourceLocationModel) {
        self.location = location
    }
}

public class SelfReferenceFinder: SyntaxVisitor {
    public var foundSelf = false
    
    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if node.baseName.text == "self" {
            foundSelf = true
            return .skipChildren
        }
        return .visitChildren
    }
}

public class MemoryAuditVisitor: SyntaxVisitor {
    public var violations: [MemoryViolation] = []
    
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    
    private var classStackCount = 0
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func getCurrentLocation(for node: SyntaxProtocol) -> SourceLocationModel? {
        guard let converter = currentLocationConverter else { return nil }
        let startLoc = node.startLocation(converter: converter)
        return SourceLocationModel(file: currentFilePath, line: startLoc.line)
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        classStackCount += 1
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        classStackCount -= 1
    }
    
    public override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // Only target reference types (class declarations) to prevent false positives in structs
        guard classStackCount > 0 else {
            return .visitChildren
        }
        
        let finder = SelfReferenceFinder(viewMode: .sourceAccurate)
        finder.walk(node.statements)
        
        if finder.foundSelf {
            if !capturesSelfWeaklyOrUnownedly(node) {
                if let loc = getCurrentLocation(for: node) {
                    violations.append(MemoryViolation(location: loc))
                }
            }
        }
        
        return .visitChildren
    }
    
    private func capturesSelfWeaklyOrUnownedly(_ node: ClosureExprSyntax) -> Bool {
        guard let captureList = node.signature?.capture else {
            return false
        }
        for item in captureList.items {
            let desc = item.trimmedDescription
            if desc.contains("self") && (desc.contains("weak") || desc.contains("unowned")) {
                return true
            }
        }
        return false
    }
}
