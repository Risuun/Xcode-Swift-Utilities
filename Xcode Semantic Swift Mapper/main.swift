import Foundation
import SwiftSyntax
import SwiftParser

class SwiftMapVisitor: SyntaxVisitor {
    private var indentLevel = 0
    
    private func printWithIndent(_ text: String) {
        let indent = String(repeating: "    ", count: indentLevel)
        print("\(indent)\(text)")
    }
    
    private func printHeader(_ prefix: String, _ keyword: String, _ name: String, _ generics: String, _ inheritance: String) {
        let keywordStr = keyword.isEmpty ? "" : "\(keyword) "
        let inheritanceStr = inheritance.isEmpty ? "" : " \(inheritance)"
        printWithIndent("\(prefix)\(keywordStr)\(name)\(generics)\(inheritanceStr) {")
        indentLevel += 1
    }
    
    private func printFooter() {
        indentLevel -= 1
        printWithIndent("}")
    }
    
    // MARK: - Visit Declarations
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let generics = node.genericParameterClause?.trimmedDescription ?? ""
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        printHeader(prefix, node.structKeyword.text, name, generics, inheritance)
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        printFooter()
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let generics = node.genericParameterClause?.trimmedDescription ?? ""
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        printHeader(prefix, node.classKeyword.text, name, generics, inheritance)
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        printFooter()
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let generics = node.genericParameterClause?.trimmedDescription ?? ""
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        printHeader(prefix, node.enumKeyword.text, name, generics, inheritance)
        return .visitChildren
    }
    
    override func visitPost(_ node: EnumDeclSyntax) {
        printFooter()
    }
    
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        printHeader(prefix, node.protocolKeyword.text, name, "", inheritance)
        return .visitChildren
    }
    
    override func visitPost(_ node: ProtocolDeclSyntax) {
        printFooter()
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let generics = node.genericParameterClause?.trimmedDescription ?? ""
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        printHeader(prefix, node.actorKeyword.text, name, generics, inheritance)
        return .visitChildren
    }
    
    override func visitPost(_ node: ActorDeclSyntax) {
        printFooter()
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let specifier = node.bindingSpecifier.text
        
        for binding in node.bindings {
            let pattern = binding.pattern.trimmedDescription
            if let typeAnnotation = binding.typeAnnotation {
                let type = typeAnnotation.trimmedDescription
                printWithIndent("\(prefix)\(specifier) \(pattern)\(type)")
            } else {
                printWithIndent("\(prefix)\(specifier) \(pattern)")
            }
        }
        return .skipChildren
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let keyword = node.funcKeyword.text
        let name = node.name.text
        let signature = node.signature.trimmedDescription
        printWithIndent("\(prefix)\(keyword) \(name)\(signature)")
        return .skipChildren
    }
    
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let keyword = node.initKeyword.text
        let signature = node.signature.trimmedDescription
        printWithIndent("\(prefix)\(keyword)\(signature)")
        return .skipChildren
    }
    
    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let cases = node.elements.map { $0.trimmedDescription }.joined(separator: ", ")
        printWithIndent("\(prefix)case \(cases)")
        return .skipChildren
    }
    
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let generics = node.genericParameterClause?.trimmedDescription ?? ""
        let underlyingType = node.initializer.trimmedDescription
        printWithIndent("\(prefix)typealias \(name)\(generics) \(underlyingType)")
        return .skipChildren
    }
    
    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        let prefix = node.modifiers.trimmedDescription.isEmpty ? "" : "\(node.modifiers.trimmedDescription) "
        let name = node.name.text
        let inheritance = node.inheritanceClause?.trimmedDescription ?? ""
        let inheritanceStr = inheritance.isEmpty ? "" : " \(inheritance)"
        printWithIndent("\(prefix)associatedtype \(name)\(inheritanceStr)")
        return .skipChildren
    }
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    fputs("Usage: swift-mapper <file-path>\n", stderr)
    exit(1)
}

let filePath = arguments[1]
let fileURL = URL(fileURLWithPath: filePath)

do {
    let fileContent = try String(contentsOf: fileURL, encoding: .utf8)
    let sourceFile = Parser.parse(source: fileContent)
    
    let visitor = SwiftMapVisitor(viewMode: .sourceAccurate)
    visitor.walk(sourceFile)
} catch {
    fputs("Error reading file: \(error.localizedDescription)\n", stderr)
    exit(1)
}
