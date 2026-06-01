import Foundation

// MARK: - Config Manager

actor ConfigManager {
    private let sshManager: SSHManager
    private let configPath: String

    init(sshManager: SSHManager, configPath: String = "/etc/sing-box/config.json") {
        self.sshManager = sshManager
        self.configPath = configPath
    }

    func getConfig() async throws -> SingBoxConfig {
        let (stdout, stderr) = try await sshManager.execute("cat \(configPath)")

        if !stderr.isEmpty && stdout.isEmpty {
            throw ConfigError.readFailed(stderr)
        }

        guard let data = stdout.data(using: .utf8) else {
            throw ConfigError.decodingFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(SingBoxConfig.self, from: data)
    }

    func putConfig(_ config: SingBoxConfig) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(config)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ConfigError.encodingFailed
        }

        // Escape single quotes for shell
        let escapedJson = jsonString.replacingOccurrences(of: "'", with: "'\\''")

        let writeCommand = "echo '\(escapedJson)' > \(configPath)"
        let (_, writeErr) = try await sshManager.execute(writeCommand)

        if !writeErr.isEmpty {
            throw ConfigError.writeFailed(writeErr)
        }

        // Restart sing-box
        let (_, restartErr) = try await sshManager.execute("/etc/init.d/sing-box restart")
        if !restartErr.isEmpty {
            throw ConfigError.restartFailed(restartErr)
        }
    }

    enum ConfigError: LocalizedError {
        case readFailed(String)
        case writeFailed(String)
        case restartFailed(String)
        case decodingFailed
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .readFailed(let msg):
                return "Failed to read config: \(msg)"
            case .writeFailed(let msg):
                return "Failed to write config: \(msg)"
            case .restartFailed(let msg):
                return "Failed to restart sing-box: \(msg)"
            case .decodingFailed:
                return "Failed to decode config JSON"
            case .encodingFailed:
                return "Failed to encode config JSON"
            }
        }
    }
}

// MARK: - Node Manager

