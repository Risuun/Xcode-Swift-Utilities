// DiffCheckCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser
import SwiftParserDiagnostics
import SwiftDiagnostics

func runDiffCheck(args: [String]) {
    if args.contains("--help") || args.contains("-h") {
        printDiffCheckUsage(toStderr: false)
        exit(0)
    }
    var isParseOnly = false
    var noHeaderFix = false
    var isStdin = false
    var rawFilePath: String? = nil

    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg == "--parse-only" {
            isParseOnly = true
        } else if arg == "--no-header-fix" {
            noHeaderFix = true
        } else if arg == "--stdin" {
            isStdin = true
        } else if arg == "--path" || arg == "-p" {
            if idx + 1 < args.count {
                rawFilePath = args[idx + 1]
                idx += 1
            }
        } else if arg.hasPrefix("--path=") {
            rawFilePath = String(arg.dropFirst("--path=".count))
        } else if arg.hasPrefix("-") {
            fputs("Unknown option: \(arg)\n", stderr)
            exit(1)
        } else if rawFilePath == nil {
            rawFilePath = arg
        }
        idx += 1
    }
    let leafFileName: String
    let sourceContent: String
    let targetFileURL: URL?

    if isStdin || rawFilePath == "-" {
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: inputData, encoding: .utf8) else {
            fputs("[ERROR: Failed to read utf-8 content from standard input]\n", stderr)
            exit(1)
        }
        sourceContent = text
        leafFileName = "Source.swift"
        targetFileURL = nil
    } else {
        guard let inputPath = rawFilePath, !inputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            printDiffCheckUsage(toStderr: true)
            exit(1)
        }

        let sanitizedInput = sanitizePath(inputPath)
        guard let resolvedPath = resolveTargetFileOrDirectory(sanitizedInput) else {
            fputs("[MISSING: \(URL(fileURLWithPath: sanitizedInput).lastPathComponent)]\n", stderr)
            exit(1)
        }

        let url = URL(fileURLWithPath: resolvedPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fputs("[ERROR: Failed to read source file at \(url.lastPathComponent)]\n", stderr)
            exit(1)
        }

        sourceContent = text
        leafFileName = url.lastPathComponent
        targetFileURL = url
    }

    // 1. Parse AST via SwiftParser
    let sourceFile = Parser.parse(source: sourceContent)
    let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: sourceFile)

    // 2. Check for syntax errors
    let errorDiagnostics = diagnostics.filter { $0.diagMessage.severity == .error }
    if !errorDiagnostics.isEmpty || !diagnostics.isEmpty {
        let locationConverter = SourceLocationConverter(fileName: leafFileName, tree: sourceFile)
        for diag in diagnostics {
            let loc = diag.location(converter: locationConverter)
            let line = loc.line
            let column = loc.column
            let message = diag.diagMessage.message
            let severity = diag.diagMessage.severity == .error ? "error" : "warning"
            fputs("\(leafFileName):\(line):\(column): \(severity): \(message)\n", stderr)
        }
        fputs("[INVALID: \(leafFileName)]\n", stderr)
        exit(1)
    }

    // 3. Fast exit if parse-only
    if isParseOnly {
        print("[OK: \(leafFileName)]")
        exit(0)
    }

    // 4. Header validation & atomic in-place fix
    if !noHeaderFix, let fileURL = targetFileURL {
        formatAndVerifyHeader(at: fileURL, leafFileName: leafFileName, currentContent: sourceContent)
    }

    print("[OK: \(leafFileName)] Syntax valid & header verified.")
    exit(0)
}

private func formatAndVerifyHeader(at fileURL: URL, leafFileName: String, currentContent: String) {
    let lineEnding = currentContent.contains("\r\n") ? "\r\n" : "\n"
    let lines = currentContent.components(separatedBy: .newlines)

    var startIndex = 0
    while startIndex < lines.count && lines[startIndex].trimmingCharacters(in: .whitespaces).isEmpty {
        startIndex += 1
    }

    let parentFolder = fileURL.deletingLastPathComponent().lastPathComponent
    let projectRoot = findProjectRoot(from: fileURL.path).deletingPathExtension().lastPathComponent
    let projectName = (parentFolder.isEmpty || parentFolder == ".") ? projectRoot : parentFolder

    // Check if the top line already conforms to // <filename>.swift // <ProjectName> // or // <filename> // <ProjectName>
    if startIndex < lines.count {
        let firstLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        if firstLine.hasPrefix("//") {
            let parts = firstLine.components(separatedBy: "//").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 {
                let headerFile = parts[0]
                if headerFile == leafFileName || headerFile == leafFileName.replacingOccurrences(of: ".swift", with: "") {
                    // Header is already valid
                    return
                }
            }
        }
    }

    // Strip old leading comments if they form an Xcode default header block
    var headerEndIndex = startIndex
    while headerEndIndex < lines.count {
        let line = lines[headerEndIndex].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("//") {
            headerEndIndex += 1
        } else {
            break
        }
    }

    var codeStartIndex = headerEndIndex
    while codeStartIndex < lines.count && lines[codeStartIndex].trimmingCharacters(in: .whitespaces).isEmpty {
        codeStartIndex += 1
    }

    let canonicalHeader = "// \(leafFileName) // \(projectName) //"
    var newLines: [String] = []
    newLines.append(canonicalHeader)
    newLines.append("")
    if codeStartIndex < lines.count {
        newLines.append(contentsOf: lines[codeStartIndex...])
    }

    let newContent = newLines.joined(separator: lineEnding)
    if newContent != currentContent {
        try? newContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

private func printDiffCheckUsage(toStderr: Bool) {
    let usage = """
    Usage:
      XCSwiftMap diff-check [--parse-only] [--no-header-fix] [--stdin] [<file-path>]

    Options:
      --parse-only       Fast syntax parse validation without header modification
      --no-header-fix    Preserve header comments without minifying or updating
      --stdin            Read Swift source code from standard input
    """
    if toStderr {
        fputs(usage + "\n", stderr)
    } else {
        print(usage)
    }
}