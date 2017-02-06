import Foundation
import MongoKitten

public protocol TemplatingSyntax {
    static func compile(_ file: String, atPath path: String, inContext context: Any?) throws -> Template
    static func compile(fromData data: [UInt8], atPath path: String, inContext context: Any?) throws -> Template
}

extension TemplatingSyntax {
    public static func compile(_ file: String, atPath path: String, inContext context: Any? = nil) throws -> Template {
        guard let data = FileManager.default.contents(atPath: path + file) else {
            throw TemplateError.fileDoesNotExist(atPath: path + file)
        }
        
        return try Self.compile(fromData: try data.makeBytes(), atPath: path, inContext: context)
    }
}

public protocol ContextValueConvertible {
    func makeContextValue() ->Template.Context.ContextValue
}

public protocol DocumentRepresentable {
    func makeDocument() -> Document
}

extension Document: DocumentRepresentable {
    public func makeDocument() -> Document {
        return self
    }
}

extension Document: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension String: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension Int: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension Int32: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension Int64: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension Bool: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension Date: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}
extension ObjectId: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

extension RegularExpression: ContextValueConvertible {
    public func makeContextValue() -> Template.Context.ContextValue {
        return .value(self)
    }
}

public final class Template : CustomValueConvertible {
    public let compiled: [UInt8]
    
    public init(compiled data: [UInt8]) {
        self.compiled = data
    }
    
    public init?(_ value: BSONPrimitive) {
        guard let value = value as? Binary else {
            return nil
        }
        
        self.compiled = value.makeBytes()
    }
    
    public func makeBSONPrimitive() -> BSONPrimitive {
        return Binary(data: self.compiled, withSubtype: .generic)
    }
    
    public init(raw template: String) throws {
        self.compiled = try Template.compile(template)
    }
    
    public struct Context: ExpressibleByDictionaryLiteral {
        public enum ContextValue: ContextValueConvertible {
            case cursor(Cursor<Document>)
            case value(ValueConvertible)
            
            public func makeContextValue() -> ContextValue {
                return self
            }
        }
        
        var context: [String: ContextValue]
        
        public init(dictionaryLiteral elements: (String, ContextValueConvertible)...) {
            var context = [String: ContextValue]()
            
            for (key, value) in elements {
                context[key] = value.makeContextValue()
            }
            
            self.context = context
        }
    }
    
    public func run(inContext context: Context = [:]) throws -> [UInt8] {
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
                throw DeserializationError.unableToInstantiateString(fromBytes: Array(stringData))
            }
            
            return string
        }
        
        func runExpression(inContext context: Context) throws -> Context.ContextValue? {
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
                
                guard let contextValue = context.context[firstPart] else {
                    return nil
                }
                
                if case .value(let value) = contextValue {
                    if path.count == 0 {
                        return .value(value)
                    }
                    
                    guard let doc = value as? Document, let value = doc[raw: path] else {
                        return nil
                    }
                    
                    return .value(value)
                }
                
                guard path.count == 0 else {
                    return nil
                    // TODO: discuss: throw error?
                }
                
                return contextValue
            default:
                throw TemplateError.invalidExpression(compiled[position])
            }
        }
        
        func runStatements(inContext context: Context) throws {
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
                        
                        if let anyContextValue = try runExpression(inContext: context), case .value(let anyExpression) = anyContextValue, let booleanExpression = anyExpression as? Bool {
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
                            switch contextValue {
                            case .cursor(let cursor):
                                for document in cursor {
                                    defer {
                                        position = oldPosition
                                    }
                                    newContext.context[variableName] = .value(document)
                                    try runStatements(inContext: newContext)
                                }
                            case .value(let value):
                                if let document = value as? Document, document.validatesAsArray() {
                                    for (_, value) in document {
                                        defer {
                                            position = oldPosition
                                        }
                                        newContext.context[variableName] = .value(value)
                                        try runStatements(inContext: newContext)
                                    }
                                } else {
                                    defer {
                                        position = oldPosition
                                    }
                                    newContext.context[variableName] = contextValue
                                    try runStatements(inContext: newContext)
                                }
                            }
                        }
                        
                        position += loopOffset
                        
                        guard compiled[position] == 0x00 else {
                            throw TemplateError.unclosedLoop
                        }
                        
                        position += 1
                    case Statement.print:
                        position += 1
                        
                        guard let contextValue = try runExpression(inContext: context), case .value(let value) = contextValue else {
                            break elementSwitch
                        }
                        
                        output.append(contentsOf: value.makeTemplatingUTF8String())
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

extension ValueConvertible {
    func makeTemplatingUTF8String() -> [UInt8] {
        switch self.makeBSONPrimitive() {
        case is String:
            return [UInt8]((self as! String).utf8)
        case is Int32:
            return [UInt8]((self as! Int32).description.utf8)
        case is Int64:
            return [UInt8]((self as! Int64).description.utf8)
        case is ObjectId:
            return [UInt8]((self as! ObjectId).hexString.utf8)
//        case is Int64:
//            return [UInt8]((self as! Int64).description.utf8)
//        case is Int64:
//            return [UInt8]((self as! Int64).description.utf8)
        default:
            return []
        }
    }
}
