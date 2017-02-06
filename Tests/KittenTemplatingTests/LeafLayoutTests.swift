import Foundation
import XCTest
import BSON
@testable import KittenTemplating

class LayoutTests: XCTestCase {
    static let allTests = [
        ("testBasicLayout", testBasicLayout),
        ("testBasicLayoutFallback", testBasicLayoutFallback),
        ("testSimpleEmbed", testSimpleEmbed),
        ("testLayoutEmbedMix", testLayoutEmbedMix),
        ]
    
    func testBasicLayout() throws {
        let template = try LeafSyntax.compile("basic-extension.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "World"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Hello, World!")
    }
    
    func testBasicLayoutFallback() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("#extend(\"basic-extendable\")".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "World"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Hello, World!")
    }
    
    func testSimpleEmbed() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("I'm a header! #embed(\"template-basic-raw\")".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: [:])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "I'm a header! Hello, World!")
    }
    
    func testLayoutEmbedMix() throws {
        var extend = "#extend(\"base\")\n"
        extend += "#export(\"header\") { I'm a header! #embed(\"template-basic-raw\") }"
        
        let template = try LeafSyntax.compile(fromData: [UInt8](extend.utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: [:])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, " I'm a header! Hello, World! \n")
    }
}
