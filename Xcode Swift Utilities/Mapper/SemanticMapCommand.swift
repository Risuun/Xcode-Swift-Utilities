// SemanticMapCommand.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax
import SwiftParser

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
