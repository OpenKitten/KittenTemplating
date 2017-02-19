import Foundation
import XCTest
import BSON
@testable import KittenTemplating

class IfTests: XCTestCase {
    static let allTests = [
        ("testBasicIf", testBasicIf),
        ("testBasicIfFail", testBasicIfFail),
        ("testBasicIfElse", testBasicIfElse),
        ("testNestedIfElse", testNestedIfElse),
//        ("testIfThrow", testIfThrow),
//        ("testIfEmptyString", testIfEmptyString),
        ]
    
    func testBasicIf() throws {
        let template = try LeafSyntax.compile("basic-if-test.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["say-hello": true])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " Hello, there! ")
    }
    
    func testBasicIfFail() throws {
        let template = try LeafSyntax.compile("basic-if-test.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["say-hello": false])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "")
    }
    
    func testBasicIfElse() throws {
        let template = try LeafSyntax.compile("basic-if-else.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["entering": true,
                                                         "friend-name": "World"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " Hello, World! \n")
        
        let renderedBytes2 = try template.run(inContext: ["entering": false,
                                                         "friend-name": "World"])
        
        guard let rendered2 = String(bytes: renderedBytes2, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered2, " Goodbye, World! \n")
    }
    
    func testNestedIfElse() throws {
        let template = try LeafSyntax.compile("nested-if-else.leaf", atPath: workDir + "Leaf/")
        let expectations: [(input: TemplateContext, expectation: String)] = [
            (input: ["a": true], expectation: "\n    Got a.\n\n"),
            (input: ["b": true], expectation: "\n    Got b.\n\n"),
            (input: ["c": true], expectation: "\n    Got c.\n\n"),
            (input: ["d": true], expectation: "\n    Got d.\n\n"),
            (input: [:], expectation: "\n    Got e.\n\n")
        ]
        
        try expectations.forEach { input, expectation in
            let renderedBytes = try template.run(inContext: input)
            
            guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
                XCTFail()
                return
            }
            
            XCTAssertEqual(rendered, expectation)
        }
    }
//    
//    func testIfThrow() throws {
//        let leaf = try stem.spawnLeaf(raw: "#if(too, many, arguments) { }")
//        let context = Context([:])
//        do {
//            _ = try stem.render(leaf, with: context)
//            XCTFail("should throw")
//        } catch If.Error.expectedSingleArgument {}
//    }
//    
//    func testIfEmptyString() throws {
//        let template = try stem.spawnLeaf(named: "if-empty-string-test")
//        do {
//            let context = try Node(node: ["name": "name"])
//            let loadable = Context(context)
//            let rendered = try stem.render(template, with: loadable).string
//            let expectation = "Hello, there!"
//            XCTAssert(rendered == expectation, "have: \(rendered), want: \(expectation)")
//        }
//        do {
//            let context = try Node(node: ["name": ""])
//            let loadable = Context(context)
//            let rendered = try stem.render(template, with: loadable).string
//            let expectation = ""
//            XCTAssert(rendered == expectation, "have: \(rendered), want: \(expectation)")
//        }
//    }
}
