// main.swift // Xcode Swift Utilities

import Foundation

func main() {
    let arguments = CommandLine.arguments
    let binaryName = URL(fileURLWithPath: arguments[0]).lastPathComponent
    var args = arguments
    args.removeFirst() // remove program name
    
    // Support executing as XCGitDiff binary directly
    if binaryName == "XCGitDiff" {
        runGitDiff(args: args)
        return
    }
    
    guard !args.isEmpty else {
        printUsage(toStderr: true)
        exit(1)
    }
    
    if args[0] == "--help" || args[0] == "-h" {
        printUsage(toStderr: false)
        exit(0)
    }
    
    if args[0] == "search" {
        args.removeFirst()
        runSearch(args: args)
    } else if args[0] == "index" {
        args.removeFirst()
        runIndex(args: args)
    } else if args[0] == "extract-schema" {
        args.removeFirst()
        runExtractSchema(args: args)
    } else if args[0] == "view-skeleton" {
        args.removeFirst()
        runViewSkeleton(args: args)
    } else if args[0] == "trace-state" || args[0] == "scope-check" {
        args.removeFirst()
        runTraceState(args: args)
    } else if args[0] == "spm-summary" {
        args.removeFirst()
        runSPMSummary(args: args)
    } else if args[0] == "audit-memory" {
        args.removeFirst()
        runAuditMemory(args: args)
    } else if args[0] == "git-diff" {
        args.removeFirst()
        runGitDiff(args: args)
    } else if args[0] == "locate" {
        args.removeFirst()
        runLocate(args: args)
    } else if args[0] == "preview-render" {
        args.removeFirst()
        runPreviewRender(args: args)
    } else if args[0] == "xcassets" {
        args.removeFirst()
        runXCAssets(args: args)
    } else {
        runSemanticMap(args: args)
    }
}

func printUsage(toStderr: Bool = false) {
    let usageText = """
Usage:
  XCSwiftMap [--json] [--summary] [--mermaid] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap search "<concept>" [path] [--limit <n>] [--json]
  XCSwiftMap index [path]
  XCSwiftMap locate <symbol-query> [directory-or-file-path] [--json]
  XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap view-skeleton <file-path>
  XCSwiftMap scope-check [--json] <directory-or-file-path>
  XCSwiftMap trace-state [--json] <directory-or-file-path>
  XCSwiftMap spm-summary [--json] [directory-path]
  XCSwiftMap audit-memory [--json] <directory-or-file-path>
  XCSwiftMap git-diff [--json] [--branch <branch>]
  XCSwiftMap preview-render [--png] <file-path>
  XCSwiftMap xcassets [--json] [--exclude <patterns>] <directory-path>
"""
    if toStderr {
        fputs(usageText + "\n", stderr)
    } else {
        print(usageText)
    }
}

main()
