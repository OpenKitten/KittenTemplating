import XCTest
@testable import KittenTemplating
import BSON

#if Xcode
    private var workDir: String {
        let parent = #file.characters.split(separator: "/").map(String.init).dropLast().joined(separator: "/")
        let path = "/\(parent)/../../Resources/"
        return path
    }
#else
    private let workDir = "./Resources/"
#endif

class KittenTemplatingTests: XCTestCase {
    func testLoop() throws {
        let template = try LeafSyntax.compile("simple.leaf", atPath: workDir)
        
        let output = try template.run(inContext: [
            "list": [
                ["hoi": "kaas0"] as Document,
                ["hoi": "kaas1"] as Document,
                ["hoi": "kaas2"] as Document,
                ["hoi": "kaas3"] as Document,
                ["hoi": "kaas4"] as Document,
            ] as Document
        ])
        
        guard let string = String(bytes: output, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        print(string)
        
        XCTAssert(string.contains("kaas0"))
        XCTAssert(string.contains("kaas1"))
        XCTAssert(string.contains("kaas2"))
        XCTAssert(string.contains("kaas3"))
        XCTAssert(string.contains("kaas4"))
        XCTAssertFalse(string.contains("kaas5"))
    }

    func testExample() throws {
        let template = try LeafSyntax.compile("embed.leaf", atPath: workDir)
        
        let output = try template.run()
        
        guard let string = String(bytes: output, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssert(string.contains("<html>"))
        XCTAssert(string.contains("</html>"))
        XCTAssert(string.contains("<body></body>"))
    }
    
    func testExample2() throws {
        let template = try LeafSyntax.compile("html.leaf", atPath: workDir)
        
        let output = try template.run()
        
        guard let string = String(bytes: output, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssert(string.contains("<!DOCTYPE html>"))
        XCTAssert(string.contains("<html>"))
        XCTAssert(string.contains("</html>"))
        XCTAssert(string.contains("<body></body>"))
    }

    static var allTests : [(String, (KittenTemplatingTests) -> () throws -> Void)] {
        return [
            ("testLoop", testLoop),
        ]
    }
}
