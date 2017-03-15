//
//  Context.swift
//  KittenTemplating
//
//  Created by Joannis Orlandos on 15/03/2017.
//
//

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
        var path = path
        
        if path.characters.last != "/" {
            path += "/"
        }
        
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
    
    var storage = [SupportedValue]()
    
    public init<S>(sequence: S) where S : Sequence, S.Iterator.Element == SupportedValue {
        storage = Array(sequence)
    }
    
    public init(arrayLiteral elements: ContextValue...) {
        storage = elements
    }
    
    public func makeIterator() -> IndexingIterator<[ContextValue]> {
        return storage.makeIterator()
    }
}

public struct TemplateContext : ContextValue, InitializableObject, ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (KittenBytes, ContextValue)...) {
        self.storage = elements.map { ($0.0.kittenBytes, $0.1) }
    }
    
    public init<S>(sequence: S) where S : Sequence, S.Iterator.Element == SupportedValue {
        self.storage = sequence.map { ($0.0, $0.1) }
    }
    
    public typealias ObjectKey = KittenBytes
    public typealias ObjectValue = ContextValue
    public typealias SupportedValue = (KittenBytes, ContextValue)
    
    var storage = [(KittenBytes, ContextValue)]()
    
    public var dictionaryRepresentation: [KittenBytes: ContextValue] {
        var dict = [KittenBytes: ContextValue]()
        
        for (key, value) in storage {
            dict[key] = value
        }
        
        return dict
    }
    
    func getValue(forKey key: KittenBytes) -> ContextValue? {
        return self.storage.first(where: { $0.0.bytes == key.bytes })?.1
    }
    
    func getValue(forKey key: String) -> ContextValue? {
        return self.storage.first(where: { $0.0 == key.kittenBytes })?.1
    }
    
    mutating func setValue(to newValue: ContextValue?, forKey key: KittenBytes) {
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
    
    mutating func setValue(to newValue: ContextValue?, forKey key: String) {
        let position = storage.index(where: {
            $0.0 == key.kittenBytes
        })
        
        if let newValue = newValue {
            if let position = position {
                storage[position] = (key.kittenBytes, newValue)
            } else {
                storage.append((key.kittenBytes, newValue))
            }
        } else if let position = position {
            storage.remove(at: position)
        }
    }
    
    public func makeIterator() -> AnyIterator<(KittenBytes, ContextValue)> {
        var storageIterator = storage.makeIterator()
        
        return AnyIterator {
            return storageIterator.next()
        }
    }
}

extension Dictionary : ContextValue {
    public func makeTemplateContext() -> TemplateContext {
        guard let dict = self as? [String : ContextValue] else {
            // `assertionFailure` only triggers a crash on debug configurations, not on release.
            let error = "Only [String : BSON.Primitive] dictionaries are BSON.Primitive. Tried to initialize a document using [\(Key.self) : \(Value.self)]. This will crash on debug and print this message on release configurations."
            assertionFailure(error)
            print(error)
            return [:]
        }
        
        return dict.convert(toObject: TemplateData.self)
    }
}

extension Array : ContextValue {
    public func makeTemplateSequence() -> TemplateSequence {
        guard let `self` = self as? [ContextValue] else {
            // `assertionFailure` only triggers a crash on debug configurations, not on release.
            let error = "Only [BSON.Primitive] arrays are BSON.Primitive. Tried to initialize a document using [\(Element.self)]. This will crash on debug and print this message on release configurations."
            assertionFailure(error)
            print(error)
            return ([] as TemplateSequence)
        }
        
        return TemplateSequence(sequence: self)
    }
}


extension String: ContextValue {}
extension Double: ContextValue {}
extension StaticString: ContextValue {}
extension KittenBytes: ContextValue {}
extension Int: ContextValue {}
extension Bool: ContextValue {}
