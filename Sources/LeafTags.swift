import BSON

/// Simple typealias for simplicity
public typealias LeafCompileContext = LeafSyntax.CompileContext

/// A closure used to compile the tag into bytes given the context
///
/// The context can be used to store data from pre-compiling to compile-time.
public typealias LeafCompileClosure = ((LeafCompileContext) throws -> [UInt8])

/// A leaf tag
public protocol LeafTag {
    /// The tag as a name
    static var stringName: String { get }
    
    /// The tag as bytes, for the compiler to be fast
    static var name: [UInt8] { get }
    
    /// Used to parse the tag starting at the character after the function open bracket `(` in the `input` code
    ///
    /// The input code is the file being parsed
    ///
    /// The templating language is provided to allow you to compile parts of the code or other files using the same language
    ///
    /// The path is the current working directory in which the templates exist
    ///
    /// The context is provided to store data from pre-compiling (this function) to this and other closures that are returned to generate bitcode
    static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure
}

/// A basic leaf tag doesn't use compiler contexts most of the time and simply return bitcode
public protocol BasicLeafTag : LeafTag {
    static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8]
}

extension BasicLeafTag {
    /// Helper for BasicLeafTags
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        let bitcode = try Self.compile(atPosition: &position, inCode: input, byTemplatingLanguage: language, atPath: path, inContext: context)
        
        return { _ in
            return bitcode
        }
    }
}

extension LeafTag {
    /// A leaf tag's name as a string is usually directly the name for the bytes
    public static var name: [UInt8] {
        return [UInt8](Self.stringName.utf8)
    }
}

/// The possible leaf errors that can exist by default
public enum LeafError: Error {
    case nullTerminatorInTemplate
    case tagContainsWhitespace
    case invalidSecondArugmentInLoop
    case unknownTag([UInt8])
    case tagNotOpened
    case tagNotClosed
    case variablePathContainsWhitespace
    case missingRequiredCharacter(found: UInt8, need: UInt8)
    case invalidString
    case notExported(String)
}

/// Prints the variable inbetween the brackets
public struct LeafPrint : BasicLeafTag {
    public static var stringName: String = ""
    
    /// Compiles this tag to a print statement to print the variable as a string
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        let variableBytes = try input.scanUntil(SpecialCharacters.argumentsClose, fromPosition: &position)
        var variablePath = variableBytes.makeVariablePath(inContext: context)
        let oldPosition = position
        
        // Scan for raw data between function brackets
        if let subTemplate = try? input.parseSubTemplate(atPosition: &position) {
            var newScope = variablePath
            
            // Remove null terminators
            newScope.removeLast(2)
            
            var oldScope: [UInt8]? = nil
            
            if let currentScope = context.options["scope"] as? [UInt8] {
                oldScope = currentScope
            }
            
            context.options["scope"] = newScope
            defer {
                context.options["scope"] = oldScope
            }
            
            var subTemplateBitcode = try LeafSyntax.compile(fromData: subTemplate, atPath: path, inContext: context).compiled
            context.options["scope"] = nil
            
            subTemplateBitcode.removeLast()
            
            return subTemplateBitcode
        } else {
            position = oldPosition
            /// [statement, print, variable] + variable_path
            return [Element.statement, Statement.print, Expression.variable] + variablePath
        }
    }
}

/// Embeds an external file template
public struct LeafEmbed : BasicLeafTag {
    public static var stringName = "embed"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        let embedNameBytes = try input.scanStringLiteral(atPosition: &position)
        
        position += 1
        
        guard let embeddedFile = String(bytes: embedNameBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        var subTemplateCode = try language.compile(embeddedFile + ".leaf", atPath: path, inContext: context).compiled
        
        // Remove compiled template null terminator and embed the bitcode here
        subTemplateCode.removeLast()
        
        return subTemplateCode
    }
}

/// Exports a subtemplate under a name to import somewhere else
public struct LeafExport : BasicLeafTag {
    public static var stringName = "export"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        // Find the export name
        let exportNameBytes = try input.scanStringLiteral(atPosition: &position)
        
