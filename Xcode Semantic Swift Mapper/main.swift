import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Models

class TypeModel: Codable {
    var kind: String // "struct", "class", "enum", "protocol", "actor", "extension"
    var name: String
    var accessLevel: String
    var inheritance: [String]
    var properties: [PropertyModel] = []
    var functions: [FunctionModel] = []
    var initializers: [InitializerModel] = []
    var cases: [String] = []
    var typealiases: [TypealiasModel] = []
    var associatedtypes: [AssociatedTypeModel] = []
    var nestedTypes: [TypeModel] = []
    
    init(kind: String, name: String, accessLevel: String, inheritance: [String]) {
        self.kind = kind
        self.name = name
        self.accessLevel = accessLevel
        self.inheritance = inheritance
    }
}

struct PropertyModel: Codable {
    var accessLevel: String
    var specifier: String // "let" or "var"
    var name: String
    var type: String?
}

struct FunctionModel: Codable {
    var accessLevel: String
    var name: String
    var signature: String
}

struct InitializerModel: Codable {
    var accessLevel: String
    var signature: String
}

struct TypealiasModel: Codable {
    var accessLevel: String
    var name: String
    var underlyingType: String
}

struct AssociatedTypeModel: Codable {
    var accessLevel: String
    var name: String
    var inheritance: String?
}

class SourceMap: Codable {
    var types: [TypeModel] = []
    var properties: [PropertyModel] = []
    var functions: [FunctionModel] = []
    var typealiases: [TypealiasModel] = []
}

// MARK: - AST Visitor

class SwiftMapVisitor: SyntaxVisitor {
    var types: [TypeModel] = []
    var properties: [PropertyModel] = []
    var functions: [FunctionModel] = []
    var typealiases: [TypealiasModel] = []
    
    private var typeStack: [TypeModel] = []
    
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
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "struct", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "class", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "enum", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: EnumDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "protocol", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: ProtocolDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "actor", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: ActorDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.extendedType.trimmedDescription
        let inheritance = node.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let model = TypeModel(kind: "extension", name: name, accessLevel: accessLevel, inheritance: inheritance)
        addType(model)
        return .visitChildren
    }
    
    override func visitPost(_ node: ExtensionDeclSyntax) {
        popType()
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let specifier = node.bindingSpecifier.text
        
        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            let type = binding.typeAnnotation?.type.trimmedDescription
            let model = PropertyModel(accessLevel: accessLevel, specifier: specifier, name: name, type: type)
            
            if let currentType = typeStack.last {
                currentType.properties.append(model)
            } else {
                properties.append(model)
            }
        }
        return .skipChildren
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let signature = node.signature.trimmedDescription
        let model = FunctionModel(accessLevel: accessLevel, name: name, signature: signature)
        
        if let currentType = typeStack.last {
            currentType.functions.append(model)
        } else {
            functions.append(model)
        }
        return .skipChildren
    }
    
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let signature = node.signature.trimmedDescription
        let model = InitializerModel(accessLevel: accessLevel, signature: signature)
        
        if let currentType = typeStack.last {
            currentType.initializers.append(model)
        }
        return .skipChildren
    }
    
    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let cases = node.elements.map { $0.trimmedDescription }
        if let currentType = typeStack.last {
            currentType.cases.append(contentsOf: cases)
        }
        return .skipChildren
    }
    
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let underlyingType = node.initializer.value.trimmedDescription
        let model = TypealiasModel(accessLevel: accessLevel, name: name, underlyingType: underlyingType)
        
        if let currentType = typeStack.last {
            currentType.typealiases.append(model)
        } else {
            typealiases.append(model)
        }
        return .skipChildren
    }
    
    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let accessLevel = node.modifiers.trimmedDescription
        let name = node.name.text
        let inheritance = node.inheritanceClause?.trimmedDescription
        let model = AssociatedTypeModel(accessLevel: accessLevel, name: name, inheritance: inheritance)
        
        if let currentType = typeStack.last {
            currentType.associatedtypes.append(model)
        }
        return .skipChildren
    }
}

// MARK: - Consolidation Logic

func merge(_ source: TypeModel, into target: TypeModel) {
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

func consolidateSourceMap(types: [TypeModel]) -> [TypeModel] {
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

// MARK: - File Scanning

func findSwiftFiles(at path: String, excluding: [String]) -> [URL] {
    let url = URL(fileURLWithPath: path)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
        return []
    }
    
    if !isDir.boolValue {
        return shouldExclude(url.path, patterns: excluding) ? [] : [url]
    }
    
    var swiftFiles: [URL] = []
    let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    
    while let fileURL = enumerator?.nextObject() as? URL {
        if shouldExclude(fileURL.path, patterns: excluding) {
            if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator?.skipDescendants()
            }
            continue
        }
        if fileURL.pathExtension == "swift" {
            swiftFiles.append(fileURL)
        }
    }
    return swiftFiles
}

func shouldExclude(_ path: String, patterns: [String]) -> Bool {
    for pattern in patterns {
        if path.lowercased().contains(pattern.lowercased()) {
            return true
        }
    }
    return false
}

// MARK: - Text Printer

class SourceMapPrinter {
    let sourceMap: SourceMap
    var indentLevel = 0
    
