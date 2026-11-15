import SwiftUI

private struct IndexedWrapper: Identifiable {
    let value: Int
    var id: Int { value }
}

struct TopicSubscriptionsView: View {
    @ObservedObject var stats: SubscriptionStats
    @ObservedObject var connectionState: ConnectionState
    var onMarkAllSeen: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    @State private var subscriptions: [TopicSubscription] = []
    @State private var expandedRows: Set<UUID> = []
    @State private var topicPickerTarget: IndexedWrapper? = nil
    @State private var showAlert = false

    private var brokerConfig: TopicDiscoveryManager.Config {
        let broker = UserDefaults.standard.string(forKey: MqttManager.mqttBrokerKey) ?? ""
        let port = UserDefaults.standard.integer(forKey: MqttManager.mqttPortKey)
        let username = KeychainManager.load(account: MqttManager.mqttUsernameKey)
        let password = KeychainManager.load(account: MqttManager.mqttPasswordKey)
        return TopicDiscoveryManager.Config(
            broker: broker,
            port: port == 0 ? 1883 : port,
            username: username,
            password: password
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(subscriptions.indices, id: \.self) { i in
                        SubscriptionRow(
                            sub: $subscriptions[i],
                            stats: stats,
                            isExpanded: expandedBinding(for: subscriptions[i].id),
                            onBrowse: { topicPickerTarget = IndexedWrapper(value: i) },
                            onRemove: subscriptions.count > 1 ? { subscriptions.remove(at: i) } : nil
                        )
                    }
                }
                .padding()
            }

            Divider()

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
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            HStack(spacing: 12) {
                Button(action: {
                    subscriptions.append(TopicSubscription(topic: ""))
                }) {
                    Label("Add Topic", systemImage: "plus.circle")
                }

                Spacer()

                Button("Cancel") { onCancel() }
                Button("Save") { save() }
                    .buttonStyle(DefaultButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 500, minHeight: 380)
        .onAppear {
            loadSubscriptions()
            stats.markAllSeen()
            onMarkAllSeen()
        }
        .sheet(item: $topicPickerTarget) { target in
            let currentTopic = subscriptions[target.value].topic
            TopicPickerView(
                config: brokerConfig,
                initialTopic: currentTopic.isEmpty ? nil : currentTopic,
                subscribedTopics: Set(subscriptions.map(\.topic))
            ) { selectedTopic, selectedJsonPath in
                subscriptions[target.value].topic = selectedTopic
                subscriptions[target.value].jsonKeyPath = selectedJsonPath
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text("Please add at least one topic with a non-empty path."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedRows.contains(id) },
            set: { if $0 { expandedRows.insert(id) } else { expandedRows.remove(id) } }
        )
    }

    private func loadSubscriptions() {
        if let subs = TopicSubscription.loadAll(), !subs.isEmpty {
            subscriptions = subs
        } else {
            subscriptions = [TopicSubscription(topic: "")]
        }
    }

    private func save() {
        let valid = subscriptions.filter { !$0.topic.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !valid.isEmpty else {
            showAlert = true
            return
        }
        TopicSubscription.saveAll(valid)
        onSave()
    }
}

// MARK: - Subscription Row

private struct SubscriptionRow: View {
    @Binding var sub: TopicSubscription
    @ObservedObject var stats: SubscriptionStats
    @Binding var isExpanded: Bool
    var onBrowse: () -> Void
    var onRemove: (() -> Void)?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: expand toggle + topic + stats
            HStack(spacing: 6) {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text(sub.topic.isEmpty ? "(no topic)" : sub.topic)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(sub.topic.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                Spacer()

                if let count = stats.messageCount[sub.id] {
                    Text("\(count) msgs")
                        .foregroundColor(.orange)
                        .font(.caption.monospacedDigit())
                }

                if let t = stats.lastReceived[sub.id] {
                    Text(Self.timeFmt.string(from: t))
                        .foregroundColor(.blue)
                        .font(.caption.monospacedDigit())
                }
            }

            // Expanded: current value + diff
            if isExpanded {
                if let ctx = stats.lastContext[sub.id] {
                    ExpandedValueView(context: ctx)
                } else {
                    Text("No messages received yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                }
            }

            // Show in menu bar + label
            HStack(spacing: 10) {
                Toggle("Show in menu bar", isOn: $sub.showInMenuBar)
                    .toggleStyle(.checkbox)

                TextField("Label", text: Binding(
                    get: { sub.label ?? "" },
                    set: { sub.label = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 110)
                .help("Short label shown above the value in the menu bar")
                .disabled(!sub.showInMenuBar)
                .opacity(sub.showInMenuBar ? 1.0 : 0.4)
            }

            // Topic path + browse + remove
            HStack(spacing: 6) {
                TextField("Topic path", text: $sub.topic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Browse…", action: onBrowse)

                if let remove = onRemove {
                    Button(action: remove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            // JSON key path (if set)
            if let keyPath = sub.jsonKeyPath, !keyPath.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("JSON key: \(keyPath)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        sub.jsonKeyPath = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
    }
}

// MARK: - Expanded Value View

private struct ExpandedValueView: View {
    let context: MqttMessageContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prettyPrintJSON(context.rawMessage))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
                .textSelection(.enabled)

            let diffs = buildDiffLines(old: context.previousRawMessage, new: context.rawMessage)
            if !diffs.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(diffs.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(color(for: line.kind))
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.06)))
                .textSelection(.enabled)
            }
        }
    }

    private func color(for kind: DiffLineKind?) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .changed: return .orange
        case nil: return .primary
        }
    }
}