        // Require tag end
        try input.requireCharacter(SpecialCharacters.argumentsClose, atPosition: &position)
        
        // Convert the name to a string
        guard let exportName = String(bytes: exportNameBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        // Create a subtemplate
        let template = try input.parseSubTemplate(atPosition: &position)
        
        // Add it the the exported templates list
        var exported = context.options["exports"] as? [String: [UInt8]] ?? [:]
        
        exported[exportName] = template
        
        context.options["exports"] = exported
        
        return []
    }
}

/// Imports/embeds an exported subtemplate
public struct LeafImport : LeafTag {
    public static var stringName = "import"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // Find the import name
        let importNameBytes = try input.scanStringLiteral(atPosition: &position)
        
        // Require tag end
        try input.requireCharacter(SpecialCharacters.argumentsClose, atPosition: &position)
        
        // Convert the name to a string
        guard let importName = String(bytes: importNameBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        return { context in
            // Find the referenced subtemplate
            guard let exports = context.options["exports"] as? [String: [UInt8]], let uncompiledTemplate = exports[importName] else {
                throw LeafError.notExported(importName)
            }
            
            // Compile it
            var subTemplateCode = try language.compile(fromData: uncompiledTemplate, atPath: path, inContext: context).compiled
            
            // Remove trailing null terminator
            subTemplateCode.removeLast()
            
            // Embed it
            return subTemplateCode
        }
    }
}

public struct LeafExtend : LeafTag {
    public static var stringName = "extend"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // Find the export name
        let extensionNameBytes = try input.scanStringLiteral(atPosition: &position)
        
        // Require tag end
        try input.requireCharacter(SpecialCharacters.argumentsClose, atPosition: &position)
        
        // Convert the name to a string
        guard let extensionName = String(bytes: extensionNameBytes, encoding: .utf8) else {
            throw LeafError.invalidString
        }
        
        return { context in
            // Embed the extension template here and give it access to the context of this template
            var subTemplateCode = try language.compile(extensionName + ".leaf", atPath: path, inContext: context).compiled
            
            subTemplateCode.removeLast()
            
            return subTemplateCode
        }
    }
}

public struct LeafIndex: LeafTag {
    
}

public struct LeafElse : LeafTag {
    public static var stringName = "else"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        try input.requireCharacter(SpecialCharacters.argumentsClose, atPosition: &position)
        
        input.skipWhitespace(fromPosition: &position)
        
        // Scan for the subtemplate
        let subTemplate = try input.parseSubTemplate(atPosition: &position)
        
        return { context in
            // Compile the template when `true`
            var compiledTemplate = try language.compile(fromData: subTemplate, atPath: path, inContext: context).compiled
            
            compiledTemplate.removeLast()
            return compiledTemplate
        }
    }
}

