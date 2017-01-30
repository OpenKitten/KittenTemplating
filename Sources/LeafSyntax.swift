//
//  LanguageMustache.swift
//  MeowVapor
//
//  Created by Joannis Orlandos on 20/01/2017.
//
//

import Foundation

public enum LeafSyntax: TemplatingSyntax {
    public static var tags: [Tag.Type] = [
        LeafPrint.self,
        LeafLoop.self,
        LeafEmbed.self,
    ]
    
    public static func compile(fromData input: [UInt8], atPath path: String) throws -> Template {
        return Template(compiled: try LeafSyntax.compile(fromData: input, atPath: path))
    }
    
    private static func compile(fromData input: [UInt8], atPath path: String) throws -> [UInt8] {
        var position = 0
        var rawBuffer = [UInt8]()
        var compiledTemplate = [UInt8]()
        
        func parseTag() throws -> [UInt8] {
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
            
            return try tag.compile(atPosition: &position, inCode: input, byTemplatingLanguage: LeafSyntax.self, atPath: path)
        }
        
        while position < input.count {
            // "#"
            if input[position] == 0x23 {
                if rawBuffer.count > 0 {
                    compiledTemplate.append(0x01)
                    compiledTemplate.append(contentsOf: rawBuffer)
                    compiledTemplate.append(0x00)
                    rawBuffer = []
                }
                
                position += 1
                
                compiledTemplate.append(contentsOf: try parseTag())
            // Null terminator
            } else if input[position] != 0x00 {
                rawBuffer.append(input[position])
                position += 1
            } else {
                throw LeafError.nullTerminatorInTemplate
            }
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
    
    internal static func parseSubTemplate(atPosition position: inout Int, inCode input: [UInt8], atPath path: String) throws -> Template {
        var check = false
        var subTemplate = [UInt8]()
        
        startTagLoop: while position < input.count {
            defer { position += 1 }
            
            // "{"
            if input[position] == 0x7b {
                check = true
                break startTagLoop
            }
        }
        
        guard check else {
            throw LeafError.tagNotOpened
        }
        
        check = false
        
        endTagLoop: while position < input.count {
            defer { position += 1 }
            
            // "}"
            if input[position] == 0x7d {
                check = true
                break endTagLoop
            }
            
            subTemplate.append(input[position])
        }
        
        guard check else {
            throw LeafError.tagNotClosed
        }
        
        return try self.compile(fromData: subTemplate, atPath: path)
    }
}
