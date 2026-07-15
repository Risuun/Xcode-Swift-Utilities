// Models.swift // Xcode Swift Utilities

import Foundation

public struct SourceLocationModel: Codable {
    public var file: String
    public var line: Int
    
    public init(file: String, line: Int) {
        self.file = file
        self.line = line
    }
}
