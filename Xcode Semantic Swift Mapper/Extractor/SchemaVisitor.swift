import Foundation
import SwiftSyntax

public class SchemaVisitor: SyntaxVisitor {
    public var models: [SchemaModel] = []
    public var queries: [SchemaQuery] = []
    
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    
    private var currentModel: SchemaModel? = nil
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func getCurrentLocation(for node: SyntaxProtocol) -> SourceLocationModel? {
        guard let converter = currentLocationConverter else { return nil }
        let startLoc = node.startLocation(converter: converter)
        return SourceLocationModel(file: currentFilePath, line: startLoc.line)
    }
    
    private func hasModelMacro(_ node: ClassDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Model" {
                    return true
                }
            }
        }
        return false
    }
    
    private func hasQueryAttribute(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                if attr.attributeName.trimmedDescription == "Query" {
                    return true
                }
            }
        }
        return false
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasModelMacro(node) {
            let model = SchemaModel(name: node.name.text)
            model.location = getCurrentLocation(for: node)
            models.append(model)
            currentModel = model
            return .visitChildren
        }
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        if hasModelMacro(node) {
            currentModel = nil
        }
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = getCurrentLocation(for: node)
        
        // 1. Check for Query
        if hasQueryAttribute(node) {
            for binding in node.bindings {
                let name = binding.pattern.trimmedDescription
                let type = binding.typeAnnotation?.type.trimmedDescription ?? ""
                let query = SchemaQuery(name: name, type: type, location: location)
                queries.append(query)
            }
            return .skipChildren
        }
        
        // 2. If inside a model, check if it's a stored property
        if let model = currentModel {
            let modifiers = node.modifiers.trimmedDescription
            if modifiers.contains("static") || modifiers.contains("class") {
                return .skipChildren
            }
            
            for binding in node.bindings {
                if binding.accessorBlock != nil {
                    continue // computed property
                }
                let name = binding.pattern.trimmedDescription
                let type = binding.typeAnnotation?.type.trimmedDescription ?? ""
                let prop = SchemaProperty(name: name, type: type, location: location)
                model.properties.append(prop)
            }
            return .skipChildren
        }
        
        return .skipChildren
    }
}
