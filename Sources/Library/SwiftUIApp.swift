import SwiftUI

// MARK: - SwiftUI App (macOS/iOS)

@main
struct SingBoxManagerSwiftUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - View Models

@MainActor
class ConnectionViewModel: ObservableObject {
    @Published var routerIP: String = "192.168.50.1"
    @Published var username: String = "root"
    @Published var password: String = ""
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    var sshManager: SSHManager?
    var configManager: ConfigManager?
    var nodeManager: NodeManager?

    func connect() async {
        isLoading = true
        errorMessage = nil

        let ssh = SSHManager(host: routerIP, username: username, password: password)

        do {
            try await ssh.connect()
            self.sshManager = ssh
            self.configManager = ConfigManager(sshManager: ssh)
            self.nodeManager = NodeManager(configManager: configManager!)
            isConnected = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func disconnect() async {
        if let ssh = sshManager {
            try? await ssh.disconnect()
        }
        isConnected = false
        sshManager = nil
        configManager = nil
        nodeManager = nil
    }
}

@MainActor
class NodesViewModel: ObservableObject {
    @Published var nodes: [VMessNode] = []
    @Published var defaultNode: VMessNode?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    var nodeManager: NodeManager?

    func loadNodes() async {
        guard let nodeManager = nodeManager else { return }

        isLoading = true
        errorMessage = nil

        do {
            nodes = try await nodeManager.listNodes()
            defaultNode = try await nodeManager.getDefaultNode()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func addNode(link: String) async {
        guard let nodeManager = nodeManager else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await nodeManager.addNode(link: link)
            await loadNodes()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func deleteNode(at index: Int) async {
        guard let nodeManager = nodeManager else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await nodeManager.deleteNode(at: index)
            await loadNodes()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func setDefaultNode(at index: Int) async {
        guard let nodeManager = nodeManager else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await nodeManager.setDefaultNode(at: index)
            await loadNodes()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var connectionVM = ConnectionViewModel()
    @StateObject private var nodesVM = NodesViewModel()

    var body: some View {
        if connectionVM.isConnected {
            NodesListView(connectionVM: connectionVM, nodesVM: nodesVM)
        } else {
            LoginView(connectionVM: connectionVM)
        }
    }
}

struct LoginView: View {
    @ObservedObject var connectionVM: ConnectionViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .center, spacing: 10) {
                Text("⬡")
                    .font(.system(size: 40))
                Text("SING-BOX NODE MANAGER")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 30)

            VStack(spacing: 15) {
                TextField("Router IP", text: $connectionVM.routerIP)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                TextField("SSH User", text: $connectionVM.username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $connectionVM.password)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = connectionVM.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(action: {
                Task {
                    await connectionVM.connect()
                    if connectionVM.isConnected {
                        nodesVM.nodeManager = connectionVM.nodeManager
                        await nodesVM.loadNodes()
                    }
                }
            }) {
                if connectionVM.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("Connect")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(connectionVM.isLoading)

            Spacer()
        }
        .padding()
    }
}

struct NodesListView: View {
    @ObservedObject var connectionVM: ConnectionViewModel
    @ObservedObject var nodesVM: NodesViewModel
    @State private var showAddSheet = false
    @State private var vmessLink = ""

    var body: some View {
        NavigationView {
            VStack {
                if nodesVM.isLoading {
                    ProgressView()
                } else if nodesVM.nodes.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "network")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No nodes configured")
                            .font(.headline)
                        Text("Add a vmess:// link to get started")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(nodesVM.nodes.enumerated()), id: \.element.tag) { index, node in
                            NodeRowView(
                                node: node,
                                isDefault: node.tag == nodesVM.defaultNode?.tag,
                                onSetDefault: {
                                    Task {
                                        await nodesVM.setDefaultNode(at: index)
                                    }
                                },
                                onDelete: {
                                    Task {
                                        await nodesVM.deleteNode(at: index)
                                    }
                                }
                            )
                        }
                    }
                }

                if let error = nodesVM.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }
            .navigationTitle("Nodes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Disconnect") {
                        Task {
                            await connectionVM.disconnect()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddNodeSheet(
                    vmessLink: $vmessLink,
                    isPresented: $showAddSheet,
                    onAdd: {
                        Task {
                            await nodesVM.addNode(link: vmessLink)
                            vmessLink = ""
                            showAddSheet = false
                        }
                    }
                )
            }
            .onAppear {
                Task {
                    await nodesVM.loadNodes()
                }
            }
        }
    }
}

struct NodeRowView: View {
    let node: VMessNode
    let isDefault: Bool
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.tag)
                        .font(.headline)
                        .fontWeight(isDefault ? .bold : .regular)
                        .foregroundColor(isDefault ? .green : .primary)

                    Text("\(node.server):\(node.server_port)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                if isDefault {
                    Label("Default", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
            }

            HStack(spacing: 10) {
                Button(action: onSetDefault) {
                    Label("Set Default", systemImage: "star")
                        .font(.caption)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddNodeSheet: View {
    @Binding var vmessLink: String
    @Binding var isPresented: Bool
    let onAdd: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Paste your vmess:// link")
                    .font(.headline)

                TextEditor(text: $vmessLink)
                    .border(Color.gray)
                    .frame(minHeight: 100)

                Button(action: onAdd) {
                    Text("Add Node")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(vmessLink.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Add Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
