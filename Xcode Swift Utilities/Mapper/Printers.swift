// Printers.swift // Xcode Swift Utilities

import Foundation

public class SourceMapPrinter {
    let sourceMap: SourceMap
    let isSummary: Bool
    var indentLevel = 0
    
    public init(sourceMap: SourceMap, isSummary: Bool) {
        self.sourceMap = sourceMap
        self.isSummary = isSummary
    }
    
    func printWithIndent(_ text: String) {
        let indent = String(repeating: "    ", count: indentLevel)
        print("\(indent)\(text)")
    }
    
    private func commentStr(for location: SourceLocationModel?) -> String {
        return location.map { " // \($0.file):\($0.line)" } ?? ""
    }
    
    public func printMap() {
        for prop in sourceMap.properties {
            printProperty(prop)
        }
        for function in sourceMap.functions {
            printFunction(function)
        }
        for typealiasDecl in sourceMap.typealiases {
            printTypealias(typealiasDecl)
        }
        
        if !sourceMap.properties.isEmpty || !sourceMap.functions.isEmpty || !sourceMap.typealiases.isEmpty {
            print("")
        }
        
        for type in sourceMap.types {
            printType(type)
        }
    }
    
    func printType(_ type: TypeModel) {
        let prefix = type.accessLevel.isEmpty ? "" : "\(type.accessLevel) "
        let inheritanceStr = type.inheritance.isEmpty ? "" : " : \(type.inheritance.joined(separator: ", "))"
        let kindKeyword = type.kind
        let locComment = commentStr(for: type.location)
        
        printWithIndent("\(prefix)\(kindKeyword) \(type.name)\(inheritanceStr) {\(locComment)")
        
        if isSummary {
            printWithIndent("}")
            return
        }
        
        indentLevel += 1
        
        for enumCase in type.cases {
            printWithIndent("case \(enumCase)")
        }
        if !type.cases.isEmpty { print("") }
        
        for assoc in type.associatedtypes {
            let assocPrefix = assoc.accessLevel.isEmpty ? "" : "\(assoc.accessLevel) "
            let inheritanceStr = (assoc.inheritance?.isEmpty ?? true) ? "" : " : \(assoc.inheritance!)"
            let assocComment = commentStr(for: assoc.location)
            printWithIndent("\(assocPrefix)associatedtype \(assoc.name)\(inheritanceStr)\(assocComment)")
        }
        
        for ta in type.typealiases {
            printTypealias(ta)
        }
        
        for prop in type.properties {
            printProperty(prop)
        }
        
        for initDecl in type.initializers {
            let initPrefix = initDecl.accessLevel.isEmpty ? "" : "\(initDecl.accessLevel) "
            let initComment = commentStr(for: initDecl.location)
            printWithIndent("\(initPrefix)init\(initDecl.signature)\(initComment)")
        }
        
        for function in type.functions {
            printFunction(function)
        }
        
        for nested in type.nestedTypes {
            print("")
            printType(nested)
        }
        
        indentLevel -= 1
        printWithIndent("}")
    }
    
    func printProperty(_ prop: PropertyModel) {
        let prefix = prop.accessLevel.isEmpty ? "" : "\(prop.accessLevel) "
        let locComment = commentStr(for: prop.location)
        if let type = prop.type {
            printWithIndent("\(prefix)\(prop.specifier) \(prop.name): \(type)\(locComment)")
        } else {
            printWithIndent("\(prefix)\(prop.specifier) \(prop.name)\(locComment)")
        }
    }
    
    func printFunction(_ function: FunctionModel) {
        let prefix = function.accessLevel.isEmpty ? "" : "\(function.accessLevel) "
        let locComment = commentStr(for: function.location)
        printWithIndent("\(prefix)func \(function.name)\(function.signature)\(locComment)")
    }
    
    func printTypealias(_ ta: TypealiasModel) {
        let prefix = ta.accessLevel.isEmpty ? "" : "\(ta.accessLevel) "
        let locComment = commentStr(for: ta.location)
        printWithIndent("\(prefix)typealias \(ta.name) = \(ta.underlyingType)\(locComment)")
    }
}

public class MermaidPrinter {
    let sourceMap: SourceMap
    let isSummary: Bool
    
    public init(sourceMap: SourceMap, isSummary: Bool) {
        self.sourceMap = sourceMap
        self.isSummary = isSummary
    }
    
    public func printDiagram() {
        print("classDiagram")
        
        var relationships: [String] = []
        
        func printType(_ type: TypeModel) {
            print("    class \(type.name) {")
            
            if !isSummary {
                for prop in type.properties {
                    let pVis = mermaidVisibility(for: prop.accessLevel)
                    let typeStr = prop.type.map { ": \($0)" } ?? ""
                    print("        \(pVis)\(prop.specifier) \(prop.name)\(typeStr)")
                }
                
                for initDecl in type.initializers {
                    let iVis = mermaidVisibility(for: initDecl.accessLevel)
                    print("        \(iVis)init\(initDecl.signature)")
                }
                
                for function in type.functions {
                    let fVis = mermaidVisibility(for: function.accessLevel)
                    print("        \(fVis)func \(function.name)\(function.signature)")
                }
            }
            
            print("    }")
            
            for base in type.inheritance {
                relationships.append("    \(base) <|-- \(type.name)")
            }
            
            for nested in type.nestedTypes {
                printType(nested)
                relationships.append("    \(type.name) +-- \(nested.name)")
            }
        }
        
        for type in sourceMap.types {
            printType(type)
        }
        
        for rel in relationships {
            print(rel)
        }
    }
    
    private func mermaidVisibility(for accessLevel: String) -> String {
        let level = accessLevel.lowercased()
        if level.contains("public") || level.contains("open") {
            return "+"
        } else if level.contains("private") || level.contains("fileprivate") {
            return "-"
        } else {
            return "~"
        }
    }
}
