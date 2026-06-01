import Foundation

// MARK: - Console UI

class ConsoleUI {
    enum Color: String {
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
        case cyan = "\u{001B}[96m"
        case green = "\u{001B}[92m"
        case yellow = "\u{001B}[93m"
        case red = "\u{001B}[91m"
        case magenta = "\u{001B}[95m"
        case blue = "\u{001B}[94m"
    }

    static func clear() {
        if isatty(STDOUT_FILENO) != 0 {
            print("\u{001B}[2J\u{001B}[H", terminator: "")
        }
    }

    static func divider(char: String = "─", color: Color = .dim) {
        print("\(color.rawValue)\(String(repeating: char, count: 52))\(Color.reset.rawValue)")
    }

    static func header(_ title: String = "") {
        clear()
        print("\(Color.cyan.rawValue)\(Color.bold.rawValue)")
        print("  ╔══════════════════════════════════════════════╗")
        print("  ║        ⬡  SING-BOX NODE MANAGER  ⬡          ║")
        print("  ╚══════════════════════════════════════════════╝")
        print("\(Color.reset.rawValue)")
        if !title.isEmpty {
            print("  \(Color.magenta.rawValue)\(Color.bold.rawValue)▶  \(title)\(Color.reset.rawValue)")
            divider()
        }
    }

    static func success(_ msg: String) {
        print("\n  \(Color.green.rawValue)✔  \(msg)\(Color.reset.rawValue)")
    }

    static func error(_ msg: String) {
        print("\n  \(Color.red.rawValue)✘  \(msg)\(Color.reset.rawValue)")
    }

    static func info(_ msg: String) {
        print("\n  \(Color.blue.rawValue)ℹ  \(msg)\(Color.reset.rawValue)")
    }

    static func warn(_ msg: String) {
        print("\n  \(Color.yellow.rawValue)⚠  \(msg)\(Color.reset.rawValue)")
    }

    static func prompt(_ label: String, default: String = "") -> String {
        let hint = !`default`.isEmpty ? "\(Color.dim.rawValue)[\(`default`)]\(Color.reset.rawValue) " : ""
        print("  \(Color.cyan.rawValue)❯\(Color.reset.rawValue) \(label) \(hint): ", terminator: "")
        fflush(stdout)

        if let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty {
            return input
        }
        return `default`
    }

    static func pause() {
        print("\n  \(Color.dim.rawValue)Press Enter to continue...\(Color.reset.rawValue)", terminator: "")
        fflush(stdout)
        _ = readLine()
    }

    static func listNodes(_ nodes: [VMessNode], defaultTag: String? = nil) {
        print("  \(Color.dim.rawValue)#   Tag                         Server               Port\(Color.reset.rawValue)")
        divider()

        for (i, node) in nodes.enumerated() {
            let isDefault = node.tag == defaultTag
            let indexColor = isDefault ? "\(Color.yellow.rawValue)\(Color.bold.rawValue)" : Color.dim.rawValue
            let tagColor = isDefault ? "\(Color.green.rawValue)\(Color.bold.rawValue)" : Color.cyan.rawValue
            let star = isDefault ? "  \(Color.yellow.rawValue)★ default\(Color.reset.rawValue)" : ""

            let indexStr = String(format: "%-4d", i + 1)
            let tagStr = String(format: "%-28s", node.tag)
            let serverStr = String(format: "%-20s", node.server)

            print("  \(indexColor)\(indexStr)\(Color.reset.rawValue)\(tagColor)\(tagStr)\(Color.reset.rawValue)\(Color.dim.rawValue)\(serverStr)\(node.server_port)\(Color.reset.rawValue)\(star)")
        }

        divider()
        print("  \(Color.dim.rawValue)Total: \(nodes.count) node(s)\(Color.reset.rawValue)")
    }
}

// MARK: - Menu Item

struct MenuItem {
    let label: String
    let action: (() async -> Void)?
}

// MARK: - Application

@main
struct SingBoxManagerApp {
    static func main() async {
        let app = SingBoxManager()
        await app.run()
    }
}

