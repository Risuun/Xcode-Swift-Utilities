// SwiftMapVisitor.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax

public class SwiftMapVisitor: SyntaxVisitor {
    public var types: [TypeModel] = []
    public var properties: [PropertyModel] = []
    public var functions: [FunctionModel] = []
    public var typealiases: [TypealiasModel] = []
    
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    
    private var typeStack: [TypeModel] = []
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func addType(_ model: TypeModel) {
        if let parent = typeStack.last {
            parent.nestedTypes.append(model)
        } else {
            types.append(model)
        }
        typeStack.append(model)
    }
    
    private func popType() {
        _ = typeStack.popLast()
    }
    
    private func getCurrentLocation(for node: SyntaxProtocol) -> SourceLocationModel? {
        guard let converter = currentLocationConverter else { return nil }
        let startLoc = node.startLocation(converter: converter)
        return SourceLocationModel(file: currentFilePath, line: startLoc.line)
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "struct", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: StructDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "class", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "enum", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: EnumDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "protocol", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ProtocolDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "actor", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ActorDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.extendedType.trimmedDescription
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "extension", name: name, accessLevel: accessLevel, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        addType(model)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ExtensionDeclSyntax) {
        popType()
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let specifier = node.bindingSpecifier.text
        let location = getCurrentLocation(for: node)
        
        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            let type = binding.typeAnnotation?.type.trimmedDescription
            var model = PropertyModel(accessLevel: accessLevel, specifier: specifier, name: name, type: type)
            model.location = location
            
            if let currentType = typeStack.last {
                currentType.properties.append(model)
            } else {
                properties.append(model)
            }
        }
        return .skipChildren
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let signature = node.signature.trimmedDescription
        var model = FunctionModel(accessLevel: accessLevel, name: name, signature: signature)
        model.location = getCurrentLocation(for: node)
        
        if let currentType = typeStack.last {
            currentType.functions.append(model)
        } else {
            functions.append(model)
        }
        return .skipChildren
    }
    
    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let signature = node.signature.trimmedDescription
        var model = InitializerModel(accessLevel: accessLevel, signature: signature)
        model.location = getCurrentLocation(for: node)
        
        if let currentType = typeStack.last {
            currentType.initializers.append(model)
        }
        return .skipChildren
    }
    
    public override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let cases = node.elements.map { $0.trimmedDescription }
        if let currentType = typeStack.last {
            currentType.cases.append(contentsOf: cases)
        }
        return .skipChildren
    }
    
    public override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let underlyingType = node.initializer.value.trimmedDescription
        var model = TypealiasModel(accessLevel: accessLevel, name: name, underlyingType: underlyingType)
        model.location = getCurrentLocation(for: node)
        
        if let currentType = typeStack.last {
            currentType.typealiases.append(model)
        } else {
            typealiases.append(model)
        }
        return .skipChildren
    }
    
    public override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.trimmedDescription
        var model = AssociatedTypeModel(accessLevel: accessLevel, name: name, inheritance: inheritance)
        model.location = getCurrentLocation(for: node)
        
        if let currentType = typeStack.last {
            currentType.associatedtypes.append(model)
        }
        return .skipChildren
    }
}
