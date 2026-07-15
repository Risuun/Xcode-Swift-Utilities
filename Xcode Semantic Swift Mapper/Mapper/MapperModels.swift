import Foundation

public class TypeModel: Codable {
    public var kind: String // "struct", "class", "enum", "protocol", "actor", "extension"
    public var name: String
    public var accessLevel: String
    public var inheritance: [String]
    public var properties: [PropertyModel] = []
    public var functions: [FunctionModel] = []
    public var initializers: [InitializerModel] = []
    public var cases: [String] = []
    public var typealiases: [TypealiasModel] = []
    public var associatedtypes: [AssociatedTypeModel] = []
    public var nestedTypes: [TypeModel] = []
    public var location: SourceLocationModel?
    
    public init(kind: String, name: String, accessLevel: String, inheritance: [String]) {
        self.kind = kind
        self.name = name
        self.accessLevel = accessLevel
        self.inheritance = inheritance
    }
}

public struct PropertyModel: Codable {
    public var accessLevel: String
    public var specifier: String
    public var name: String
    public var type: String?
    public var location: SourceLocationModel?
}

public struct FunctionModel: Codable {
    public var accessLevel: String
    public var name: String
    public var signature: String
    public var location: SourceLocationModel?
}

public struct InitializerModel: Codable {
    public var accessLevel: String
    public var signature: String
    public var location: SourceLocationModel?
}

public struct TypealiasModel: Codable {
    public var accessLevel: String
    public var name: String
    public var underlyingType: String
    public var location: SourceLocationModel?
}

public struct AssociatedTypeModel: Codable {
    public var accessLevel: String
    public var name: String
    public var inheritance: String?
    public var location: SourceLocationModel?
}

public class SourceMap: Codable {
    public var types: [TypeModel] = []
    public var properties: [PropertyModel] = []
    public var functions: [FunctionModel] = []
    public var typealiases: [TypealiasModel] = []
    
    public init() {}
}

public func merge(_ source: TypeModel, into target: TypeModel) {
    target.properties.append(contentsOf: source.properties)
    target.functions.append(contentsOf: source.functions)
    target.initializers.append(contentsOf: source.initializers)
    target.cases.append(contentsOf: source.cases)
    target.typealiases.append(contentsOf: source.typealiases)
    target.associatedtypes.append(contentsOf: source.associatedtypes)
    
    for item in source.inheritance {
        if !target.inheritance.contains(item) {
            target.inheritance.append(item)
        }
    }
    
    for nestedSource in source.nestedTypes {
        if let existingTargetNested = target.nestedTypes.first(where: { $0.name == nestedSource.name }) {
            merge(nestedSource, into: existingTargetNested)
        } else {
            target.nestedTypes.append(nestedSource)
        }
    }
}

public func consolidateSourceMap(types: [TypeModel]) -> [TypeModel] {
    var primaryTypes: [String: TypeModel] = [:]
    var extensions: [TypeModel] = []
    
    func catalogTypes(_ typesList: [TypeModel], parentPath: String = "") {
        for type in typesList {
            let fqName = parentPath.isEmpty ? type.name : "\(parentPath).\(type.name)"
            if type.kind == "extension" {
                extensions.append(type)
            } else {
                if let existing = primaryTypes[fqName] {
                    merge(type, into: existing)
                } else {
                    primaryTypes[fqName] = type
                }
            }
            catalogTypes(type.nestedTypes, parentPath: fqName)
        }
    }
    
    catalogTypes(types)
    
    func findType(byPath path: [String], in rootTypes: inout [String: TypeModel]) -> TypeModel? {
        guard !path.isEmpty else { return nil }
        let rootName = path[0]
        guard let rootType = rootTypes[rootName] else { return nil }
        
        var current = rootType
        for part in path.dropFirst() {
            if let next = current.nestedTypes.first(where: { $0.name == part }) {
                current = next
            } else {
                return nil
            }
        }
        return current
    }
    
    for ext in extensions {
        let parts = ext.name.split(separator: ".").map(String.init)
        if let targetType = findType(byPath: parts, in: &primaryTypes) {
            merge(ext, into: targetType)
        } else {
            if let existingExt = primaryTypes[ext.name] {
                merge(ext, into: existingExt)
            } else {
                primaryTypes[ext.name] = ext
            }
        }
    }
    
    var topLevelTypes: [TypeModel] = []
    for (fqName, type) in primaryTypes {
        if !fqName.contains(".") {
            topLevelTypes.append(type)
        }
    }
    
    return topLevelTypes.sorted(by: { $0.name < $1.name })
}
