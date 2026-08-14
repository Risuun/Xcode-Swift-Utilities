// Models.swift // Common

import Foundation

public struct SourceLocationModel: Codable {
    public var file: String
    public var line: Int
    public var column: Int
    
    public init(file: String, line: Int, column: Int = 1) {
        self.file = file
        self.line = line
        self.column = column
    }
}
