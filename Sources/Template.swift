import KittenCore
import Foundation

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

public protocol ContextValue {}

public struct TemplateContext : ContextValue, SerializableObject, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral {
    public typealias SupportedValue = ContextValue
    var storage = [(String, SupportedValue)]()
    
    public init(dictionary: [String : SupportedValue]) {
        for pair in dictionary {
            storage.append(pair)
        }
    }
    
    public init(dictionaryLiteral elements: (String, SupportedValue)...) {
        for (key, value) in elements {
            storage.append((key, value))
        }
    }
    
    public init(arrayLiteral elements: SupportedValue...) {
        for (key, value) in elements.enumerated() {
            storage.append((key.description, value))
        }
    }
    
    public func getKeys() -> [String] {
        return storage.map {
            $0.0
        }
    }
    
    public func getValues() -> [ContextValue] {
        return storage.map {
            $0.1
        }
    }
    
    public func getKeyValuePairs() -> [String : ContextValue] {
        var pairs = [String: ContextValue]()
        
        for (key, value) in storage {
            pairs[key] = value
        }
        
        return pairs
    }
    
    public func getValue(forKey key: String) -> ContextValue? {
        return storage.first {
            $0.0 == key
        }?.1
    }
    
    public mutating func setValue(to newValue: ContextValue?, forKey key: String) {
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
}

extension String: ContextValue {}
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
                
                let firstPart = path.removeFirst()
                
                guard var value = context.getValue(forKey: firstPart) else {
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
                            if let object = contextValue as? TemplateContext {
                                for value in object.getValues() {
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
