// InspectModelCommand.swift // Commands
// Compound operation: extract-schema, audit-filters, and find-usage in a single concurrent pass

import Foundation
import SwiftSyntax
import SwiftParser

public struct InspectSchemaProperty: Codable, Sendable {
    public var name: String
    public var type: String
    public var isRelationship: Bool
    
    public init(name: String, type: String, isRelationship: Bool = false) {
        self.name = name
        self.type = type
        self.isRelationship = isRelationship
    }
}

public struct InspectFilterEntry: Codable, Sendable {
    public var file: String
    public var line: Int
    public var description: String
    
    public init(file: String, line: Int, description: String) {
        self.file = file
        self.line = line
        self.description = description
    }
}

public struct InspectUsageEntry: Codable, Sendable {
    public var file: String
    public var line: Int
    public var expression: String
    public var access: String // "read" or "write"
    
    public init(file: String, line: Int, expression: String, access: String) {
        self.file = file
        self.line = line
        self.expression = expression
        self.access = access
    }
}

public struct InspectModelOutput: Codable, Sendable {
    public var model: String
    public var schema: [InspectSchemaProperty]
    public var predicatesAndFilters: [InspectFilterEntry]
    public var propertyUsages: [InspectUsageEntry]
    
    public init(model: String, schema: [InspectSchemaProperty], predicatesAndFilters: [InspectFilterEntry], propertyUsages: [InspectUsageEntry]) {
        self.model = model
        self.schema = schema
        self.predicatesAndFilters = predicatesAndFilters
        self.propertyUsages = propertyUsages
    }
}

// AST Visitor to extract schema for a specific target model name
private class TargetModelSchemaVisitor: SyntaxVisitor {
    let targetModel: String
    var properties: [InspectSchemaProperty] = []
    
    init(targetModel: String) {
        self.targetModel = targetModel
        super.init(viewMode: .sourceAccurate)
    }
    
    private func matchesModelName(_ name: String) -> Bool {
        return name == targetModel || name.caseInsensitiveCompare(targetModel) == .orderedSame
    }
    
    private func extractProperties(from memberBlock: MemberBlockSyntax) {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let modifiers = varDecl.modifiers.trimmedDescription
            if modifiers.contains("static") || modifiers.contains("class") { continue }
            
            var isRel = false
            for attribute in varDecl.attributes {
                if case .attribute(let attr) = attribute {
                    if attr.attributeName.trimmedDescription == "Relationship" {
                        isRel = true
                    }
                }
            }
            
            for binding in varDecl.bindings {
                if binding.accessorBlock != nil {
                    // Check if accessor block has getters or is computed
                    if let accessors = binding.accessorBlock?.accessors {
                        switch accessors {
                        case .getter:
                            continue
                        case .accessors(let list):
                            if list.contains(where: { $0.accessorSpecifier.text == "get" }) {
                                continue
                            }
                        }
                    }
                }
                
                let name = binding.pattern.trimmedDescription
                var typeStr = binding.typeAnnotation?.type.trimmedDescription ?? ""
                if typeStr.isEmpty {
                    if let initClause = binding.initializer {
                        typeStr = "Inferred(\(initClause.value.trimmedDescription))"
                    } else {
                        typeStr = "Any"
                    }
                }
                
                properties.append(InspectSchemaProperty(name: name, type: typeStr, isRelationship: isRel))
            }
        }
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if matchesModelName(node.name.text) {
            extractProperties(from: node.memberBlock)
        }
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if matchesModelName(node.name.text) {
            extractProperties(from: node.memberBlock)
        }
        return .visitChildren
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        if matchesModelName(node.name.text) {
            extractProperties(from: node.memberBlock)
        }
        return .visitChildren
    }
}

// AST Visitor to extract property usages
private class PropertyUsageVisitor: SyntaxVisitor {
    let keyProperties: Set<String>
    let targetModel: String
    let currentFilePath: String
    let locationConverter: SourceLocationConverter
    var usages: [InspectUsageEntry] = []
    private var recordedLines: Set<String> = []
    
