public typealias LeafCompileContext = LeafSyntax.CompileContext
public typealias LeafCompileClosure = ((LeafCompileContext) throws -> [UInt8])

public protocol LeafTag {
    static var stringName: String { get }
    static var name: [UInt8] { get }
    
    static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure
}

public protocol BasicLeafTag : LeafTag {
    static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8]
}

extension BasicLeafTag {
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        let bitcode = try Self.compile(atPosition: &position, inCode: input, byTemplatingLanguage: language, atPath: path, inContext: context)

        return { _ in
            return bitcode
        }
    }
}

extension LeafTag {
    public static var name: [UInt8] {
        return [UInt8](Self.stringName.utf8)
    }
}

public enum LeafError: Error {
    case nullTerminatorInTemplate
    case tagContainsWhitespace
    case invalidSecondArugmentInLoop
    case unknownTag([UInt8])
    case tagNotOpened
    case tagNotClosed
    case variablePathContainsWhitespace
    case missingQuotationMark
    case invalidString
    case notExported(String)
}

fileprivate func compileVariablePath(fromData path: [UInt8]) throws -> [UInt8] {
    // " "
    guard !path.contains(0x20) else {
        throw LeafError.variablePathContainsWhitespace
    }
    
    return path.map { byte in
        // "."->0x00
        return byte == 0x2e ? 0x00 : byte
        // Once for the last key, once for the path
        } + [0x00, 0x00]
}

public struct LeafPrint : BasicLeafTag {
    public static var stringName: String = ""
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        var variableBytes = [UInt8]()
        
        variableLoop: while position < input.count {
            defer { position += 1 }
            
            // ")"
            if input[position] == 0x29 {
                break variableLoop
            }
            
            variableBytes.append(input[position])
        }
        
        let variablePath = try compileVariablePath(fromData: variableBytes)
        
        return [0x02, 0x03, 0x01] + variablePath
    }
}

public struct LeafEmbed : BasicLeafTag {
    public static var stringName = "embed"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        // " (quotation mark)
        guard input.count + 1 > position, input[position] == 0x22 else {
            throw LeafError.missingQuotationMark
        }

        position += 1
        
        var variableBytes = [UInt8]()
        
        stringLoop: while position < input.count {
            defer { position += 1 }
            
            // "\""
            if input[position] == 0x22 {
                break stringLoop
            }
            
            variableBytes.append(input[position])
        }
        
        // ")"
        guard input.count > position, input[position] == 0x29 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        guard let file = String(bytes: variableBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        var subTemplateCode = try language.compile(file + ".leaf", atPath: path, inContext: context).compiled
        
        subTemplateCode.removeLast()
        
        return subTemplateCode
    }
}

public struct LeafExport : LeafTag {
    public static var stringName = "export"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // " (quotation mark)
        guard input.count + 1 > position, input[position] == 0x22 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        var variableBytes = [UInt8]()
        
        stringLoop: while position < input.count {
            defer { position += 1 }
            
            // "\""
            if input[position] == 0x22 {
                break stringLoop
            }
            
            variableBytes.append(input[position])
        }
        
        // ")"
        guard input.count > position, input[position] == 0x29 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        guard let name = String(bytes: variableBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        let template = try LeafSyntax.parseSubTemplate(atPosition: &position, inCode: input, atPath: path)
        
        var exported = context.options["exports"] as? [String: [UInt8]] ?? [:]
        
        exported[name] = template
        
        context.options["exports"] = exported
        
        return { _ in
            return []
        }
    }
}

public struct LeafImport : LeafTag {
    public static var stringName = "import"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // " (quotation mark)
        guard input.count + 1 > position, input[position] == 0x22 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        var variableBytes = [UInt8]()
        
        stringLoop: while position < input.count {
            defer { position += 1 }
            
            // "\""
            if input[position] == 0x22 {
                break stringLoop
            }
            
            variableBytes.append(input[position])
        }
        
        // ")"
        guard input.count > position, input[position] == 0x29 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        guard let exportName = String(bytes: variableBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        return { context in
            guard let exports = context.options["exports"] as? [String: [UInt8]], let uncompiledTemplate = exports[exportName] else {
                throw LeafError.notExported(exportName)
            }
            
            var subTemplateCode = try language.compile(fromData: uncompiledTemplate, atPath: path, inContext: context).compiled
            
            subTemplateCode.removeLast()
            
            return subTemplateCode
        }
    }
}

public struct LeafExtend : LeafTag {
    public static var stringName = "extend"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // " (quotation mark)
        guard input.count + 1 > position, input[position] == 0x22 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        var variableBytes = [UInt8]()
        
        stringLoop: while position < input.count {
            defer { position += 1 }
            
            // "\""
            if input[position] == 0x22 {
                break stringLoop
            }
            
            variableBytes.append(input[position])
        }
        
        // ")"
        guard input.count > position, input[position] == 0x29 else {
            throw LeafError.missingQuotationMark
        }
        
        position += 1
        
        guard let file = String(bytes: variableBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        return { context in
            var subTemplateCode = try language.compile(file + ".leaf", atPath: path, inContext: context).compiled
            
            subTemplateCode.removeLast()
            
            return subTemplateCode
        }
    }
}

public struct LeafLoop : BasicLeafTag {
    public static var stringName = "loop"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        var newVariableBytes = [UInt8]()
        var oldVariableBytes = [UInt8]()
        
        variableLoop: while position < input.count {
            defer { position += 1 }
            
            // "," " "
            if input[position] == 0x2c || input[position] == 0x20 {
                break variableLoop
            }
            
            oldVariableBytes.append(input[position])
        }
        
        whitespaceLoop: while position < input.count {
            guard input[position] == 0x2c || input[position] == 0x20 || input[position] == 0x0a || input[position] == 0x22 else {
                throw LeafError.invalidSecondArugmentInLoop
            }
            
            defer { position += 1 }
            
            // " (quotation mark)
            if input[position] == 0x22 {
                break whitespaceLoop
            }
        }
        
        variableLoop: while position < input.count {
            defer { position += 1 }
            
            // null terminator && "."
            guard input[position] != 0x00 else {
                throw LeafError.nullTerminatorInTemplate
            }
            
            // " (quotation mark)
            if input[position] == 0x22 {
                break variableLoop
            }
            
            newVariableBytes.append(input[position])
        }
        
        // ")"
        guard input[position] == 0x29 else {
            throw LeafError.invalidSecondArugmentInLoop
        }
        
        let subTemplateCode = try LeafSyntax.compileSubTemplate(atPosition: &position, inCode: input, atPath: path)
        
        let oldVariablePath = try compileVariablePath(fromData: oldVariableBytes)
        
        var compiledLoop: [UInt8] = [0x02, 0x02]
        compiledLoop.append(contentsOf: newVariableBytes)
        compiledLoop.append(0x00)
        compiledLoop.append(0x01)
        compiledLoop.append(contentsOf: oldVariablePath)
        compiledLoop.append(contentsOf: subTemplateCode.compiled)
        compiledLoop.append(0x00)
        
        return compiledLoop
    }
}
