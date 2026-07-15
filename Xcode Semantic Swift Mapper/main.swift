import Foundation
import SwiftSyntax
import SwiftParser

// Helper to determine base type from type string
func getBaseTypeName(from typeStr: String) -> String {
    var result = typeStr.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.hasSuffix("?") || result.hasSuffix("!") {
        result = String(result.dropLast())
    }
    if result.hasPrefix("[") && result.hasSuffix("]") {
        result = String(result.dropFirst().dropLast())
    }
    if result.hasSuffix("?") || result.hasSuffix("!") {
        result = String(result.dropLast())
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func main() {
    let arguments = CommandLine.arguments
    var args = arguments
    args.removeFirst() // remove program name
    
    guard !args.isEmpty else {
        printUsage()
        exit(1)
    }
    
    if args[0] == "extract-schema" {
        args.removeFirst()
        runExtractSchema(args: args)
    } else {
        runSemanticMap(args: args)
    }
}

func printUsage() {
    fputs("""
Usage:
  XCSwiftMap [--json] [--summary] [--mermaid] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>
""", stderr)
}

func runExtractSchema(args: [String]) {
    var isJSON = false
    var excludes: [String] = ["Tests", "Mocks", "Mock", "test", "mock", "Spec", "Spec.swift"]
    var path: String? = nil
    
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
        fputs("Usage: XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: targetPath, excluding: excludes)
    if swiftFiles.isEmpty {
        fputs("No Swift files found at: \(targetPath)\n", stderr)
        exit(1)
    }
    
    let visitor = SchemaVisitor(viewMode: .sourceAccurate)
    let baseFolderURL = URL(fileURLWithPath: targetPath)
    
    for fileURL in swiftFiles {
        if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            let sourceFile = Parser.parse(source: fileContent)
            
            let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
            visitor.currentFilePath = relPath
            visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
            
            visitor.walk(sourceFile)
        }
    }
    
    let modelNames = Set(visitor.models.map { $0.name })
    
    // Build output objects
    var outputModels: [SchemaModelOutput] = []
    for model in visitor.models {
        var properties: [SchemaProperty] = []
        var relationships: [SchemaRelationship] = []
        
        for prop in model.properties {
            let baseType = getBaseTypeName(from: prop.type)
            if modelNames.contains(baseType) {
                let relationshipType = prop.type.contains("[") && prop.type.contains("]") ? "1-to-many" : "1-to-1"
                relationships.append(SchemaRelationship(from: model.name, to: baseType, type: relationshipType))
            } else {
                properties.append(prop)
            }
        }
        outputModels.append(SchemaModelOutput(name: model.name, location: model.location, properties: properties, relationships: relationships))
    }
    
    if isJSON {
        let output = SchemaOutput(models: outputModels, queries: visitor.queries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(output), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        // Text format
        for model in outputModels {
            let locStr = model.location.map { " // \($0.file):\($0.line)" } ?? ""
            print("Model: \(model.name)\(locStr)")
            
            if !model.properties.isEmpty {
                print("  Properties:")
                for prop in model.properties {
                    let propLoc = prop.location.map { " // \($0.file):\($0.line)" } ?? ""
                    print("    var \(prop.name): \(prop.type)\(propLoc)")
                }
            }
            
            if !model.relationships.isEmpty {
                print("  Relationships:")
                for rel in model.relationships {
                    print("    \(rel.from) has a \(rel.type) relationship with \(rel.to)")
                }
            }
            print("")
        }
        
        if !visitor.queries.isEmpty {
            print("Queries:")
            for query in visitor.queries {
                let queryLoc = query.location.map { " // \($0.file):\($0.line)" } ?? ""
                print("  @Query var \(query.name): \(query.type)\(queryLoc)")
            }
        }
    }
}

func runSemanticMap(args: [String]) {
    var isJSON = false
    var isSummary = false
    var isMermaid = false
    var excludes: [String] = ["Tests", "Mocks", "Mock", "test", "mock", "Spec", "Spec.swift"]
    var path: String? = nil
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg == "--summary" {
            isSummary = true
        } else if arg == "--mermaid" {
            isMermaid = true
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
        printUsage()
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: targetPath, excluding: excludes)
    if swiftFiles.isEmpty {
        fputs("No Swift files found at: \(targetPath)\n", stderr)
        exit(1)
    }
    
    let visitor = SwiftMapVisitor(viewMode: .sourceAccurate)
    let baseFolderURL = URL(fileURLWithPath: targetPath)
    
    for fileURL in swiftFiles {
        if let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            let sourceFile = Parser.parse(source: fileContent)
            
            let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
            visitor.currentFilePath = relPath
            visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
            
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
    } else if isMermaid {
        let printer = MermaidPrinter(sourceMap: sourceMap, isSummary: isSummary)
        printer.printDiagram()
    } else {
        let printer = SourceMapPrinter(sourceMap: sourceMap, isSummary: isSummary)
        printer.printMap()
    }
}

main()