    init(keyProperties: Set<String>, targetModel: String, filePath: String, converter: SourceLocationConverter) {
        self.keyProperties = keyProperties
        self.targetModel = targetModel
        self.currentFilePath = filePath
        self.locationConverter = converter
        super.init(viewMode: .sourceAccurate)
    }
    
    private func determineAccess(for node: SyntaxProtocol) -> String {
        var current: Syntax? = node.parent
        while let p = current {
            if let infix = p.as(InfixOperatorExprSyntax.self) {
                if let op = infix.operator.as(BinaryOperatorExprSyntax.self), op.operator.text == "=" {
                    if infix.leftOperand.trimmedDescription == node.trimmedDescription {
                        return "write"
                    }
                }
            }
            if let seq = p.as(SequenceExprSyntax.self) {
                let elements = Array(seq.elements)
                if let idx = elements.firstIndex(where: { $0.trimmedDescription == node.trimmedDescription }) {
                    if idx + 1 < elements.count, elements[idx + 1].trimmedDescription == "=" {
                        return "write"
                    }
                }
            }
            if p.is(InOutExprSyntax.self) {
                return "write"
            }
            if p.is(CodeBlockItemSyntax.self) || p.is(StmtSyntax.self) {
                break
            }
            current = p.parent
        }
        return "read"
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let propName = node.declName.baseName.text
        if keyProperties.contains(propName) {
            let baseDesc = node.base?.trimmedDescription ?? ""
            if !baseDesc.isEmpty {
                let expr = "\(baseDesc).\(propName)"
                let loc = node.startLocation(converter: locationConverter)
                let key = "\(loc.line):\(expr)"
                if !recordedLines.contains(key) {
                    recordedLines.insert(key)
                    let access = determineAccess(for: node)
                    usages.append(InspectUsageEntry(
                        file: currentFilePath,
                        line: loc.line,
                        expression: expr,
                        access: access
                    ))
                }
            }
        }
        return .visitChildren
    }
}

private final class PropertyCollector: @unchecked Sendable {
    var items = [InspectSchemaProperty]()
    let lock = NSLock()
    
    func appendUnique(_ newItems: [InspectSchemaProperty]) {
        lock.lock()
        for item in newItems {
            if !items.contains(where: { $0.name == item.name }) {
                items.append(item)
            }
        }
        lock.unlock()
    }
}

