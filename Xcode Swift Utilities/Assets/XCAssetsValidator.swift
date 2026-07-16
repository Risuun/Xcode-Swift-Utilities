// XCAssetsValidator.swift // Xcode Swift Utilities

import Foundation
import SwiftSyntax
import SwiftParser

public struct AssetInfo: Codable {
    public let name: String
    public let type: String // image, color, data, symbol, appicon
    public let path: String
}

public struct AssetReference: Codable {
    public let name: String
    public let file: String
    public let line: Int
}

public struct XCAssetsReport: Codable {
    public let unusedAssets: [AssetInfo]
    public let missingReferences: [AssetReference]
}

public class XCAssetsValidator {
    private let projectPath: String
    private let excludes: [String]
    
    public init(projectPath: String, excludes: [String]) {
        self.projectPath = projectPath
        self.excludes = excludes
    }
    
    public func run(isJSON: Bool) {
        // 1. Scan for asset catalogs and their contents
        let assets = scanAssetCatalogs()
        
        // 2. Scan for references in source code
        let (preciseStringRefs, allStringRefs, memberRefs, nonSwiftRefs) = scanReferences(assets: assets)
        
        // 3. Match references to assets to find:
        //    - Unused assets: Assets in catalogs with no matching reference in code.
        //    - Missing references: References in code that do not correspond to any asset.
        
        var unusedAssets: [AssetInfo] = []
        let assetNameMap = Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0) })
        let assetSwiftIdentifierMap = Dictionary(uniqueKeysWithValues: assets.map { (swiftSafeIdentifier(from: $0.name), $0) })
        
        // Track which assets have been referenced
        var referencedAssetNames = Set<String>()
        
        // Check ALL string references (exact name match) for unused assets verification
        for ref in allStringRefs {
            if assetNameMap[ref.name] != nil {
                referencedAssetNames.insert(ref.name)
            }
        }
        
        // Check member references (camelCase symbol match)
        for ref in memberRefs {
            if let asset = assetSwiftIdentifierMap[ref.name] {
                referencedAssetNames.insert(asset.name)
            }
        }
        
        // Check non-Swift file references
        for ref in nonSwiftRefs {
            if assetNameMap[ref.name] != nil {
                referencedAssetNames.insert(ref.name)
            } else if let asset = assetSwiftIdentifierMap[ref.name] {
                referencedAssetNames.insert(asset.name)
            }
        }
        
        // Find unused assets
        for asset in assets {
            if !referencedAssetNames.contains(asset.name) {
                unusedAssets.append(asset)
            }
        }
        
        // Find missing references (only look at precise string references)
        var missingReferences: [AssetReference] = []
        for ref in preciseStringRefs {
            if assetNameMap[ref.name] == nil {
                missingReferences.append(ref)
            }
        }
        
        // Report
        if isJSON {
            let report = XCAssetsReport(unusedAssets: unusedAssets, missingReferences: missingReferences)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report), let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("=== XCAssets Analysis Report ===")
            print("Project Path: \(projectPath)")
            print("")
            
            print("--- Unused Assets (\(unusedAssets.count)) ---")
            if unusedAssets.isEmpty {
                print("No unused assets found.")
            } else {
                for asset in unusedAssets.sorted(by: { $0.name < $1.name }) {
                    print("  [\(asset.type)] \(asset.name) // \(asset.path)")
                }
            }
            print("")
            
            print("--- Missing Asset References (\(missingReferences.count)) ---")
            if missingReferences.isEmpty {
                print("No missing asset references found.")
            } else {
                for ref in missingReferences.sorted(by: { $0.name < $1.name }) {
                    print("  Reference \"\(ref.name)\" not found // \(ref.file):\(ref.line)")
                }
            }
        }
    }
    
    // Convert asset name to Swift-safe camelCase identifier
    private func swiftSafeIdentifier(from assetName: String) -> String {
        // If namespaced, only use the last component for identifier check (e.g. "Folder/Asset" -> "asset")
        let lastComponent = assetName.components(separatedBy: "/").last ?? assetName
        guard !lastComponent.isEmpty else { return "" }
        
        var words: [String] = []
        var currentWord = ""
        
        let chars = Array(lastComponent)
        for i in 0..<chars.count {
            let char = chars[i]
            
            if !char.isLetter && !char.isNumber {
                // Word boundary separator
                if !currentWord.isEmpty {
                    words.append(currentWord)
                    currentWord = ""
                }
            } else if char.isUppercase {
                // Check for lowercase-to-uppercase transition (e.g., "rI")
                // or uppercase-to-lowercase transition for acronyms (e.g., "LS" in "URLSession" where we split before "S")
                if !currentWord.isEmpty {
                    let prevChar = chars[i - 1]
                    let hasNextLowercase = (i + 1 < chars.count) && chars[i + 1].isLowercase
                    
                    if prevChar.isLowercase || prevChar.isNumber || hasNextLowercase {
                        words.append(currentWord)
                        currentWord = String(char)
                        continue
                    }
                }
                currentWord.append(char)
            } else {
                currentWord.append(char)
            }
        }
        
        if !currentWord.isEmpty {
            words.append(currentWord)
        }
        
        guard !words.isEmpty else { return lastComponent }
        
        // First word is lowercase
        var result = words[0].lowercased()
        
        // Subsequent words are capitalized
        for word in words.dropFirst() {
            if !word.isEmpty {
                let firstChar = String(word.prefix(1)).uppercased()
                let rest = String(word.dropFirst()).lowercased()
                result += firstChar + rest
            }
        }
        
        return result
    }
    
    private func scanAssetCatalogs() -> [AssetInfo] {
        var assets: [AssetInfo] = []
        let rootURL = URL(fileURLWithPath: projectPath)
        
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if shouldExclude(fileURL.path, patterns: excludes) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            
            if fileURL.pathExtension == "xcassets" {
                assets.append(contentsOf: scanCatalog(at: fileURL))
                enumerator?.skipDescendants()
            }
        }
        
        return assets
    }
    
    private func scanCatalog(at catalogURL: URL) -> [AssetInfo] {
        var results: [AssetInfo] = []
        
        func walk(directoryURL: URL, namespacePrefix: String) {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return
            }
            
            for itemURL in contents {
                let component = itemURL.lastPathComponent
                let ext = itemURL.pathExtension
                
                if ext == "imageset" || ext == "colorset" || ext == "dataset" || ext == "symbolset" || ext == "appiconset" {
                    let type = String(ext.dropLast(3)) // drop "set"
                    let assetNameWithoutExt = itemURL.deletingPathExtension().lastPathComponent
                    let fullName = namespacePrefix + assetNameWithoutExt
                    let relPath = relativePath(of: itemURL, relativeTo: URL(fileURLWithPath: projectPath))
                    results.append(AssetInfo(name: fullName, type: type, path: relPath))
                } else if (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // Check for provides-namespace in Contents.json
                    var providesNamespace = false
                    let contentsJSONURL = itemURL.appendingPathComponent("Contents.json")
                    if let data = try? Data(contentsOf: contentsJSONURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let properties = json["properties"] as? [String: Any],
                       let prov = properties["provides-namespace"] as? Bool {
                        providesNamespace = prov
                    }
                    
                    let nextPrefix = providesNamespace ? (namespacePrefix + component + "/") : namespacePrefix
                    walk(directoryURL: itemURL, namespacePrefix: nextPrefix)
                }
            }
        }
        
        walk(directoryURL: catalogURL, namespacePrefix: "")
        return results
    }
    
    private func scanReferences(assets: [AssetInfo]) -> (preciseStringRefs: [AssetReference], allStringRefs: [AssetReference], memberRefs: [AssetReference], nonSwiftRefs: [AssetReference]) {
        var preciseStringRefs: [AssetReference] = []
        var allStringRefs: [AssetReference] = []
        var memberRefs: [AssetReference] = []
        var nonSwiftRefs: [AssetReference] = []
        
        let rootURL = URL(fileURLWithPath: projectPath)
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        
        var swiftFiles: [URL] = []
        var nonSwiftFiles: [URL] = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if shouldExclude(fileURL.path, patterns: excludes) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator?.skipDescendants()
                }
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            if ext == "swift" {
                swiftFiles.append(fileURL)
            } else if ext == "storyboard" || ext == "xib" || ext == "plist" {
                nonSwiftFiles.append(fileURL)
            }
        }
        
        // 1. Scan Swift files using SwiftSyntax
        let baseFolderURL = URL(fileURLWithPath: projectPath)
        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let sourceFile = Parser.parse(source: content)
            let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
            let converter = SourceLocationConverter(fileName: fileURL.path, tree: sourceFile)
            
            let visitor = SwiftAssetReferenceVisitor(viewMode: .sourceAccurate, filePath: relPath, converter: converter)
            visitor.walk(sourceFile)
            
            preciseStringRefs.append(contentsOf: visitor.preciseStringReferences)
            allStringRefs.append(contentsOf: visitor.allStringReferences)
            memberRefs.append(contentsOf: visitor.memberReferences)
        }
        
        // 2. Scan non-Swift files using delimited text searches for asset names
        for fileURL in nonSwiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = relativePath(of: fileURL, relativeTo: baseFolderURL)
            
            for asset in assets {
                if isAssetReference(in: content, name: asset.name) {
                    nonSwiftRefs.append(AssetReference(name: asset.name, file: relPath, line: 0))
                }
            }
        }
        
        return (preciseStringRefs, allStringRefs, memberRefs, nonSwiftRefs)
    }
    
    private func isAssetReference(in content: String, name: String) -> Bool {
        if content.contains("\"" + name + "\"") {
            return true
        }
        if content.contains(">" + name + "<") {
            return true
        }
        if content.contains("'" + name + "'") {
            return true
        }
        return false
    }
}

