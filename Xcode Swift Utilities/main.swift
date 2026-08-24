// main.swift // XCEdit //

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
    } else if args[0] == "inspect-model" {
        args.removeFirst()
        runInspectModel(args: args)
    } else if args[0] == "find-usage" {
        args.removeFirst()
        runFindUsage(args: args)
    } else if args[0] == "audit-filters" {
        args.removeFirst()
        runAuditFilters(args: args)
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
    } else if args[0] == "diff-check" {
        args.removeFirst()
        runDiffCheck(args: args)
    } else if args[0] == "view-scrub" {
        args.removeFirst()
        runViewScrub(args: args)
    } else if args[0] == "pack-context" {
        args.removeFirst()
        runPackContext(args: args)
    } else if args[0] == "mini-map" {
        args.removeFirst()
        runMiniMap(args: args)
    } else if args[0] == "trace-state-logical" {
        args.removeFirst()
        runTraceStateLogical(args: args)
    } else if args[0] == "flatten-deps" {
        args.removeFirst()
        runFlattenDeps(args: args)
    } else if args[0] == "bind-check" {
        args.removeFirst()
        runBindCheck(args: args)
    } else if args[0] == "intent-blame" {
        args.removeFirst()
        runIntentBlame(args: args)
    } else {
        runSemanticMap(args: args)
    }
}

func printUsage(toStderr: Bool = false) {
    let usageText = """
Usage:
  XCSwiftMap [--json] [--summary] [--mermaid] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap diff-check [--parse-only] [--no-header-fix] [--stdin] [<file-path>]
  XCSwiftMap search "<concept>" [path] [--limit <n>] [--json]
  XCSwiftMap index [path]
  XCSwiftMap inspect-model --model <ModelName> [directory-or-file-path] [--json]
  XCSwiftMap locate <symbol-query> [directory-or-file-path] [--json]
  XCSwiftMap find-usage <symbol> [directory-or-file-path] [--json]
  XCSwiftMap audit-filters --model <ModelName> [directory-or-file-path] [--json]
  XCSwiftMap extract-schema [--json] [--exclude <patterns>] <file-or-directory-path>
  XCSwiftMap view-skeleton <file-path>
  XCSwiftMap view-scrub <file-path>
  XCSwiftMap pack-context <file-path>
  XCSwiftMap mini-map <file-path>
  XCSwiftMap scope-check [--json] <directory-or-file-path>
  XCSwiftMap trace-state [--json] <directory-or-file-path>
  XCSwiftMap trace-state-logical <file-path>
  XCSwiftMap flatten-deps --symbol <symbol> [--directory <path>]
  XCSwiftMap bind-check --model-path <path> --view-path <path>
  XCSwiftMap intent-blame <symbol> <file-path>
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
