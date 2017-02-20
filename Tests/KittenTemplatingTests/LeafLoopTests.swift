import Foundation
import XCTest
@testable import KittenTemplating

#if Xcode
    internal var workDir: String {
        let parent = #file.characters.split(separator: "/").map(String.init).dropLast().joined(separator: "/")
        let path = "/\(parent)/../../Resources/"
        return path
    }
#else
    internal let workDir = "./Resources/"
#endif

class LeafLoopTests: XCTestCase {
    static let allTests = [
        ("testBasicLoop", testBasicLoop),
//        ("testComplexLoop", testComplexLoop),
//        ("testNumberThrow", testNumberThrow),
//        ("testInvalidSignature1", testInvalidSignature1),
//        ("testInvalidSignature2", testInvalidSignature2),
//        ("testSkipNil", testSkipNil),
//        ("testFuzzySingle", testFuzzySingle),
        ]
    
    func testBasicLoop() throws {
        let template = try LeafSyntax.compile("basic-loop.leaf", atPath: workDir + "Leaf/")
        let expectation = " Hello, asdf  Hello, 🐌  Hello, 8###z0-1  Hello, 12 \n"
        let renderedBytes = try template.run(inContext: [
            "friends": [
                "asdf",
                "🐌",
                "8###z0-1",
                12
            ] as TemplateContext
            ])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, expectation)
    }
    
    func testComplexLoop() throws {
        let template = try LeafSyntax.compile("complex-loop.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: [
            "friends": [
                [
                    "name": "Venus",
                    "age": 12345
                ] as TemplateContext,
                [
                    "name": "Pluto",
                    "age": 888
                ] as TemplateContext,
                [
                    "name": "Mercury",
                    "age": 9000
                ] as TemplateContext
            ] as TemplateContext
            ])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        let expectation = "\n<li><b>Venus</b>: 12345</li>\n\n<li><b>Pluto</b>: 888</li>\n\n<li><b>Mercury</b>: 9000</li>\n\n"
        XCTAssertEqual(rendered, expectation)
    }

    func testNumberThrow() throws {
        do {
            _ = try LeafSyntax.compile(fromData: [UInt8]("#loop(too, many, arguments)".utf8), atPath: workDir)
            XCTFail("Should throw")
        } catch { return }
    }

    func testInvalidSignature1() throws {
        do {
            _ = try LeafSyntax.compile(fromData: [UInt8]("#loop(\"invalid\", \"signature\")".utf8), atPath: workDir)
            XCTFail("Should throw")
        } catch { return }
    }

    func testInvalidSignature2() throws {
        do {
            _ = try LeafSyntax.compile(fromData: [UInt8]("#loop(invalid, signature)".utf8), atPath: workDir)
            XCTFail("Should throw")
        } catch { return }
    }
    
    func testSkipNil() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#loop(find-nil, \"inner-name\") { asdfasdfasdfsdf }".utf8), atPath: workDir)
        
        let renderedBytes = try template.run(inContext: [:])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "")
    }
    
    func testFuzzySingle() throws {
        // single => array
        let template = try LeafSyntax.compile(fromData: [UInt8]("#loop(names, \"name\") { Hello, #(name)! }".utf8), atPath: workDir)
        
        let renderedBytes = try template.run(inContext: ["names": "Rick"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " Hello, Rick! ")
    }
}