/// An if statement, also parses else-ifs and else
public struct LeafIf : LeafTag {
    public static var stringName = "if"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> LeafCompileClosure {
        // Scan for the variable
        var variableBytes = try input.scanUntil(SpecialCharacters.argumentsClose, fromPosition: &position)
        
        variableBytes = variableBytes.makeVariablePath(inContext: context)
        
        // Scan for the subtemplate
        let subTemplate = try input.parseSubTemplate(atPosition: &position)
        
        let elseClosure: LeafCompileClosure?
        
        input.skipWhitespace(fromPosition: &position)
        
        if position + 2 < input.count && input[position] == SpecialCharacters.pound && input[position + 1] == SpecialCharacters.pound {
            position += 2
            
            let tagName = try input.scanUntil(SpecialCharacters.argumentsOpen, fromPosition: &position)
            
            for character in tagName {
                guard !SpecialCharacters.whitespace.contains(character) else {
                    throw LeafError.tagContainsWhitespace
                }
            }
            
            if tagName == LeafElse.name {
                elseClosure = try LeafElse.compile(atPosition: &position, inCode: input, byTemplatingLanguage: language, atPath: path, inContext: context)
            } else {
                // Find the matching tag if possible
                guard let tag = LeafSyntax.tags.first(where: { $0.name == tagName }) else {
                    throw LeafError.unknownTag(tagName)
                }
                
                // Compile the tag to a closure and add it to the compiler tasks
                elseClosure = try tag.compile(atPosition: &position, inCode: input, byTemplatingLanguage: LeafSyntax.self, atPath: path, inContext: context)
            }
        } else {
            elseClosure = nil
        }
        
        return { context in
            // Compile the template when `true`
            let trueTemplate = try language.compile(fromData: subTemplate, atPath: path, inContext: context).compiled
            
            // TODO: False template
            let elseTemplate = try elseClosure?(context) ?? []
            
            // Convert the true-template-length to an UInt32 as bytes
            let trueLength = UInt32(trueTemplate.count).makeBytes()
            
            // Convert the false-template-length to an UInt32 as bytes
            // TODO: Unsupported
            let falseLength = UInt32(elseTemplate.count).makeBytes()
            
            // Construct the bitcode
            // [statement, if, boolean_variable] + skip_length_true + skip_length_false + true_template + false_template
            return [Element.statement, Statement.if, Expression.variable] + variableBytes + trueLength + falseLength + trueTemplate + elseTemplate
        }
    }
}

/// Displays raw data, ignoring special characters
public struct LeafRaw : BasicLeafTag {
    public static var stringName = "raw"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        // Scan for a variable
        let variableBytes = try input.scanUntil(SpecialCharacters.argumentsClose, fromPosition: &position)
        
        if variableBytes.count == 0 {
            // Scan for raw data between function brackets
            let subTemplate = try input.parseSubTemplate(atPosition: &position, countingBrackets: false)
            
            return [Element.rawData] + UInt32(subTemplate.count).makeBytes() + subTemplate
        } else {
            let variablePath = variableBytes.makeVariablePath(inContext: context)
            
            return [Element.statement, Statement.print, Expression.variable] + variablePath
        }
    }
}

/// A for..in loop
public struct LeafLoop : BasicLeafTag {
    public static var stringName = "loop"
    
    public static func compile(atPosition position: inout Int, inCode input: [UInt8], byTemplatingLanguage language: TemplatingSyntax.Type, atPath path: String, inContext context: LeafCompileContext) throws -> [UInt8] {
        // Scan for the variable
        let oldVariableBytes = try input.scanUntil([SpecialCharacters.space, SpecialCharacters.comma], fromPosition: &position)
        
        // Skip whitespace
        input.skip(fromPosition: &position, characters: SpecialCharacters.space, SpecialCharacters.comma, SpecialCharacters.endLine)
        
        // Find the new variable name
        let newVariableBytes = try input.scanStringLiteral(atPosition: &position)
        
        // Require tag end
        try input.requireCharacter(SpecialCharacters.argumentsClose, atPosition: &position)
        
        // Compile the sub template
        let subTemplateCode = try LeafSyntax.compileSubTemplate(atPosition: &position, inCode: input, atPath: path)
        
        // Define the loop length for the runtime
        let loopLength = UInt32(subTemplateCode.compiled.count).makeBytes()
        
        // Construct the old variable to a null-separated-path
        let oldVariablePath = oldVariableBytes.makeVariablePath(inContext: context)
        
        
        var compiledLoop: [UInt8] = [Element.statement, Statement.for]
        
        // Null terminated the cString
        compiledLoop.append(contentsOf: newVariableBytes)
        compiledLoop.append(0x00)
        
        // Old variable
        compiledLoop.append(Expression.variable)
        compiledLoop.append(contentsOf: oldVariablePath)
        
        // The subtemplate
        compiledLoop.append(contentsOf: loopLength)
        compiledLoop.append(contentsOf: subTemplateCode.compiled)
        
        // End of loop
        compiledLoop.append(0x00)
        
        return compiledLoop
    }
}