// SwiftSyntax Visitor to look for asset references in Swift source code
class SwiftAssetReferenceVisitor: SyntaxVisitor {
    var preciseStringReferences: [AssetReference] = []
    var allStringReferences: [AssetReference] = []
    var memberReferences: [AssetReference] = []
    
    private let filePath: String
    private let converter: SourceLocationConverter
    
    init(viewMode: SyntaxTreeViewMode, filePath: String, converter: SourceLocationConverter) {
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: viewMode)
    }
    
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        var value = ""
        for segment in node.segments {
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                value += stringSegment.content.text
            } else {
                return .visitChildren
            }
        }
        
        let startLoc = node.startLocation(converter: converter)
        let ref = AssetReference(name: value, file: filePath, line: startLoc.line)
        allStringReferences.append(ref)
        
        // Check context to make sure this is likely an asset reference.
        if isAssetInitializerContext(node) {
            preciseStringReferences.append(ref)
        }
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text
        
        var isAssetSymbol = false
        if let base = node.base {
            let baseDesc = base.trimmedDescription
            if baseDesc == "ImageResource" || baseDesc == "ColorResource" {
                isAssetSymbol = true
            }
        } else {
            isAssetSymbol = true
        }
        
        if isAssetSymbol {
            let startLoc = node.startLocation(converter: converter)
            memberReferences.append(AssetReference(name: name, file: filePath, line: startLoc.line))
        }
        
        return .visitChildren
    }
    
    private func isAssetInitializerContext(_ node: StringLiteralExprSyntax) -> Bool {
        var parent: Syntax? = node.parent
        while let current = parent {
            if let call = current.as(FunctionCallExprSyntax.self) {
                let calledDesc = call.calledExpression.trimmedDescription
                let allowedTypes = ["Image", "Color", "UIImage", "UIColor", "NSImage", "NSColor", "Label"]
                for type in allowedTypes {
                    if calledDesc == type || calledDesc == "\(type).init" {
                        return true
                    }
                }
                break
            }
            parent = current.parent
        }
        return false
    }
}
