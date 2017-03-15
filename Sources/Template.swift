import KittenCore
import Foundation

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
        
        func parseCString() throws -> KittenBytes {
            var stringData = [UInt8]()
            
            while position < compiled.count, compiled[position] != 0x00 {
                defer { position += 1 }
                stringData.append(compiled[position])
            }
            
            position += 1
            
            return KittenBytes(stringData)
        }
        
        func runExpression(inContext context: TemplateContext) throws -> ContextValue? {
            switch compiled[position] {
            case Expression.variable:
                position += 1
                var path = [KittenBytes]()
                
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
                        if let newValue = object.getValue(forKey: key) {
                            value = newValue
                        } else {
                            return nil
                        }
                    } else if let sequence = value as? TemplateSequence {
                        if let key = Int(byteString: key.bytes), key < sequence.storage.count {
                            print(key)
                            value = sequence.storage[key]
                        } else {
                            return nil
                        }
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

extension Int {
    init?(byteString: [UInt8]) {
        var me = 0
        var power = 1
        
        for byte in byteString.reversed() {
            defer { power = power * 10 }
            
            guard byte >= 0x30 && byte <= 0x39 else {
                return nil
            }
            
            let byte = byte - 0x30
            
            me += Int(byte) * power
        }
        
        self = me
    }
}

extension ContextValue {
    func makeTemplatingUTF8String() -> [UInt8] {
        switch self {
        case let string as String:
            return [UInt8](string.utf8)
        case let int as Int:
            return [UInt8](int.description.utf8)
        case let double as Double:
            return [UInt8](double.description.utf8)
        case let string as StaticString:
            var data = [UInt8](repeating: 0, count: string.utf8CodeUnitCount)
            memcpy(&data, string.utf8Start, string.utf8CodeUnitCount)
            return data
        case let string as KittenBytes:
            return string.bytes
        case let bool as Bool:
            return bool ? "true".makeTemplatingUTF8String() : "false".makeTemplatingUTF8String()
        default:
            return []
        }
    }
}
