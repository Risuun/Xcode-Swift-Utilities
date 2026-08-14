// XCAssetsCommand.swift // Assets

import Foundation

func runXCAssets(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap xcassets [--json] [--exclude <patterns>] <directory-path>")
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
        fputs("Usage: XCSwiftMap xcassets [--json] [--exclude <patterns>] <directory-path>\n", stderr)
        exit(1)
    }
    
    let resolvedPath = resolveOrExitTarget(targetPath)
    let validator = XCAssetsValidator(projectPath: resolvedPath, excludes: excludes)
    validator.run(isJSON: isJSON)
}
