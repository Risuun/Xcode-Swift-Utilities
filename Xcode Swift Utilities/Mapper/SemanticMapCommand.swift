// SemanticMapCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

func runSemanticMap(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        printUsage(toStderr: false)
        exit(0)
    }

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
                excludes = args[idx + 1].split(separator: ",").map { sanitizePath(String($0)) }
                idx += 1
            }
        } else if arg.hasPrefix("--exclude=") {
            excludes = String(arg.dropFirst(10)).split(separator: ",").map { sanitizePath(String($0)) }
        } else if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        } else {
            path = arg
        }
        idx += 1
    }
    
    guard let rawPath = path else {
        printUsage(toStderr: true)
        exit(1)
    }
    
    let targetPath = sanitizePath(rawPath)
    let swiftFiles = findSwiftFiles(at: targetPath, excluding: excludes)
    if swiftFiles.isEmpty {
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    struct MapFileScanResult {
        var types: [TypeModel]
        var properties: [PropertyModel]
        var functions: [FunctionModel]
        var typealiases: [TypealiasModel]
    }
    
    let baseFolderURL = URL(fileURLWithPath: resolveOrExitTarget(targetPath))
    
    let scanResults = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [MapFileScanResult] in
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: fileContent)
        let visitor = SwiftMapVisitor(viewMode: .sourceAccurate)
        let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
        visitor.currentFilePath = relPath
        visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        visitor.walk(sourceFile)
        return [MapFileScanResult(
            types: visitor.types,
            properties: visitor.properties,
            functions: visitor.functions,
            typealiases: visitor.typealiases
        )]
    }
    
    var allTypes: [TypeModel] = []
    var allProperties: [PropertyModel] = []
    var allFunctions: [FunctionModel] = []
    var allTypealiases: [TypealiasModel] = []
    
    for item in scanResults {
        allTypes.append(contentsOf: item.types)
        allProperties.append(contentsOf: item.properties)
        allFunctions.append(contentsOf: item.functions)
        allTypealiases.append(contentsOf: item.typealiases)
    }
    
    let consolidatedTypes = consolidateSourceMap(types: allTypes)
    
    let sourceMap = SourceMap()
    sourceMap.types = consolidatedTypes
    sourceMap.properties = allProperties
    sourceMap.functions = allFunctions
    sourceMap.typealiases = allTypealiases
    
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