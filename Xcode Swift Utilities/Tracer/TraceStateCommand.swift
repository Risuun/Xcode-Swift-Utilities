// TraceStateCommand.swift // Tracer

import Foundation
import SwiftSyntax
import SwiftParser

func runTraceState(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap trace-state [--json] <directory-or-file-path>")
        exit(0)
    }

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
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    let baseFolderURL = URL(fileURLWithPath: resolveOrExitTarget(targetPath))
    
    let views = ParallelASTScanner.scan(files: swiftFiles) { fileURL -> [ViewStateModel] in
        guard FastFilter.shouldParse(fileURL: fileURL, subcommand: "trace-state", queryOrModel: nil) else {
            return []
        }
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }
        let sourceFile = Parser.parse(source: fileContent)
        let visitor = StateTraceVisitor(viewMode: .sourceAccurate)
        let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
        visitor.currentFilePath = relPath
        visitor.currentLocationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        visitor.walk(sourceFile)
        return visitor.views
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(views), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        if views.isEmpty || views.allSatisfy({ $0.variables.isEmpty }) {
            print("[OK: No active matches found for 'State' across \(swiftFiles.count) scanned files]")
            return
        }

        for view in views {
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
