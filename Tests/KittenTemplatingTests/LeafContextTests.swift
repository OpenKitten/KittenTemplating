import Foundation
import XCTest
import BSON
@testable import KittenTemplating

class ContextTests: XCTestCase {
    static let allTests = [
        ("testBasic", testBasic),
        ("testNested", testNested),
        ("testLoop", testLoop),
        ("testNamedInner", testNamedInner),
        ("testDualContext", testDualContext),
        ("testMultiContext", testMultiContext),
        ("testIfChain", testIfChain),
        ("testNestedComplex", testNestedComplex),
        ]
    
    func testBasic() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("Hello, #(name)!".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "World"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Hello, World!")
    }
    
    func testNested() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#(best-friend) { Hello, #(self.name)! }".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["best-friend": ["name": "World"] as TemplateContext])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " Hello, World! ")
    }
    
    func testLoop() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#loop(friends, \"friend\") { Hello, #(friend)! }".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["friends": ["a", "b", "c", "#loop"] as TemplateContext])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " Hello, a!  Hello, b!  Hello, c!  Hello, #loop! ")
    }
    
    func testNamedInner() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#(name) { #(name) }".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "foo"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " foo ")
    }
    
    func testDualContext() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("Let's render #(friend) { #(name) is friends with #(friend.name) } ".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "Foo", "friend": ["name": "Bar"] as TemplateContext])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Let's render  Foo is friends with Bar  ")
    }
    
    func testMultiContext() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#(a) { #(self.b) { #(self.c) { #(self.path.1) } } }".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["a": ["b": ["c": ["path": ["array-variant", "HEllo"] as TemplateContext] as TemplateContext] as TemplateContext] as TemplateContext])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "   HEllo   ")
    }
    
    func testIfChain() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#if(key-zero) { Hi, A! } ##if(key-one) { Hi, B! } ##else() { Hi, C! }".utf8), atPath: workDir + "Leaf/")
        
        let cases: [(key: String, bool: Bool, expectation: String)] = [
            ("key-zero", true, " Hi, A! "),
            ("key-zero", false, " Hi, C! "),
            ("key-one", true, " Hi, B! "),
            ("key-one", false, " Hi, C! "),
            ("s••z", true, " Hi, C! "),
            ("$º–%,🍓", true, " Hi, C! "),
            ("]", true, " Hi, C! "),
            ]
        
        for (key, bool, expectation) in cases {
            let renderedBytes = try template.run(inContext: [key: bool])
            
            guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
                XCTFail()
                return
            }
            
            XCTAssertEqual(rendered, expectation)
        }
    }
    
    func testNestedComplex() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("Hello, #(path.to.person.0.name)!".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: [
            "path": [
                "to": [
                    "person": [
                        ["name": "World"] as TemplateContext
                    ] as TemplateContext
                ] as TemplateContext
            ] as TemplateContext
            ])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Hello, World!")
    }
}
