import Foundation
import XCTest
import BSON
@testable import KittenTemplating

class RenderTests: XCTestCase {
    static let allTests = [
        ("testBasicRender", testBasicRender),
        ]
    
    func testBasicRender() throws {
        let template = try LeafSyntax.compile("basic-render.leaf", atPath: workDir + "Leaf/")
        
        for context in ["a", "ab9###", "ajcm301kc,s--11111", "World", "👾"] {
            let renderedBytes = try template.run(inContext: ["self": context])
            
            guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
                XCTFail()
                return
            }
            
            XCTAssertEqual(rendered, "Hello, \(context)!\n")
        }
    }
}
