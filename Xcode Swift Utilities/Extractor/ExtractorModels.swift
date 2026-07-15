// ExtractorModels.swift // Xcode Swift Utilities

import Foundation

public class SchemaModel: Codable {
    public var name: String
    public var location: SourceLocationModel?
    public var properties: [SchemaProperty] = []
    
    public init(name: String) {
        self.name = name
    }
}

public struct SchemaProperty: Codable {
    public var name: String
    public var type: String
    public var location: SourceLocationModel?
    
    public init(name: String, type: String, location: SourceLocationModel?) {
        self.name = name
        self.type = type
        self.location = location
    }
}

public struct SchemaQuery: Codable {
    public var name: String
    public var type: String
    public var location: SourceLocationModel?
    
    public init(name: String, type: String, location: SourceLocationModel?) {
        self.name = name
        self.type = type
        self.location = location
    }
}

public struct SchemaRelationship: Codable {
    public var from: String
    public var to: String
    public var type: String // "1-to-1" or "1-to-many"
    
    public init(from: String, to: String, type: String) {
        self.from = from
        self.to = to
        self.type = type
    }
}

public struct SchemaModelOutput: Codable {
    public var name: String
    public var location: SourceLocationModel?
    public var properties: [SchemaProperty]
    public var relationships: [SchemaRelationship]
}

public struct SchemaOutput: Codable {
    public var models: [SchemaModelOutput]
    public var queries: [SchemaQuery]
}
