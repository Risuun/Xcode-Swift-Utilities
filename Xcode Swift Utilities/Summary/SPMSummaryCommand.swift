// SPMSummaryCommand.swift // Xcode Swift Utilities

import Foundation

func runSPMSummary(args: [String]) {
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
    
    let targetPath = path ?? FileManager.default.currentDirectoryPath
    let resolvedFiles = findPackageResolvedFiles(at: targetPath)
    
    if resolvedFiles.isEmpty {
        fputs("No Package.resolved files found under: \(targetPath)\n", stderr)
        exit(1)
    }
    
    var allDeps: [String: String] = [:]
    for fileURL in resolvedFiles {
        let deps = parsePackageResolved(at: fileURL)
        for (pkg, version) in deps {
            allDeps[pkg] = version
        }
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(allDeps), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    } else {
        let sorted = allDeps.sorted(by: { $0.key < $1.key })
        for (pkg, version) in sorted {
            print("\(pkg) v\(version)")
        }
    }
}
