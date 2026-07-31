// PreviewRenderCommand.swift // Xcode Swift Utilities //

import Foundation
import SwiftSyntax
import SwiftParser

public class PreviewVisitor: SyntaxVisitor {
    public var previewCount = 0
    public var previewNames: [String] = []

    public override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" {
            previewCount += 1
            let label = node.arguments.first?.expression.trimmedDescription.replacingOccurrences(of: "\"", with: "") ?? "Preview #\(previewCount)"
            previewNames.append(label)
        }
        return .visitChildren
    }
}

func runPreviewRender(args: [String]) {
    guard !args.isEmpty else {
        fputs("Usage: XCSwiftMap preview-render [--png] <file-path>\n", stderr)
        exit(1)
    }

    var wantPNG = false
    var filePath: String? = nil

    for arg in args {
        if arg == "--png" {
            wantPNG = true
        } else if !arg.hasPrefix("-") {
            filePath = arg
        }
    }

    guard let targetPath = filePath, FileManager.default.fileExists(atPath: targetPath) else {
        fputs("Error: Valid file path required for preview-render\n", stderr)
        exit(1)
    }

    guard let fileContent = try? String(contentsOfFile: targetPath, encoding: .utf8) else {
        fputs("Error: Unable to read file '\(targetPath)'\n", stderr)
        exit(1)
    }

    let sourceFile = Parser.parse(source: fileContent)
    let visitor = PreviewVisitor(viewMode: .sourceAccurate)
    visitor.walk(sourceFile)

    let fileName = URL(fileURLWithPath: targetPath).lastPathComponent
    print("=== SwiftUI View Preview Hierarchy ===")
    print("Target File: \(fileName)")
    print("Found Previews: \(visitor.previewCount)")
    for name in visitor.previewNames {
        print("  • \(name)")
    }
    print("")

    let finder = ViewSkeletonFinder(viewMode: .sourceAccurate)
    finder.walk(sourceFile)

    if wantPNG {
        let outputPath = "/tmp/preview_\(URL(fileURLWithPath: targetPath).deletingPathExtension().lastPathComponent).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", "booted", "screenshot", outputPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            if FileManager.default.fileExists(atPath: outputPath) {
                print("\n[PNG Screenshot Generated]: \(outputPath)")
            } else {
                print("\nNote: Boot an iOS/macOS simulator to save live PNG render to '\(outputPath)'.")
            }
        } catch {
            print("Unable to capture simulator screenshot: \(error)")
        }
    }

    if !finder.hasFoundView {
        print("No SwiftUI View 'body' declaration found in '\(targetPath)'.")
    }
}
