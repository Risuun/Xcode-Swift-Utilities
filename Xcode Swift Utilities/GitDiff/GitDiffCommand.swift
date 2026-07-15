// GitDiffCommand.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax
import SwiftParser

func runGitDiff(args: [String]) {
    var isJSON = false
    var cleanArgs: [String] = []
    
    for arg in args {
        if arg == "--json" {
            isJSON = true
        } else {
            cleanArgs.append(arg)
        }
    }
    
    let workspacePath = FileManager.default.currentDirectoryPath
    guard let diffOutput = runGitDiffProcess(args: cleanArgs, workspacePath: workspacePath) else {
        fputs("Error running git diff.\n", stderr)
        exit(1)
    }
    
    let fileDiffs = parseGitDiffOutput(diffOutput)
    if fileDiffs.isEmpty {
        if isJSON {
            print("[]")
        } else {
            print("No modified Swift files found in diff.")
        }
        return
    }
    
    var outputModels: [DiffOutputModel] = []
    
    for fileDiff in fileDiffs {
        let fileURL = URL(fileURLWithPath: fileDiff.filepath, relativeTo: URL(fileURLWithPath: workspacePath))
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            continue
        }
        
        let sourceFile = Parser.parse(source: fileContent)
        let locationConverter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
        let collector = DeclarationCollector(viewMode: .sourceAccurate, locationConverter: locationConverter)
        collector.walk(sourceFile)
        
        var filteredRoots: [DiffNode] = []
        for root in collector.rootNodes {
            if let filtered = filterNode(root, modifiedLines: fileDiff.modifiedLines) {
                filteredRoots.append(filtered)
            }
        }
        
        if filteredRoots.isEmpty {
            continue
        }
        
        if isJSON {
            let modelNodes = filteredRoots.map { convertToModelNode($0) }
            outputModels.append(DiffOutputModel(file: fileDiff.filepath, modifications: modelNodes))
        } else {
            print("Modified: \(fileDiff.filepath)")
            for root in filteredRoots {
                printDiffTree(node: root, indent: "  ")
            }
            print("")
        }
    }
    
    if isJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(outputModels), let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
    }
}