    init(sourceMap: SourceMap) {
        self.sourceMap = sourceMap
    }
    
    func printWithIndent(_ text: String) {
        let indent = String(repeating: "    ", count: indentLevel)
        print("\(indent)\(text)")
    }
    
    func printMap() {
        for prop in sourceMap.properties {
            printProperty(prop)
        }
        for function in sourceMap.functions {
            printFunction(function)
        }
        for typealiasDecl in sourceMap.typealiases {
            printTypealias(typealiasDecl)
        }
        
        if !sourceMap.properties.isEmpty || !sourceMap.functions.isEmpty || !sourceMap.typealiases.isEmpty {
            print("")
        }
        
        for type in sourceMap.types {
            printType(type)
        }
    }
    
    func printType(_ type: TypeModel) {
        let prefix = type.accessLevel.isEmpty ? "" : "\(type.accessLevel) "
        let inheritanceStr = type.inheritance.isEmpty ? "" : " : \(type.inheritance.joined(separator: ", "))"
        let kindKeyword = type.kind
        
        printWithIndent("\(prefix)\(kindKeyword) \(type.name)\(inheritanceStr) {")
        indentLevel += 1
        
        for enumCase in type.cases {
            printWithIndent("case \(enumCase)")
        }
        if !type.cases.isEmpty { print("") }
        
        for assoc in type.associatedtypes {
            let assocPrefix = assoc.accessLevel.isEmpty ? "" : "\(assoc.accessLevel) "
            let inheritanceStr = (assoc.inheritance?.isEmpty ?? true) ? "" : " : \(assoc.inheritance!)"
            printWithIndent("\(assocPrefix)associatedtype \(assoc.name)\(inheritanceStr)")
        }
        
        for ta in type.typealiases {
            printTypealias(ta)
        }
        
        for prop in type.properties {
            printProperty(prop)
        }
        
        for initDecl in type.initializers {
            let initPrefix = initDecl.accessLevel.isEmpty ? "" : "\(initDecl.accessLevel) "
            printWithIndent("\(initPrefix)init\(initDecl.signature)")
        }
        
        for function in type.functions {
            printFunction(function)
        }
        
        for nested in type.nestedTypes {
            print("")
            printType(nested)
        }
        
        indentLevel -= 1
        printWithIndent("}")
    }
    
    func printProperty(_ prop: PropertyModel) {
        let prefix = prop.accessLevel.isEmpty ? "" : "\(prop.accessLevel) "
        if let type = prop.type {
            printWithIndent("\(prefix)\(prop.specifier) \(prop.name): \(type)")
        } else {
            printWithIndent("\(prefix)\(prop.specifier) \(prop.name)")
        }
    }
    
    func printFunction(_ function: FunctionModel) {
        let prefix = function.accessLevel.isEmpty ? "" : "\(function.accessLevel) "
        printWithIndent("\(prefix)func \(function.name)\(function.signature)")
    }
    
    func printTypealias(_ ta: TypealiasModel) {
        let prefix = ta.accessLevel.isEmpty ? "" : "\(ta.accessLevel) "
        printWithIndent("\(prefix)typealias \(ta.name) = \(ta.underlyingType)")
    }
}

// MARK: - Main Entry Point

let arguments = CommandLine.arguments
var isJSON = false
var excludes: [String] = ["Tests", "Mocks", "Mock", "test", "mock", "Spec", "Spec.swift"]
var path: String? = nil

var args = CommandLine.arguments
args.removeFirst()

var idx = 0
while idx < args.count {
    let arg = args[idx]
    if arg == "--json" {
        isJSON = true
    } else if arg == "--exclude" {
        if idx + 1 < args.count {
            excludes = args[idx + 1].split(separator: ",").map { String($0) }
            idx += 1
        }
    } else if arg.hasPrefix("--exclude=") {
        excludes = String(arg.dropFirst(10)).split(separator: ",").map { String($0) }
    } else if arg.hasPrefix("-") {
        fputs("Unknown option: \(arg)\n", stderr)
        exit(1)
    } else {
        path = arg
    }
    idx += 1
}

guard let targetPath = path else {
    fputs("Usage: XCSwiftMap [--json] [--exclude <patterns>] <file-or-directory-path>\n", stderr)
    exit(1)
}

let swiftFiles = findSwiftFiles(at: targetPath, excluding: excludes)

if swiftFiles.isEmpty {
    fputs("No Swift files found at: \(targetPath)\n", stderr)
    exit(1)
}

let visitor = SwiftMapVisitor(viewMode: .sourceAccurate)

for fileURL in swiftFiles {
    if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
        let sourceFile = Parser.parse(source: fileContent)
        visitor.walk(sourceFile)
    }
}

let consolidatedTypes = consolidateSourceMap(types: visitor.types)

let sourceMap = SourceMap()
sourceMap.types = consolidatedTypes
sourceMap.properties = visitor.properties
sourceMap.functions = visitor.functions
sourceMap.typealiases = visitor.typealiases

if isJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(sourceMap), let jsonString = String(data: data, encoding: .utf8) {
        print(jsonString)
    }
} else {
    let printer = SourceMapPrinter(sourceMap: sourceMap)
    printer.printMap()
}
