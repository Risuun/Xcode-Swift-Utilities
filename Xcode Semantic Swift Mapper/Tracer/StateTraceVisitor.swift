import Foundation
import SwiftSyntax

public class ViewStateModel: Codable {
    public var name: String
    public var kind: String
    public var location: SourceLocationModel?
    public var variables: [StateVariableModel] = []
    
    public init(name: String, kind: String) {
        self.name = name
        self.kind = kind
    }
}

public struct StateVariableModel: Codable {
    public var wrapper: String
    public var name: String
    public var type: String
    public var location: SourceLocationModel?
    
    public init(wrapper: String, name: String, type: String, location: SourceLocationModel?) {
        self.wrapper = wrapper
        self.name = name
        self.type = type
        self.location = location
    }
}

public class StateTraceVisitor: SyntaxVisitor {
    public var views: [ViewStateModel] = []
    
    public var currentFilePath: String = ""
    public var currentLocationConverter: SourceLocationConverter? = nil
    
    private var currentView: ViewStateModel? = nil
    
    public override init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    private func getCurrentLocation(for node: SyntaxProtocol) -> SourceLocationModel? {
        guard let converter = currentLocationConverter else { return nil }
        let startLoc = node.startLocation(converter: converter)
        return SourceLocationModel(file: currentFilePath, line: startLoc.line)
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let model = ViewStateModel(name: name, kind: "struct")
        model.location = getCurrentLocation(for: node)
        views.append(model)
        currentView = model
        return .visitChildren
    }
    
    public override func visitPost(_ node: StructDeclSyntax) {
        currentView = nil
    }
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let model = ViewStateModel(name: name, kind: "class")
        model.location = getCurrentLocation(for: node)
        views.append(model)
        currentView = model
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        currentView = nil
    }
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let view = currentView else { return .skipChildren }
        
        var wrapperName: String? = nil
        for attribute in node.attributes {
            if case .attribute(let attr) = attribute {
                let name = attr.attributeName.trimmedDescription
                if name == "State" || name == "Binding" || name == "StateObject" || name == "ObservedObject" || name == "EnvironmentObject" || name == "Environment" || name == "Query" || name == "Model" {
                    wrapperName = name
                    break
                }
            }
        }
        
        if let wrapper = wrapperName {
            for binding in node.bindings {
                let name = binding.pattern.trimmedDescription
                let type = binding.typeAnnotation?.type.trimmedDescription ?? "Unknown"
                let prop = StateVariableModel(wrapper: wrapper, name: name, type: type, location: getCurrentLocation(for: node))
                view.variables.append(prop)
            }
        }
        
        return .skipChildren
    }
}
