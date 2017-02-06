import Foundation
import XCTest
@testable import KittenTemplating

class RawTests: XCTestCase {
    static let allTests = [
        ("testRaw", testRaw),
        ]
    
    func testRaw() throws {
        let template = try LeafSyntax.compile("raw.leaf", atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: [:])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        let expectation = " Everything stays ##@$& \n"
        XCTAssertEqual(rendered, expectation)
    }
    
    func testRawVariable() throws {
        let template = try LeafSyntax.compile(fromData: [UInt8]("Hello, #raw(unescaped)!".utf8), atPath: workDir + "Leaf/")
        let renderedBytes = try template.run(inContext: ["unescaped": "<b>World</b>"])
        
        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        let expectation = "Hello, <b>World</b>!"
        XCTAssertEqual(rendered, expectation)
    }
}