public func runInspectModel(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap inspect-model --model <ModelName> [directory-or-file-path] [--json]")
        exit(0)
    }
    
    var isJSON = false
    var modelName: String? = nil
    var path: String = "."
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg == "--model" || arg == "-m" {
            idx += 1
            if idx < args.count {
                modelName = args[idx]
            }
        } else if arg.hasPrefix("--model=") {
            modelName = String(arg.dropFirst("--model=".count))
        } else if !arg.hasPrefix("-") {
            path = arg
        } else {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        }
        idx += 1
    }
    
    guard let targetModel = modelName, !targetModel.isEmpty else {
        fputs("Usage: XCSwiftMap inspect-model --model <ModelName> [directory-or-file-path] [--json]\n", stderr)
        exit(1)
    }
    
    let resolvedPath = resolveOrExitTarget(path)
    let swiftFiles = findSwiftFiles(at: resolvedPath, excluding: [])
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(path)]\n", stderr)
        exit(1)
    }
    
    let baseURL = URL(fileURLWithPath: resolvedPath)
    
    // Read and extract schema
    let schemaCollector = PropertyCollector()
    
    // Concurrently find schema in files
    DispatchQueue.concurrentPerform(iterations: swiftFiles.count) { i in
        let fileURL = swiftFiles[i]
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        if !content.localizedCaseInsensitiveContains(targetModel) { return }
        
        let sourceFile = Parser.parse(source: content)
        let visitor = TargetModelSchemaVisitor(targetModel: targetModel)
        visitor.walk(sourceFile)
        
        if !visitor.properties.isEmpty {
            schemaCollector.appendUnique(visitor.properties)
        }
    }
    
    let schemaProperties = schemaCollector.items
    let keyProperties = Set(schemaProperties.map { $0.name })
    
    // Pass 2: Concurrently scan for Active Predicates/Filters and Property Usages
    struct ScanResult {
        var filterEntries: [InspectFilterEntry]
        var usageEntries: [InspectUsageEntry]
    }
    
    let scanResults = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [ScanResult] in
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        
        let relPath = relativePath(of: fileURL, relativeTo: baseURL)
        let containsModel = content.localizedCaseInsensitiveContains(targetModel)
        let containsFilterKeyword = content.contains("filter") || content.contains("Predicate") || content.contains("@Query")
        let containsAnyProperty = keyProperties.contains(where: { content.contains($0) })
        
        guard containsModel || containsFilterKeyword || containsAnyProperty else {
            return []
        }
        
        let sourceFile = Parser.parse(source: content)
        let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        
        // 1. Audit Filters
        var filterEntries: [InspectFilterEntry] = []
        if containsModel || containsFilterKeyword {
            let filterVisitor = FilterAuditVisitor(viewMode: .sourceAccurate, targetModel: targetModel)
            filterVisitor.resetForNewFile(filePath: relPath, converter: converter)
            filterVisitor.walk(sourceFile)
            
            for item in filterVisitor.results {
                let leaf = URL(fileURLWithPath: item.file).lastPathComponent
                let desc: String
                if item.kind.starts(with: "#Predicate") {
                    desc = "\(item.kind) { \(item.condition) }"
                } else if item.kind == "Collection.filter" || item.kind == ".filter" {
                    desc = ".filter { \(item.condition) }"
                } else if item.kind == "@Query" {
                    desc = "@Query \(item.condition)"
                } else {
                    desc = "\(item.kind) -> \(item.condition)"
                }
                filterEntries.append(InspectFilterEntry(file: leaf, line: item.line, description: desc))
            }
        }
        
        // 2. Property Usages
        var usageEntries: [InspectUsageEntry] = []
        if !keyProperties.isEmpty {
            let usageVisitor = PropertyUsageVisitor(
                keyProperties: keyProperties,
                targetModel: targetModel,
                filePath: relPath,
                converter: converter
            )
            usageVisitor.walk(sourceFile)
            for item in usageVisitor.usages {
                let leaf = URL(fileURLWithPath: item.file).lastPathComponent
                usageEntries.append(InspectUsageEntry(
                    file: leaf,
                    line: item.line,
                    expression: item.expression,
                    access: item.access
                ))
            }
        }
        
        if filterEntries.isEmpty && usageEntries.isEmpty {
            return []
        }
        return [ScanResult(filterEntries: filterEntries, usageEntries: usageEntries)]
    }
    
    var allFilters: [InspectFilterEntry] = []
    var allUsages: [InspectUsageEntry] = []
    for res in scanResults {
        allFilters.append(contentsOf: res.filterEntries)
        allUsages.append(contentsOf: res.usageEntries)
    }
    
    // Sort results by file and line
    allFilters.sort { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
    allUsages.sort { $0.file == $1.file ? $0.line < $1.line : $0.file < $1.file }
    
    let outputObj = InspectModelOutput(
        model: targetModel,
        schema: schemaProperties,
        predicatesAndFilters: allFilters,
        propertyUsages: allUsages
    )
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(outputObj), let jsonStr = String(data: data, encoding: .utf8) {
            print(jsonStr)
        }
    } else {
        print("================ MODEL: [\(targetModel)] ================")
        print("[SCHEMA]")
        if schemaProperties.isEmpty {
            print("  (No schema properties found)")
        } else {
            for prop in schemaProperties {
                print("• \(prop.name): \(prop.type)")
            }
        }
        print("")
        print("[ACTIVE PREDICATES & FILTERS]")
        if allFilters.isEmpty {
            print("  (No active predicates or filters found)")
        } else {
            for filter in allFilters {
                print("• \(filter.file):\(filter.line) -> \(filter.description)")
            }
        }
        print("")
        print("[PROPERTY USAGES]")
        if allUsages.isEmpty {
            print("  (No property usages found)")
        } else {
            for usage in allUsages {
                print("• \(usage.file):\(usage.line) -> \(usage.expression) (\(usage.access))")
            }
        }
        print("=======================================================")
    }
}
