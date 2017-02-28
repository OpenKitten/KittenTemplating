import KittenCore
import Foundation

public enum TemplateData : DataType {
    public typealias Object = TemplateContext
    public typealias Sequence = TemplateSequence
    public typealias SupportedValue = ContextValue
}

public protocol TemplatingSyntax {
    static func compile(_ file: String, atPath path: String, inContext context: Any?) throws -> Template
    static func compile(fromData data: [UInt8], atPath path: String, inContext context: Any?) throws -> Template
}

extension TemplatingSyntax {
    public static func compile(_ file: String, atPath path: String, inContext context: Any? = nil) throws -> Template {
        guard let data = FileManager.default.contents(atPath: path + file) else {
            throw TemplateError.fileDoesNotExist(atPath: path + file)
        }
        
        return try Self.compile(fromData: Array(data), atPath: path, inContext: context)
    }
}

public protocol ContextValue : Convertible {}
public protocol SimpleContextValue : ContextValue, SimpleConvertible {}

public struct TemplateSequence : InitializableSequence, ContextValue, ExpressibleByArrayLiteral {
    public typealias SupportedValue = ContextValue
    
    public init(arrayLiteral elements: ContextValue...) {
        storage = elements
    }
    
    var storage = [SupportedValue]()
    
    public init<S>(sequence: S) where S : Sequence, S.Iterator.Element == SupportedValue {
        storage = Array(sequence)
    }
    
    public func makeIterator() -> IndexingIterator<[ContextValue]> {
        return storage.makeIterator()
    }
}

public struct TemplateContext : ContextValue, InitializableObject, ExpressibleByDictionaryLiteral {
    public /// Creates an instance initialized with the given key-value pairs.
    init(dictionaryLiteral elements: (String, ContextValue)...) {
        self.storage = elements
    }
    
    public init<S>(sequence: S) where S : Sequence, S.Iterator.Element == SupportedValue {
        self.storage = Array(sequence)
    }
    
    public typealias ObjectKey = String
    public typealias ObjectValue = ContextValue
    public typealias SupportedValue = (String, ContextValue)
    
    var storage = [(String, ContextValue)]()
    
    public var dictionaryRepresentation: [String: ContextValue] {
        var dict = [String: ContextValue]()
        
        for (key, value) in storage {
            dict[key] = value
        }
        
        return dict
    }
    
    func getValue(forKey key: String) -> ContextValue? {
        return self.storage.first(where: { $0.0 == key })?.1
    }
    
    mutating func setValue(to newValue: ContextValue?, forKey key: String) {
        let position = storage.index(where: {
            $0.0 == key
        })
        
        if let newValue = newValue {
            if let position = position {
                storage[position] = (key, newValue)
            } else {
                storage.append((key, newValue))
            }
        } else if let position = position {
            storage.remove(at: position)
        }
    }
    
    public func makeIterator() -> AnyIterator<(String, ContextValue)> {
        var storageIterator = storage.makeIterator()
        
        return AnyIterator {
            return storageIterator.next()
        }
    }
}

extension String: ContextValue {}
extension Double: ContextValue {}
extension Int: ContextValue {}
extension Bool: ContextValue {}

public final class Template {
    public let compiled: [UInt8]
    
    public init(compiled data: [UInt8]) {
        self.compiled = data
    }
    
    public init(raw template: String) throws {
        self.compiled = try Template.compile(template)
    }
    
    public func run<S: InitializableObject>(inContext context: S) throws -> [UInt8] {
        
        return try self.run(inContext: context.convert(to: TemplateData.self) as? TemplateContext ?? [:])
    }
    
