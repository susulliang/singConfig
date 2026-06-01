import Foundation

// MARK: - Models

struct VMessNode: Codable {
    let type: String
    let tag: String
    let server: String
    let server_port: Int
    let uuid: String
    let security: String
    let alter_id: Int
    var transport: Transport?
    var tls: TLSConfig?

    enum CodingKeys: String, CodingKey {
        case type, tag, server, server_port, uuid, security, alter_id, transport, tls
    }
}

struct Transport: Codable {
    let type: String
    let path: String?
    var headers: [String: String]?
    let service_name: String?

    enum CodingKeys: String, CodingKey {
        case type, path, headers, service_name
    }
}

struct TLSConfig: Codable {
    let enabled: Bool
    let server_name: String?

    enum CodingKeys: String, CodingKey {
        case enabled, server_name
    }
}

struct SelectorOutbound: Codable {
    let type: String
    var outbounds: [String]
    var `default`: String?

    enum CodingKeys: String, CodingKey {
        case type, outbounds
        case `default` = "default"
    }
}

struct SingBoxConfig: Codable {
    var outbounds: [AnyCodable]

    enum CodingKeys: String, CodingKey {
        case outbounds
    }
}

// MARK: - AnyCodable Helper

enum AnyCodable: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }
}

// MARK: - VMess Link Parser

struct VMessParser {
    static func parse(_ link: String) throws -> VMessNode {
        guard link.hasPrefix("vmess://") else {
            throw ParseError.invalidFormat
        }

        let base64String = String(link.dropFirst("vmess://".count))
        var paddedBase64 = base64String
        let padding = (4 - (base64String.count % 4)) % 4
        paddedBase64.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: paddedBase64),
              let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8) else {
            throw ParseError.decodingFailed
        }

        let decoder = JSONDecoder()
        let dict = try decoder.decode([String: AnyCodable].self, from: jsonData)

        let ps = extractString(dict["ps"]) ?? extractString(dict["add"]) ?? "unnamed"
        let add = extractString(dict["add"]) ?? ""
        let port = extractInt(dict["port"]) ?? 443
        let id = extractString(dict["id"]) ?? ""
        let aid = extractInt(dict["aid"]) ?? 0
        let net = extractString(dict["net"]) ?? "tcp"
        let tlsValue = extractString(dict["tls"])
        let host = extractString(dict["host"])
        let path = extractString(dict["path"])

        var node = VMessNode(
            type: "vmess",
            tag: ps,
            server: add,
            server_port: port,
            uuid: id,
            security: "auto",
            alter_id: aid
        )

        // Configure transport
        if net == "ws" {
            var transport = Transport(type: "ws", path: path, headers: nil, service_name: nil)
            if let host = host {
                transport.headers = ["Host": host]
            }
            node.transport = transport
        } else if net == "grpc" {
            node.transport = Transport(type: "grpc", path: nil, headers: nil, service_name: path ?? "")
        }

        // Configure TLS
        if tlsValue == "tls" {
            node.tls = TLSConfig(enabled: true, server_name: host ?? add)
        }

        return node
    }

    private static func extractString(_ value: AnyCodable?) -> String? {
        guard let value = value else { return nil }
        if case .string(let str) = value {
            return str
        }
        return nil
    }

    private static func extractInt(_ value: AnyCodable?) -> Int? {
        guard let value = value else { return nil }
        if case .int(let int) = value {
            return int
        }
        return nil
    }

    enum ParseError: LocalizedError {
        case invalidFormat
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Invalid vmess:// link format"
            case .decodingFailed:
                return "Failed to decode vmess link"
            }
        }
    }
}
