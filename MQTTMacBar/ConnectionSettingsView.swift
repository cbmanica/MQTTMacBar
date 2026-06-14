import SwiftUI

private enum ConnTestStatus: Equatable {
    case idle, testing, success
    case failure(String)
}

struct ConnectionSettingsView: View {
    @ObservedObject var connectionState: ConnectionState
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var broker: String = ""
    @State private var port: String = "1883"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = false
    @State private var savedBroker: String = ""
    @State private var savedPort: String = "1883"
    @State private var savedUsername: String = ""
    @State private var savedPassword: String = ""
    @State private var savedUseSSL: Bool = false
    @State private var launchAtLogin: Bool = LoginItemManager.launchAtLoginEnabled()
    @State private var testStatus: ConnTestStatus = .idle
    @State private var tester: MqttConnectionTester?
    @State private var showAlert = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    private var settingsChanged: Bool {
        broker != savedBroker || port != savedPort || username != savedUsername || password != savedPassword || useSSL != savedUseSSL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Connection Settings")
                    .font(.title)
                    .padding(.bottom, 4)

                GroupBox {
                    VStack(spacing: 10) {
                        TextField("Broker IP/Hostname", text: $broker)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack {
                            TextField("Port (e.g., 1883)", text: $port)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Toggle("SSL/TLS", isOn: $useSSL)
                                .toggleStyle(.checkbox)
                        }

                        TextField("Username (optional)", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        SecureField("Password (optional)", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack(spacing: 6) {
                            if connectionState.isConnected {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                if let since = connectionState.connectedAt {
                                    Text("Connected since \(Self.timeFmt.string(from: since))").foregroundColor(.green)
                                } else {
                                    Text("Connected").foregroundColor(.green)
                                }
                            } else {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text("Disconnected").foregroundColor(.red)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button("Test Connection") { runConnectionTest() }
                                .disabled(broker.isEmpty || port.isEmpty || testStatus == .testing || (connectionState.isConnected && !settingsChanged))

                            switch testStatus {
                            case .idle:
                                EmptyView()
                            case .testing:
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.75)
                                Text("Testing…").foregroundColor(.secondary)
                            case .success:
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text("Connected successfully").foregroundColor(.green)
                            case .failure(let reason):
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text(reason).foregroundColor(.red).lineLimit(2)
                            }
                        }
                        .frame(minHeight: 24)

                        Toggle(isOn: $launchAtLogin) {
                            if LoginItemManager.isInstalledBuild {
                                Text("Launch at Login")
                            } else {
                                Text("Launch at Login")
                                    + Text(" (run make install first)").foregroundColor(.secondary)
                            }
                        }
                        .disabled(!LoginItemManager.isInstalledBuild)
                        .onChange(of: launchAtLogin) { newValue in
                            LoginItemManager.setLaunchAtLogin(enabled: newValue)
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Broker").font(.headline)
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Cancel") { onCancel() }
                    Button("Save") { save() }
                        .buttonStyle(DefaultButtonStyle())
                }
                .padding()
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear(perform: loadSettings)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text("Please provide Broker IP/Hostname and Port."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        broker = defaults.string(forKey: MqttManager.mqttBrokerKey) ?? ""
        let portInt = defaults.integer(forKey: MqttManager.mqttPortKey)
        port = (portInt == 0) ? "1883" : String(portInt)
        username = KeychainManager.load(account: MqttManager.mqttUsernameKey) ?? ""
        password = KeychainManager.load(account: MqttManager.mqttPasswordKey) ?? ""
        useSSL = defaults.bool(forKey: MqttManager.mqttUseSSLKey)
        savedBroker = broker
        savedPort = port
        savedUsername = username
        savedPassword = password
        savedUseSSL = useSSL
    }

    private func save() {
        guard !broker.isEmpty, let portInt = Int(port) else {
            showAlert = true
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(broker, forKey: MqttManager.mqttBrokerKey)
        defaults.set(portInt, forKey: MqttManager.mqttPortKey)
        defaults.set(useSSL, forKey: MqttManager.mqttUseSSLKey)

        if username.isEmpty {
            KeychainManager.delete(account: MqttManager.mqttUsernameKey)
        } else {
            KeychainManager.save(username, account: MqttManager.mqttUsernameKey)
        }

        if password.isEmpty {
            KeychainManager.delete(account: MqttManager.mqttPasswordKey)
        } else {
            KeychainManager.save(password, account: MqttManager.mqttPasswordKey)
        }

        onSave()
    }

    private func runConnectionTest() {
        guard !broker.isEmpty, let portInt = Int(port) else {
            testStatus = .failure("Enter a valid broker and port first.")
            return
        }
        testStatus = .testing
        let t = MqttConnectionTester()
        tester = t
        t.test(broker: broker, port: portInt,
               username: username.isEmpty ? nil : username,
               password: password.isEmpty ? nil : password,
               useSSL: useSSL) { result in
            tester = nil
            switch result {
            case .success:
                testStatus = .success
            case .failure(let err):
                testStatus = .failure(err.localizedDescription)
            }
        }
    }
}
