// ExtractSchemaCommand.swift // Extractor

import Foundation
import SwiftSyntax
import SwiftParser

func runExtractSchema(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>")
        exit(0)
    }

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
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    struct SchemaFileScanResult {
        var models: [SchemaModel]
        var queries: [SchemaQuery]
    }
    
    let baseFolderURL = URL(fileURLWithPath: resolveOrExitTarget(targetPath))
    
    let scanResults = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [SchemaFileScanResult] in
        guard FastFilter.shouldParse(fileURL: fileURL, subcommand: "extract-schema", queryOrModel: nil) else {
            return []
        }
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: fileContent)
        let visitor = SchemaVisitor(viewMode: .sourceAccurate)
        let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
        visitor.currentFilePath = relPath
        visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        visitor.walk(sourceFile)
        if visitor.models.isEmpty && visitor.queries.isEmpty {
            return []
        }
        return [SchemaFileScanResult(models: visitor.models, queries: visitor.queries)]
    }
    
    var allModels: [SchemaModel] = []
    var allQueries: [SchemaQuery] = []
    for item in scanResults {
        allModels.append(contentsOf: item.models)
        allQueries.append(contentsOf: item.queries)
    }
    
    let modelNames = Set(allModels.map { $0.name })
    
    // Build output objects
    var outputModels: [SchemaModelOutput] = []
    for model in allModels {
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
        let output = SchemaOutput(models: outputModels, queries: allQueries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(output), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        if outputModels.isEmpty && allQueries.isEmpty {
            print("[OK: No active matches found for 'Schema' across \(swiftFiles.count) scanned files]")
            return
        }

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
        
        if !allQueries.isEmpty {
            print("Queries:")
            for query in allQueries {
                let queryLoc = query.location.map { " // \($0.file):\($0.line)" } ?? ""
                print("  @Query var \(query.name): \(query.type)\(queryLoc)")
            }
        }
    }
}
