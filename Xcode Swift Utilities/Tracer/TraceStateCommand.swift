// TraceStateCommand.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax
import SwiftParser

func runTraceState(args: [String]) {
    var isJSON = false
    var path: String? = nil
    
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--json" {
            isJSON = true
        } else if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        } else {
            path = arg
        }
        idx += 1
    }
    
    guard let targetPath = path else {
        fputs("Usage: XCSwiftMap trace-state [--json] <directory-or-file-path>\n", stderr)
        exit(1)
    }
    
    let swiftFiles = findSwiftFiles(at: targetPath, excluding: [])
    if swiftFiles.isEmpty {
        fputs("No Swift files found at: \(targetPath)\n", stderr)
        exit(1)
    }
    
    let visitor = StateTraceVisitor(viewMode: .sourceAccurate)
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
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(visitor.views), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        for view in visitor.views {
            let locStr = view.location.map { " // \($0.file):\($0.line)" } ?? ""
            print("View: \(view.name)\(locStr)")
            for v in view.variables {
                let vLoc = v.location.map { " // \($0.file):\($0.line)" } ?? ""
                print("  @\(v.wrapper) var \(v.name): \(v.type)\(vLoc)")
            }
            print("")
        }
    }
}
