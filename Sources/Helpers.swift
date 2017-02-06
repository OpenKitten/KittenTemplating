import BSON

public enum TemplateError: Error {
    case invalidElement(UInt8)
    case invalidStatement(UInt8)
    case invalidExpression(UInt8)
    case unableToInstantiateString(fromBytes: [UInt8])
    case emptyVariablePath
    case variableNotADocument(atKey: String)
    case loopingOverNil
    case unclosedLoop
    case loopingOverNonArrayType
    case fileDoesNotExist(atPath: String)
    case unexpectedEndOfTemplate
    case expectedBoolean(found: ValueConvertible?)
}

internal struct Element {
    static let rawData: UInt8 = 0x01
    static let statement: UInt8 = 0x02
}

internal struct Statement {
    static let `if`: UInt8 = 0x01
    static let `for`: UInt8 = 0x02
    static let `print`: UInt8 = 0x03
}

internal struct Expression {
    static let variable: UInt8 = 0x01
}

struct SpecialCharacters {
    static let dot: UInt8 = 0x2e
    static let comma: UInt8 = 0x2c
    static let codeBracketOpen: UInt8 = 0x7b
    static let codeBracketClose: UInt8 = 0x7d
    static let argumentsOpen: UInt8 = 0x28
    static let argumentsClose: UInt8 = 0x29
    static let space: UInt8 = 0x20
    static let quotationMark: UInt8 = 0x22
    static let endLine: UInt8 = 0x0a
    static let pound: UInt8 = 0x23
    
    static let whitespace: [UInt8] = [SpecialCharacters.space, SpecialCharacters.endLine]
}

extension Swift.Collection where Self.Iterator.Element == UInt8, Self.Index == Int, Self.IndexDistance == Int {
    internal func makeUInt32() -> UInt32 {
        var val: UInt32 = 0
        val |= self.count > 3 ? UInt32(self[startIndex.advanced(by: 3)]) << 24 : 0
        val |= self.count > 2 ? UInt32(self[startIndex.advanced(by: 2)]) << 16 : 0
        val |= self.count > 1 ? UInt32(self[startIndex.advanced(by: 1)]) << 8 : 0
        val |= self.count > 0 ? UInt32(self[startIndex]) : 0
        
        return val
    }
    
    func require(_ required: Int, afterPosition position: Int) throws {
        guard position + required < self.count else {
            throw TemplateError.unexpectedEndOfTemplate
        }
    }
    
    func scanUntil(_ character: UInt8, fromPosition position: inout Int) throws -> [UInt8] {
        var scannedBytes = [UInt8]()
        
        // Advance through the file until a new quotationmark ends the string
        stringLoop: while position < self.count {
            defer { position += 1 }
            
            // If we found the character, break
            if self[position] == character {
                break stringLoop
            }
            
            // Otherwise, append it
            scannedBytes.append(self[position])
        }
        
        return scannedBytes
    }
    
    func scanUntil(_ characters: [UInt8], fromPosition position: inout Int) throws -> [UInt8] {
        var scannedBytes = [UInt8]()
        
        // Advance through the file until a new quotationmark ends the string
        stringLoop: while position < self.count {
            defer { position += 1 }
            
            // If we found the character, break
            if characters.contains(self[position]) {
                break stringLoop
            }
            
            // Otherwise, append it
            scannedBytes.append(self[position])
        }
        
        return scannedBytes
    }
    
    func skip(fromPosition position: inout Int, characters: [UInt8]) {
        while position < self.count {
            guard characters.contains(self[position]) else {
                return
            }
            
            position += 1
        }
    }
    
    func skip(fromPosition position: inout Int, characters: UInt8...) {
        self.skip(fromPosition: &position, characters: characters)
    }
    
    func skipWhitespace(fromPosition position: inout Int) {
        skip(fromPosition: &position, characters: SpecialCharacters.whitespace)
    }
    
    func scanStringLiteral(atPosition position: inout Int) throws -> [UInt8] {
        try requireCharacter(SpecialCharacters.quotationMark, atPosition: &position)
        
        return try scanUntil(SpecialCharacters.quotationMark, fromPosition: &position)
    }
    
    func requireCharacter(_ character: UInt8, atPosition position: inout Int) throws {
        try self.require(1, afterPosition: position)
        
        defer { position += 1 }
        
        guard self[position] == character else {
            throw LeafError.missingRequiredCharacter(found: self[position], need: character)
        }
    }
    
    func parseSubTemplate(atPosition position: inout Int, countingBrackets: Bool = true) throws -> [UInt8] {
        var check = false
        var subTemplate = [UInt8]()
        
        skipWhitespace(fromPosition: &position)
        
        try self.requireCharacter(SpecialCharacters.codeBracketOpen, atPosition: &position)
        
        var tagOpenCounter = 0
        
        // Prevent closing too early
        endTagLoop: while position < self.count {
            defer { position += 1 }
            
            if self[position] == SpecialCharacters.codeBracketOpen && countingBrackets {
                tagOpenCounter += 1
            }
            
            if self[position] == SpecialCharacters.codeBracketClose {
                if tagOpenCounter == 0 {
                    check = true
                    break endTagLoop
                } else {
                    tagOpenCounter -= 1
                }
            }
            
            subTemplate.append(self[position])
        }
        
        guard check else {
            throw LeafError.tagNotClosed
        }
        
        return subTemplate
    }
    
    func makeVariablePath() -> [UInt8] {
        var variableBytes = self.map { byte -> UInt8 in
            // Instead of separating by dot, the templating bitcode requires `0x00`
            if byte == SpecialCharacters.dot {
                return 0x00
            } else {
                return byte
            }
        }
        
        // End of last variable path part
        variableBytes.append(0x00)
        // End of path
        variableBytes.append(0x00)
        
        return variableBytes
    }
}

extension UInt32 {
    internal func makeBytes() -> [UInt8] {
        let integer = self.littleEndian
        
        return [
            UInt8(integer & 0xFF),
            UInt8((integer >> 8) & 0xFF),
            UInt8((integer >> 16) & 0xFF),
            UInt8((integer >> 24) & 0xFF),
        ]
    }
}
