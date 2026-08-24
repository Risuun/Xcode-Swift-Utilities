// ViewSkeletonCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

func runViewSkeleton(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap view-skeleton <file-path>")
        exit(0)
    }

    guard args.count > 0 else {
        fputs("Usage: XCSwiftMap view-skeleton <file-path>\n", stderr)
        exit(1)
    }
    let rawPath = args[0]
    let targetPath = sanitizePath(rawPath)
    let resolvedPath = resolveOrExitTarget(targetPath)
    let fileURL = URL(fileURLWithPath: resolvedPath)
    
    guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(targetPath)]\n", stderr)
        exit(1)
    }
    
    let sourceFile = Parser.parse(source: fileContent)
    let finder = ViewSkeletonFinder(viewMode: .sourceAccurate)
    finder.walk(sourceFile)
    
    if !finder.hasFoundView {
        let leaf = fileURL.lastPathComponent
        fputs("[ERROR: No SwiftUI view body in \(leaf)]\n", stderr)
        exit(1)
    }
}