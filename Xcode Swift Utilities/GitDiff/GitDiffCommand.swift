// GitDiffCommand.swift // XCEdit //

import Foundation
import SwiftSyntax
import SwiftParser

public struct GitDiffRunner {
    public static func run(args: [String], workspacePath: String = FileManager.default.currentDirectoryPath) {
        var isJSON = false
        var gitArgs = ["diff", "-U0"]
        let sanitizedWorkspace = sanitizePath(workspacePath)
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--json" {
                isJSON = true
            } else if arg == "--branch" || arg == "-b" {
                if i + 1 < args.count {
                    gitArgs.append(sanitizePath(args[i + 1]))
                    i += 1
                }
            } else if arg.hasPrefix("--branch=") {
                gitArgs.append(sanitizePath(String(arg.dropFirst("--branch=".count))))
            } else if arg == "--staged" || arg == "--cached" {
                gitArgs.append(arg)
            } else if !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: sanitizePath(arg)) {
                // Ignore path if passed separately
            }
            i += 1
        }
        
        guard let diffOutput = executeGit(args: gitArgs, at: sanitizedWorkspace) else {
            fputs("[ERROR: Failed to execute git diff in \(sanitizedWorkspace)]\n", stderr)
            return
        }
        
        let fileDiffs = parseGitDiffOutput(diffOutput)
        if fileDiffs.isEmpty {
            if isJSON {
                print("[]")
            } else {
                print("[OK: No modified Swift declarations found in diff]")
            }
            return
        }
        
        var outputModels: [DiffOutputModel] = []
        
        for fileDiff in fileDiffs {
            let fileURL = URL(fileURLWithPath: sanitizedWorkspace).appendingPathComponent(fileDiff.filepath)
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
                print("[MODIFIED] \(fileDiff.filepath)")
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
    private static func executeGit(args: [String], at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        final class DataBuffer: @unchecked Sendable {
            var data = Data()
        }
        let outputBuffer = DataBuffer()
        let group = DispatchGroup()
        
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBuffer.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
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
            return String(data: outputBuffer.data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

public func runGitDiff(args: [String]) {
    GitDiffRunner.run(args: args)
}