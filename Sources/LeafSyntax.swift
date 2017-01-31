//
//  LanguageMustache.swift
//  MeowVapor
//
//  Created by Joannis Orlandos on 20/01/2017.
//
//

import Foundation

public enum LeafSyntax: TemplatingSyntax {
    public static var tags: [LeafTag.Type] = [
        LeafPrint.self,
        LeafLoop.self,
        LeafEmbed.self,
        LeafImport.self,
        LeafExport.self,
        LeafExtend.self,
        LeafIf.self,
        ]
    
    public class CompileContext {
        var options = [String: Any]()
        
        fileprivate init() {}
    }
    
    public static func compile(fromData input: [UInt8], atPath path: String, inContext context: Any? = nil) throws -> Template {
        return Template(compiled: try LeafSyntax.compile(fromData: input, atPath: path, inContext: context))
    }
    
    private static func compile(fromData input: [UInt8], atPath path: String, inContext context: Any? = nil) throws -> [UInt8] {
        let context = (context as? CompileContext) ?? CompileContext()
        var position = 0
        var rawBuffer = [UInt8]()
        var compilerClosures = [LeafCompileClosure]()
        var compiledTemplate = [UInt8]()
        
        func parseTag() throws -> LeafCompileClosure {
            var tagName = [UInt8]()
            
            tagNameLoop: while position < input.count {
                defer { position += 1 }
                
                // " "
                guard input[position] != 0x20 else {
                    throw LeafError.tagContainsWhitespace
                }
                
                // "("
                if input[position] == 0x28 {
                    break tagNameLoop
                }
                
                tagName.append(input[position])
            }
            
            guard let tag = tags.first(where: { $0.name == tagName }) else {
                throw LeafError.unknownTag(tagName)
            }
            
            return try tag.compile(atPosition: &position, inCode: input, byTemplatingLanguage: LeafSyntax.self, atPath: path, inContext: context)
        }
        
        while position < input.count {
            // "#"
            if input[position] == 0x23 {
                if rawBuffer.count > 0 {
                    let rawClosureBuffer = rawBuffer
                    
                    compilerClosures.append { _ in
                        return [0x01] + rawClosureBuffer + [0x00]
                    }
                    
                    rawBuffer = []
                }
                
                position += 1
                
                compilerClosures.append(try parseTag())
                // Null terminator
            } else if input[position] != 0x00 {
                rawBuffer.append(input[position])
                position += 1
            } else {
                throw LeafError.nullTerminatorInTemplate
            }
        }
        
        for closure in compilerClosures {
            compiledTemplate.append(contentsOf: try closure(context))
        }
        
        if rawBuffer.count > 0 {
            compiledTemplate.append(0x01)
            compiledTemplate.append(contentsOf: rawBuffer)
            compiledTemplate.append(0x00)
            rawBuffer = []
        }
        
        compiledTemplate.append(0x00)
        
        return compiledTemplate
    }
    
    internal static func compileSubTemplate(atPosition position: inout Int, inCode input: [UInt8], atPath path: String) throws -> Template {
        let subTemplate = try input.parseSubTemplate(atPosition: &position)
        
        return try self.compile(fromData: subTemplate, atPath: path)
    }
}
