// PreviewRenderCommand.swift // XCEdit //

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
    if args.contains("--help") || args.contains("-h") {
        print("Usage: XCSwiftMap preview-render [--png] <file-path>")
        exit(0)
    }

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

    guard let rawPath = filePath else {
        fputs("Usage: XCSwiftMap preview-render [--png] <file-path>\n", stderr)
        exit(1)
    }

    let sanitizedPath = sanitizePath(rawPath)
    let resolvedPath = resolveOrExitTarget(sanitizedPath)
    guard let fileContent = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
        fputs("[ERROR: Target not found: \(sanitizedPath)]\n", stderr)
        exit(1)
    }

    let sourceFile = Parser.parse(source: fileContent)
    let visitor = PreviewVisitor(viewMode: .sourceAccurate)
    visitor.walk(sourceFile)

    let finder = ViewSkeletonFinder(viewMode: .sourceAccurate)
    finder.walk(sourceFile)

    if !finder.hasFoundView {
        let leaf = URL(fileURLWithPath: resolvedPath).lastPathComponent
        fputs("[ERROR: No SwiftUI view body in \(leaf)]\n", stderr)
        exit(1)
    }

    if wantPNG {
        let outputPath = "/tmp/preview_\(URL(fileURLWithPath: resolvedPath).deletingPathExtension().lastPathComponent).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", "booted", "screenshot", outputPath]
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            group.wait()
            if FileManager.default.fileExists(atPath: outputPath) {
                print("[PNG Screenshot Generated]: \(outputPath)")
            } else {
                print("Note: Boot an iOS/macOS simulator to save live PNG render to '\(outputPath)'.")
            }
        } catch {
            print("Unable to capture simulator screenshot: \(error)")
        }
    }
}