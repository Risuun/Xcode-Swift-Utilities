// ViewSkeletonCommand.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax
import SwiftParser

func runViewSkeleton(args: [String]) {
    guard args.count > 0 else {
        fputs("Usage: XCSwiftMap view-skeleton <file-path>\n", stderr)
        exit(1)
    }
    let targetPath = args[0]
    let fileURL = URL(fileURLWithPath: targetPath)
    
    guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fputs("Error: Could not read file at \(targetPath)\n", stderr)
        exit(1)
    }
    
    let sourceFile = Parser.parse(source: fileContent)
    let finder = ViewSkeletonFinder(viewMode: .sourceAccurate)
    finder.walk(sourceFile)
    
    if !finder.hasFoundView {
        fputs("No SwiftUI views with a body property found in \(targetPath)\n", stderr)
        exit(1)
    }
}
