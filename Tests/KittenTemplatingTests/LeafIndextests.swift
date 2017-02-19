//import Foundation
//import XCTest
//import BSON
//@testable import KittenTemplating
//
//class IndexTests: XCTestCase {
//    static let allTests = [
//        ("testBasicIndex", testBasicIndex),
//        ("testOutOfBounds", testOutOfBounds)
//    ]
//    
//    func testBasicIndex() throws {
//        let template = try LeafSyntax.compile(fromData: [UInt8]("Hello, #index(friends, idx) { #(self)! }".utf8), atPath: workDir + "Leaf/")
//        let renderedBytes = try template.run(inContext: ["friends": ["Joe", "Jan", "Jay", "Jen"] as TemplateContext, "idx": 3])
//        
//        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
//            XCTFail()
//            return
//        }
//        
//        XCTAssertEqual(rendered, " Hello, ! ")
//    }
//    
//    func testOutOfBounds() throws {
//        let template = try LeafSyntax.compile(fromData: [UInt8]("Hello, #index(friends, idx)!".utf8), atPath: workDir + "Leaf/")
//        let renderedBytes = try template.run(inContext: ["friends": [] as TemplateContext, "idx": 3])
//        
//        guard let rendered = String(bytes: renderedBytes, encoding: .utf8) else {
//            XCTFail()
//            return
//        }
//        
//        XCTAssertEqual(rendered, " Hello, ! ")
//    }
//}
