import SwiftUI

private enum TestStatus: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

private struct IndexWrapper: Identifiable {
    let value: Int
    var id: Int { value }
}

struct SetupView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var brokerHost: String = ""
    @State private var portNumber: String = "1883"
    @State private var mqttUsername: String = ""
    @State private var mqttPassword: String = ""
    @State private var launchAtLogin: Bool = LoginItemManager.launchAtLoginEnabled()
    @State private var testStatus: TestStatus = .idle
    @State private var tester: MqttConnectionTester?
    @State private var showAlert = false
    @State private var showResetConfirm = false
    @State private var subscriptions: [TopicSubscription] = []
    @State private var topicPickerTarget: IndexWrapper? = nil

    var completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("MQTT Configuration")
                    .font(.title)
                    .padding(.bottom, 4)

                // Connection section
                GroupBox {
                    VStack(spacing: 10) {
                        TextField("Hostname or IP address", text: $brokerHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("Port number", text: $portNumber)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        TextField("MQTT username (optional)", text: $mqttUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        SecureField("MQTT password (optional)", text: $mqttPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack(spacing: 12) {
                            Button("Test Connection") { runConnectionTest() }
                                .disabled(brokerHost.isEmpty || portNumber.isEmpty || testStatus == .testing)

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
                    Text("Connection").font(.headline)
                }
                .padding(.horizontal)

                // Topics section
                GroupBox {
                    VStack(spacing: 8) {
                        ForEach(subscriptions.indices, id: \.self) { i in
                            TopicRowView(
                                subscription: $subscriptions[i],
                                canRemove: subscriptions.count > 1,
                                onBrowse: { topicPickerTarget = IndexWrapper(value: i) },
                                onRemove: { subscriptions.remove(at: i) }
                            )
                            if i < subscriptions.count - 1 {
                                Divider()
                            }
                        }

                        Button(action: {
                            subscriptions.append(TopicSubscription(topic: ""))
                        }) {
                            Label("Add Topic", systemImage: "plus.circle")
                        }
                        .padding(.top, 4)
                    }
                    .padding(8)
                } label: {
                    Text("Topic Subscriptions").font(.headline)
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Reset") { showResetConfirm = true }
                        .foregroundColor(.red)
                    Button("Save Settings") { saveSettings() }
                        .buttonStyle(DefaultButtonStyle())
                }
                .padding()
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 600)
        .onAppear(perform: loadSettings)
        .sheet(item: $topicPickerTarget) { target in
            TopicPickerView(
                config: TopicDiscoveryManager.Config(
                    broker: brokerHost,
                    port: Int(portNumber) ?? 1883,
                    username: mqttUsername.isEmpty ? nil : mqttUsername,
                    password: mqttPassword.isEmpty ? nil : mqttPassword
                )
            ) { selectedTopic, selectedJsonPath in
                subscriptions[target.value].topic = selectedTopic
                subscriptions[target.value].jsonKeyPath = selectedJsonPath
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text("Both broker hostname and port number are required."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Reset Settings?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) { clearSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all saved MQTT credentials and configuration.")
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        brokerHost = defaults.string(forKey: MqttManager.mqttBrokerKey) ?? ""
        let storedPort = defaults.integer(forKey: MqttManager.mqttPortKey)
        portNumber = storedPort > 0 ? String(storedPort) : "1883"
        mqttUsername = KeychainManager.load(account: MqttManager.mqttUsernameKey) ?? ""
        mqttPassword = KeychainManager.load(account: MqttManager.mqttPasswordKey) ?? ""

        if let subs = TopicSubscription.loadAll(), !subs.isEmpty {
            subscriptions = subs
        } else if let migrated = TopicSubscription.migrateFromLegacy() {
            subscriptions = migrated
        } else {
            subscriptions = [TopicSubscription(topic: "")]
        }
    }

    private func saveSettings() {
        let validSubs = subscriptions.filter { !$0.topic.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !brokerHost.isEmpty, let portInt = Int(portNumber), !validSubs.isEmpty else {
            showAlert = true
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(brokerHost, forKey: MqttManager.mqttBrokerKey)
        defaults.set(portInt, forKey: MqttManager.mqttPortKey)

        if mqttUsername.isEmpty {
            KeychainManager.delete(account: MqttManager.mqttUsernameKey)
        } else {
            KeychainManager.save(mqttUsername, account: MqttManager.mqttUsernameKey)
        }

        if mqttPassword.isEmpty {
            KeychainManager.delete(account: MqttManager.mqttPasswordKey)
        } else {
            KeychainManager.save(mqttPassword, account: MqttManager.mqttPasswordKey)
        }

        TopicSubscription.saveAll(validSubs)
        completion()
    }

    private func clearSettings() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: MqttManager.mqttBrokerKey)
        defaults.removeObject(forKey: MqttManager.mqttPortKey)
        defaults.removeObject(forKey: MqttManager.mqttTopicKey)
        defaults.removeObject(forKey: MqttManager.mqttJsonKeyPathKey)
        defaults.removeObject(forKey: MqttManager.mqttDisplayLabelKey)
        defaults.removeObject(forKey: TopicSubscription.userDefaultsKey)
        KeychainManager.delete(account: MqttManager.mqttUsernameKey)
        KeychainManager.delete(account: MqttManager.mqttPasswordKey)
        brokerHost = ""
        portNumber = "1883"
        mqttUsername = ""
        mqttPassword = ""
        subscriptions = [TopicSubscription(topic: "")]
        testStatus = .idle
    }

    private func runConnectionTest() {
        guard !brokerHost.isEmpty, let portInt = Int(portNumber) else {
            testStatus = .failure("Enter a valid broker and port first.")
            return
        }
        testStatus = .testing
        let t = MqttConnectionTester()
        tester = t
        t.test(broker: brokerHost, port: portInt,
               username: mqttUsername.isEmpty ? nil : mqttUsername,
               password: mqttPassword.isEmpty ? nil : mqttPassword) { result in
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

// MARK: - Topic Row

private struct TopicRowView: View {
    @Binding var subscription: TopicSubscription
    let canRemove: Bool
    let onBrowse: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Label", text: Binding(
                    get: { subscription.label ?? "" },
                    set: { subscription.label = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 110)
                .help("Short label shown above the value in the menu bar")

                TextField("Topic path", text: $subscription.topic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Browse…", action: onBrowse)

                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let keyPath = subscription.jsonKeyPath, !keyPath.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("JSON key: \(keyPath)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        subscription.jsonKeyPath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}
