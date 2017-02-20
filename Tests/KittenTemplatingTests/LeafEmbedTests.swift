import Foundation
import XCTest
@testable import KittenTemplating

class EmbedTests: XCTestCase {
    static let allTests = [
        ("testBasicEmbed", testBasicEmbed),
        ("testEmbedThrow", testEmbedThrow),
        ]
    
    func testBasicEmbed() throws {
        let template = try LeafSyntax.compile("embed-base.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["name": "World"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(rendered, "Leaf embedded: Hello, World!\n\n")
    }
    
    func testEmbedThrow() throws {
        do {
            let template = try LeafSyntax.compile(fromData: [UInt8]("#embed(invalid-variable)".utf8), atPath: workDir + "Leaf/")
            _
                = try template.run(inContext: [:])
            
            XCTFail("Expected throw")
        } catch { }
    }
}
