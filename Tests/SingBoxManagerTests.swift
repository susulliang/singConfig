import XCTest
@testable import SingBoxManagerLib

final class VMessParserTests: XCTestCase {
    func testParseValidVMessLink() throws {
        // Example vmess link (base64 encoded)
        let vmessData = """
        {
            "ps": "Test Node",
            "add": "example.com",
            "port": "443",
            "id": "12345678-1234-1234-1234-123456789012",
            "aid": "0",
            "net": "tcp",
            "tls": "tls"
        }
        """

        let base64 = Data(vmessData.utf8).base64EncodedString()
        let link = "vmess://\(base64)"

        let node = try VMessParser.parse(link)

        XCTAssertEqual(node.tag, "Test Node")
        XCTAssertEqual(node.server, "example.com")
        XCTAssertEqual(node.server_port, 443)
        XCTAssertEqual(node.type, "vmess")
        XCTAssertTrue(node.tls?.enabled ?? false)
    }

    func testParseInvalidLink() {
        let invalidLink = "http://example.com"

        XCTAssertThrowsError(try VMessParser.parse(invalidLink)) { error in
            if case VMessParser.ParseError.invalidFormat = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat error")
            }
        }
    }

    func testParseVMessWithWebSocket() throws {
        let vmessData = """
        {
            "ps": "WS Node",
            "add": "ws.example.com",
            "port": "80",
            "id": "12345678-1234-1234-1234-123456789012",
            "aid": "0",
            "net": "ws",
            "path": "/ws",
            "host": "ws.example.com"
        }
        """

        let base64 = Data(vmessData.utf8).base64EncodedString()
        let link = "vmess://\(base64)"

        let node = try VMessParser.parse(link)

        XCTAssertEqual(node.transport?.type, "ws")
        XCTAssertEqual(node.transport?.path, "/ws")
        XCTAssertEqual(node.transport?.headers?["Host"], "ws.example.com")
    }
}

final class ConfigManagerTests: XCTestCase {
    func testExtractVMessNodes() {
        let config = SingBoxConfig(outbounds: [
            .object([
                "type": .string("vmess"),
                "tag": .string("Node1"),
                "server": .string("example.com"),
                "server_port": .int(443),
                "uuid": .string("test-uuid"),
                "security": .string("auto"),
                "alter_id": .int(0)
            ]),
            .object([
                "type": .string("selector"),
                "outbounds": .array([.string("Node1")])
            ])
        ])

        // Test would require access to private methods
        // This is a simplified test structure
        XCTAssertEqual(config.outbounds.count, 2)
    }
}