actor NodeManager {
    private let configManager: ConfigManager

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func listNodes() async throws -> [VMessNode] {
        let config = try await configManager.getConfig()
        return extractVMessNodes(from: config)
    }

    func addNode(link: String) async throws {
        guard link.hasPrefix("vmess://") else {
            throw NodeError.invalidLink
        }

        let newNode = try VMessParser.parse(link)
        var config = try await configManager.getConfig()

        // Add node to outbounds
        let nodeDict = try encodeNode(newNode)
        config.outbounds.append(nodeDict)

        // Add to selector
        if let selectorIndex = findSelectorIndex(in: config) {
            if case .object(var selectorObj) = config.outbounds[selectorIndex] {
                if case .array(var outbounds) = selectorObj["outbounds"] ?? .array([]) {
                    outbounds.append(.string(newNode.tag))
                    selectorObj["outbounds"] = .array(outbounds)
                    config.outbounds[selectorIndex] = .object(selectorObj)
                }
            }
        }

        try await configManager.putConfig(config)
    }

    func deleteNode(at index: Int) async throws {
        var config = try await configManager.getConfig()
        let nodes = extractVMessNodes(from: config)

        guard index >= 0 && index < nodes.count else {
            throw NodeError.indexOutOfRange
        }

        let tagToDelete = nodes[index].tag

        // Remove from outbounds
        config.outbounds.removeAll { outbound in
            if case .object(let obj) = outbound {
                if case .string(let type) = obj["type"],
                   case .string(let tag) = obj["tag"] {
                    return type == "vmess" && tag == tagToDelete
                }
            }
            return false
        }

        // Remove from selector
        if let selectorIndex = findSelectorIndex(in: config) {
            if case .object(var selectorObj) = config.outbounds[selectorIndex] {
                if case .array(var outbounds) = selectorObj["outbounds"] ?? .array([]) {
                    outbounds.removeAll { item in
                        if case .string(let tag) = item {
                            return tag == tagToDelete
                        }
                        return false
                    }
                    selectorObj["outbounds"] = .array(outbounds)

                    // Clear default if it matches
                    if case .string(let defaultTag) = selectorObj["default"] ?? .null,
                       defaultTag == tagToDelete {
                        selectorObj.removeValue(forKey: "default")
                    }

                    config.outbounds[selectorIndex] = .object(selectorObj)
                }
            }
        }

        try await configManager.putConfig(config)
    }

    func setDefaultNode(at index: Int) async throws {
        var config = try await configManager.getConfig()
        let nodes = extractVMessNodes(from: config)

        guard index >= 0 && index < nodes.count else {
            throw NodeError.indexOutOfRange
        }

        let tagToSet = nodes[index].tag

        guard let selectorIndex = findSelectorIndex(in: config) else {
            throw NodeError.noSelector
        }

        if case .object(var selectorObj) = config.outbounds[selectorIndex] {
            selectorObj["default"] = .string(tagToSet)
            config.outbounds[selectorIndex] = .object(selectorObj)
        }

        try await configManager.putConfig(config)
    }

    func getDefaultNode() async throws -> VMessNode? {
        let config = try await configManager.getConfig()
        let nodes = extractVMessNodes(from: config)

        guard let selectorIndex = findSelectorIndex(in: config) else {
            return nil
        }

        if case .object(let selectorObj) = config.outbounds[selectorIndex] {
            if case .string(let defaultTag) = selectorObj["default"] ?? .null {
                return nodes.first { $0.tag == defaultTag }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func extractVMessNodes(from config: SingBoxConfig) -> [VMessNode] {
        var nodes: [VMessNode] = []

        for outbound in config.outbounds {
            guard case .object(let obj) = outbound,
                  case .string(let type) = obj["type"],
                  type == "vmess" else {
                continue
            }

            if let node = decodeNode(from: obj) {
                nodes.append(node)
            }
        }

        return nodes
    }

    private func findSelectorIndex(in config: SingBoxConfig) -> Int? {
        for (index, outbound) in config.outbounds.enumerated() {
            if case .object(let obj) = outbound,
               case .string(let type) = obj["type"],
               type == "selector" {
                return index
            }
        }
        return nil
    }

    private func encodeNode(_ node: VMessNode) throws -> AnyCodable {
        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return convertToAnyCodable(dict ?? [:])
    }

    private func decodeNode(from dict: [String: AnyCodable]) -> VMessNode? {
        guard case .string(let tag) = dict["tag"],
              case .string(let server) = dict["server"],
              case .int(let port) = dict["server_port"],
              case .string(let uuid) = dict["uuid"] else {
            return nil
        }

        let security = extractString(dict["security"]) ?? "auto"
        let alterId = extractInt(dict["alter_id"]) ?? 0

        var node = VMessNode(
            type: "vmess",
            tag: tag,
            server: server,
            server_port: port,
            uuid: uuid,
            security: security,
            alter_id: alterId
        )

        // Decode transport if present
        if let transportObj = dict["transport"],
           case .object(let transportDict) = transportObj {
            if case .string(let transportType) = transportDict["type"] {
                let path = extractString(transportDict["path"])
                let serviceName = extractString(transportDict["service_name"])
                var headers: [String: String]?

                if let headersObj = transportDict["headers"],
                   case .object(let headersDict) = headersObj {
                    headers = [:]
                    for (key, value) in headersDict {
                        if case .string(let strValue) = value {
                            headers?[key] = strValue
                        }
                    }
                }

                node.transport = Transport(
                    type: transportType,
                    path: path,
                    headers: headers,
                    service_name: serviceName
                )
            }
        }

        // Decode TLS if present
        if let tlsObj = dict["tls"],
           case .object(let tlsDict) = tlsObj {
            if case .bool(let enabled) = tlsDict["enabled"] {
                let serverName = extractString(tlsDict["server_name"])
                node.tls = TLSConfig(enabled: enabled, server_name: serverName)
            }
        }

        return node
    }

    private func extractString(_ value: AnyCodable?) -> String? {
        guard let value = value else { return nil }
        if case .string(let str) = value {
            return str
        }
        return nil
    }

    private func extractInt(_ value: AnyCodable?) -> Int? {
        guard let value = value else { return nil }
        if case .int(let int) = value {
            return int
        }
        return nil
    }

    private func convertToAnyCodable(_ value: Any) -> AnyCodable {
        if let dict = value as? [String: Any] {
            var result: [String: AnyCodable] = [:]
            for (key, val) in dict {
                result[key] = convertToAnyCodable(val)
            }
            return .object(result)
        } else if let array = value as? [Any] {
            return .array(array.map { convertToAnyCodable($0) })
        } else if let string = value as? String {
            return .string(string)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            } else if number === kCFBooleanTrue as NSNumber {
                return .bool(true)
            } else if number === kCFBooleanFalse as NSNumber {
                return .bool(false)
            } else if number.doubleValue == Double(number.intValue) {
                return .int(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        }
        return .null
    }

    enum NodeError: LocalizedError {
        case invalidLink
        case indexOutOfRange
        case noSelector

        var errorDescription: String? {
            switch self {
            case .invalidLink:
                return "Invalid vmess:// link"
            case .indexOutOfRange:
                return "Node index out of range"
            case .noSelector:
                return "No selector outbound found in config"
            }
        }
    }
}
