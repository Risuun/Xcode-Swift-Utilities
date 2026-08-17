// GitDiffModels.swift // GitDiff

import Foundation

public class DiffNode: Codable {
    public var kind: String
    public var name: String
    public var lineRange: ClosedRange<Int>
    public var children: [DiffNode] = []
    
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case lineRangeStart
        case lineRangeEnd
        case children
    }
    
    public init(kind: String, name: String, lineRange: ClosedRange<Int>) {
        self.kind = kind
        self.name = name
        self.lineRange = lineRange
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        let start = try container.decode(Int.self, forKey: .lineRangeStart)
        let end = try container.decode(Int.self, forKey: .lineRangeEnd)
        lineRange = start...end
        children = try container.decode([DiffNode].self, forKey: .children)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(lineRange.lowerBound, forKey: .lineRangeStart)
        try container.encode(lineRange.upperBound, forKey: .lineRangeEnd)
        try container.encode(children, forKey: .children)
    }
}

public struct FileDiff {
    public var filepath: String
    public var modifiedLines: Set<Int>
    
    public init(filepath: String, modifiedLines: Set<Int>) {
        self.filepath = filepath
        self.modifiedLines = modifiedLines
    }
}

public struct DiffNodeModel: Codable {
    public var kind: String
    public var name: String
    public var lineRange: String
    public var children: [DiffNodeModel]
    
    public init(kind: String, name: String, lineRange: String, children: [DiffNodeModel]) {
        self.kind = kind
        self.name = name
        self.lineRange = lineRange
        self.children = children
    }
}

public struct DiffOutputModel: Codable {
    public var file: String
    public var modifications: [DiffNodeModel]
    
    public init(file: String, modifications: [DiffNodeModel]) {
        self.file = file
        self.modifications = modifications
    }
}
