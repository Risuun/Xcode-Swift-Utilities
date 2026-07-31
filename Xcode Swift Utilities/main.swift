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
        printUsage()
        exit(1)
    }
    
    if args[0] == "extract-schema" {
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

func printUsage() {
    fputs("""
Usage:
  XCSwiftMap [--json] [--summary] [--mermaid] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap view-skeleton <file-path>
  XCSwiftMap scope-check [--json] <directory-or-file-path>
  XCSwiftMap trace-state [--json] <directory-or-file-path>
  XCSwiftMap spm-summary [--json] [directory-path]
  XCSwiftMap audit-memory [--json] <directory-or-file-path>
  XCSwiftMap git-diff [--json] [--branch <branch>]
  XCSwiftMap xcassets [--json] [--exclude <patterns>] <directory-path>
""", stderr)
}

main()