actor SingBoxManager {
    private var sshManager: SSHManager?
    private var configManager: ConfigManager?
    private var nodeManager: NodeManager?

    func run() async {
        do {
            try await connect()
            try await mainMenu()
        } catch {
            ConsoleUI.error(error.localizedDescription)
        }

        if let sshManager = sshManager {
            try? await sshManager.disconnect()
        }

        ConsoleUI.clear()
        print("\n  \(ConsoleUI.Color.green.rawValue)\(ConsoleUI.Color.bold.rawValue)Disconnected. Goodbye!\(ConsoleUI.Color.reset.rawValue)\n")
    }

    private func connect() async throws {
        ConsoleUI.header("Connect to Router")

        let ip = ConsoleUI.prompt("Router IP", default: "192.168.50.1")
        let user = ConsoleUI.prompt("SSH user", default: "root")

        print("  \(ConsoleUI.Color.cyan.rawValue)❯\(ConsoleUI.Color.reset.rawValue) Password: ", terminator: "")
        fflush(stdout)

        let password = readPassword()

        ConsoleUI.info("Connecting…")

        let ssh = SSHManager(host: ip, username: user, password: password)
        try await ssh.connect()

        self.sshManager = ssh
        self.configManager = ConfigManager(sshManager: ssh)
        self.nodeManager = NodeManager(configManager: configManager!)

        ConsoleUI.success("Connected to \(ip)")
        ConsoleUI.pause()
    }

    private func mainMenu() async throws {
        let menu: [MenuItem] = [
            MenuItem(label: "List nodes", action: { try await self.listNodes() }),
            MenuItem(label: "Add node", action: { try await self.addNode() }),
            MenuItem(label: "Delete node", action: { try await self.deleteNode() }),
            MenuItem(label: "Set default node", action: { try await self.setDefaultNode() }),
            MenuItem(label: "Exit", action: nil),
        ]

        while true {
            ConsoleUI.header("Main Menu")

            for (i, item) in menu.enumerated() {
                let color = item.label == "Exit" ? ConsoleUI.Color.red : ConsoleUI.Color.blue
                print("  \(color.rawValue)\(ConsoleUI.Color.bold.rawValue)[\(i + 1)]\(ConsoleUI.Color.reset.rawValue)  \(item.label)")
            }

            ConsoleUI.divider()
            let choice = ConsoleUI.prompt("Select option")

            guard let index = Int(choice), index >= 1, index <= menu.count else {
                ConsoleUI.error("Invalid choice.")
                ConsoleUI.pause()
                continue
            }

            let item = menu[index - 1]

            if item.action == nil {
                break
            }

            do {
                try await item.action?()
            } catch {
                ConsoleUI.error(error.localizedDescription)
                ConsoleUI.pause()
            }
        }
    }

    private func listNodes() async throws {
        ConsoleUI.header("Node List")

        guard let nodeManager = nodeManager else { return }

        let nodes = try await nodeManager.listNodes()
        let defaultNode = try await nodeManager.getDefaultNode()

        if nodes.isEmpty {
            ConsoleUI.warn("No vmess nodes configured.")
            ConsoleUI.pause()
            return
        }

        ConsoleUI.listNodes(nodes, defaultTag: defaultNode?.tag)
        ConsoleUI.pause()
    }

    private func addNode() async throws {
        ConsoleUI.header("Add Node")

        let link = ConsoleUI.prompt("Paste vmess:// link")

        guard link.hasPrefix("vmess://") else {
            ConsoleUI.error("Not a valid vmess:// link.")
            ConsoleUI.pause()
            return
        }

        guard let nodeManager = nodeManager else { return }

        let node = try VMessParser.parse(link)
        try await nodeManager.addNode(link: link)

        ConsoleUI.info("Adding  \(ConsoleUI.Color.cyan.rawValue)\(node.tag)\(ConsoleUI.Color.reset.rawValue)  →  \(node.server):\(node.server_port)")
        ConsoleUI.success("Config saved and sing-box restarted.")
        ConsoleUI.pause()
    }

    private func deleteNode() async throws {
        ConsoleUI.header("Delete Node")

        guard let nodeManager = nodeManager else { return }

        let nodes = try await nodeManager.listNodes()

        if nodes.isEmpty {
            ConsoleUI.pause()
            return
        }

        ConsoleUI.listNodes(nodes)

        let indexStr = ConsoleUI.prompt("Node # to delete")

        guard let index = Int(indexStr), index >= 1, index <= nodes.count else {
            ConsoleUI.error("Invalid input.")
            ConsoleUI.pause()
            return
        }

        let tag = nodes[index - 1].tag
        try await nodeManager.deleteNode(at: index - 1)

        ConsoleUI.info("Deleting  \(ConsoleUI.Color.red.rawValue)\(tag)\(ConsoleUI.Color.reset.rawValue)")
        ConsoleUI.success("Config saved and sing-box restarted.")
        ConsoleUI.pause()
    }

    private func setDefaultNode() async throws {
        ConsoleUI.header("Set Default Node")

        guard let nodeManager = nodeManager else { return }

        let nodes = try await nodeManager.listNodes()

        if nodes.isEmpty {
            ConsoleUI.pause()
            return
        }

        ConsoleUI.listNodes(nodes)

        let indexStr = ConsoleUI.prompt("Node # to set as default")

        guard let index = Int(indexStr), index >= 1, index <= nodes.count else {
            ConsoleUI.error("Invalid input.")
            ConsoleUI.pause()
            return
        }

        let tag = nodes[index - 1].tag
        try await nodeManager.setDefaultNode(at: index - 1)

        ConsoleUI.info("Default  →  \(ConsoleUI.Color.green.rawValue)\(tag)\(ConsoleUI.Color.reset.rawValue)")
        ConsoleUI.success("Config saved and sing-box restarted.")
        ConsoleUI.pause()
    }

    private func readPassword() -> String {
        var password = ""
        while let char = readLine(strippingNewline: false) {
            if char == "\n" {
                break
            }
            password.append(char)
        }
        return password.trimmingCharacters(in: .newlines)
    }
}