    public func run(inContext context: TemplateContext = [:]) throws -> [UInt8] {
        var position = 0
        var output = [UInt8]()
        
        func parseCString() throws -> String {
            var stringData = [UInt8]()
            
            while position < compiled.count, compiled[position] != 0x00 {
                defer { position += 1 }
                stringData.append(compiled[position])
            }
            
            position += 1
            
            guard let string = String(bytes: stringData, encoding: String.Encoding.utf8) else {
                throw TemplateError.invalidString
            }
            
            return string
        }
        
        func runExpression(inContext context: TemplateContext) throws -> ContextValue? {
            switch compiled[position] {
            case Expression.variable:
                position += 1
                var path = [String]()
                
                while compiled[position] != 0x00 {
                    path.append(try parseCString())
                }
                
                position += 1
                
                guard path.count >= 1 else {
                    throw TemplateError.emptyVariablePath
                }
                
                guard var value = context.getValue(forKey: path.removeFirst()) else {
                    return nil
                }
                
                if path.count == 0 {
                    return value
                }
                
                for key in path {
                    if let object = value as? TemplateContext {
                        guard let newValue = object.getValue(forKey: key) else {
                            return nil
                        }
                        
                        value = newValue
                    } else if let sequence = value as? TemplateSequence, let position = Int(key), position < sequence.storage.count {
                        value = sequence.storage[position]
                    } else {
                        return nil
                    }
                }
                
                return value
            default:
                throw TemplateError.invalidExpression(compiled[position])
            }
        }
        
        func runStatements(inContext context: TemplateContext) throws {
            while position < compiled.count {
                elementSwitch: switch compiled[position] {
                case 0x00:
                    position += 1
                    return
                case Element.rawData:
                    try compiled.require(5, afterPosition: position)
                    position += 1
                    
                    let rawDataSize = Int(compiled[position..<position + 4].makeUInt32())
                    position += 4
                    
                    try compiled.require(rawDataSize, afterPosition: position)
                    
                    output.append(contentsOf: Array(compiled[position..<position + rawDataSize]))
                    position += rawDataSize
                case Element.statement:
                    position += 1
                    
                    switch compiled[position] {
                    case Statement.if:
                        position += 1
                        
                        var expression = false
                        
                        if let anyContextValue = try runExpression(inContext: context), let booleanExpression = anyContextValue as? Bool {
                            expression = booleanExpression
                        }
                        
                        guard position + 8 < compiled.count else {
                            throw TemplateError.unexpectedEndOfTemplate
                        }
                        
                        let trueOffset = Int(compiled[position..<position + 4].makeUInt32())
                        position += 4
                        let falseOffset = Int(compiled[position..<position + 4].makeUInt32())
                        position += 4
                        
                        guard position + trueOffset + falseOffset < compiled.count else {
                            throw TemplateError.unexpectedEndOfTemplate
                        }
                        
                        if expression {
                            try runStatements(inContext: context)
                            position += falseOffset
                        } else {
                            position += trueOffset
                            
                            if falseOffset > 0 {
                                try runStatements(inContext: context)
                            }
                        }
                    case Statement.for:
                        position += 1
                        
                        let variableName = try parseCString()
                        let contextValue = try runExpression(inContext: context)
                        
                        var newContext = context
                        
                        let loopOffset = Int(compiled[position..<position + 4].makeUInt32())
                        position += 4
                        
                        let oldPosition = position
                        
                        if let contextValue = contextValue {
                            if let sequence = contextValue as? TemplateSequence {
                                for value in sequence {
                                    defer {
                                        position = oldPosition
                                    }
                                    
                                    newContext.setValue(to: value, forKey: variableName)
                                    try runStatements(inContext: newContext)
                                }
                            } else if let object = contextValue as? TemplateContext {
                                for (_, value) in object {
                                    defer {
                                        position = oldPosition
                                    }
                                    
                                    newContext.setValue(to: value, forKey: variableName)
                                    try runStatements(inContext: newContext)
                                }
                            } else {
                                defer {
                                    position = oldPosition
                                }
                                
                                newContext.setValue(to: contextValue, forKey: variableName)
                                try runStatements(inContext: newContext)
                            }
                        }
                    
                        position += loopOffset
                        
                        guard compiled[position] == 0x00 else {
                            throw TemplateError.unclosedLoop
                        }
                        
                        position += 1
                    case Statement.print:
                        position += 1
                        
                        guard let contextValue = try runExpression(inContext: context) else {
                            break elementSwitch
                        }
                        
                        output.append(contentsOf: contextValue.makeTemplatingUTF8String())
                    default:
                        throw TemplateError.invalidStatement(compiled[position])
                    }
                default:
                    throw TemplateError.invalidElement(compiled[position])
                }
            }
        }
        
        try runStatements(inContext: context)
        
        return output
    }
    
    private static func compile(_ template: String) throws -> [UInt8] {
        return []
    }
}

enum HTMLCharacters: UInt8 {
    case quotation = 0x22
    case ampersand = 0x26
    case apostrophe = 0x27
    case lessThan = 0x3c
    case greaterThan = 0x3e
    
    var escaped: [UInt8] {
        var buffer: [UInt8]
        
        switch self {
        case .quotation:
            buffer = [UInt8]("quot".utf8)
        case .ampersand:
            buffer = [UInt8]("amp".utf8)
        case .apostrophe:
            buffer = [SpecialCharacters.pound] + [UInt8]("39".utf8)
        case .lessThan:
            buffer = [UInt8]("lt".utf8)
        case .greaterThan:
            buffer = [UInt8]("gt".utf8)
        }
        
        return [HTMLCharacters.ampersand.rawValue] + buffer + [SpecialCharacters.semicolon]
    }
}

extension String {
    public func htmlEscaped() -> String {
        var buffer = [UInt8]()
        
        [UInt8](self.utf8).forEach { byte in
            if let character = HTMLCharacters(rawValue: byte) {
                buffer.append(contentsOf: character.escaped)
            } else {
                buffer.append(byte)
            }
        }
        
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }
}

extension ContextValue {
    func makeTemplatingUTF8String() -> [UInt8] {
        switch self {
        case let string as String:
            return [UInt8](string.utf8)
        case let int as Int:
            return [UInt8](int.description.utf8)
        case let bool as Bool:
            return bool ? "true".makeTemplatingUTF8String() : "false".makeTemplatingUTF8String()
        default:
            return []
        }
    }
}
