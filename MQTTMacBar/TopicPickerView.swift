import SwiftUI

private enum TopicSortOrder {
    case alphabetical, byUpdateTime
}

private struct FlatNode: Identifiable {
    let node: TopicNode
    let depth: Int
    var id: String { node.id }
}

struct TopicPickerView: View {
    let config: TopicDiscoveryManager.Config
    var initialTopic: String? = nil
    var subscribedTopics: Set<String> = []
    var onSelect: (String, String?) -> Void

    @Environment(\.presentationMode) var presentationMode
    @StateObject private var discovery = TopicDiscoveryManager()
    @State private var searchText = ""
    @State private var selectedTopic: String? = nil
    @State private var selectedJsonPath: String? = nil
    @State private var sortOrder: TopicSortOrder = .alphabetical
    @State private var expandedNodes: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            searchBar
            Divider()

            if discovery.rootNodes.isEmpty {
                emptyState
            } else {
                treeList
            }

            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            discovery.start(config: config)
            if let t = initialTopic, !t.isEmpty {
                selectedTopic = t
                expandedNodes = ancestorPaths(of: t)
            }
        }
        .onDisappear { discovery.stop() }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack {
            Text("Topic Browser")
                .font(.headline)
            Spacer()
            statusBadge
            Spacer()
            Picker("", selection: $sortOrder) {
                Image(systemName: "textformat.abc").tag(TopicSortOrder.alphabetical)
                Image(systemName: "clock").tag(TopicSortOrder.byUpdateTime)
            }
            .pickerStyle(.segmented)
            .frame(width: 72)
            .help("Sort: A–Z or most recently updated")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var statusBadge: some View {
        switch discovery.state {
        case .connecting:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Connecting…").font(.caption).foregroundColor(.secondary)
            }
        case .discovering:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("\(discovery.messageCount) msgs").font(.caption).foregroundColor(.secondary)
            }
        case .stopped:
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Stopped · \(discovery.messageCount) msgs").font(.caption).foregroundColor(.secondary)
            }
        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle").foregroundColor(.red)
                Text(reason).font(.caption).foregroundColor(.red).lineLimit(1)
            }
        case .idle:
            EmptyView()
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Filter topics…", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    @ViewBuilder private var emptyState: some View {
        Spacer()
        switch discovery.state {
        case .connecting, .discovering:
            VStack(spacing: 8) {
                ProgressView()
                Text(discovery.state == .connecting ? "Connecting to broker…" : "Waiting for messages…")
                    .foregroundColor(.secondary)
            }
        default:
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.largeTitle).foregroundColor(.secondary)
                Text("No topics discovered yet").foregroundColor(.secondary)
            }
        }
        Spacer()
    }

    private var treeList: some View {
        let version = discovery.treeVersion
        let nodes = flatNodes
        return List {
            ForEach(nodes) { flat in
                TopicRowView(
                    node: flat.node,
                    treeVersion: version,
                    depth: flat.depth,
                    isExpanded: expandedNodes.contains(flat.node.id),
                    subscribedTopics: subscribedTopics,
                    onToggle: flat.node.childrenOrNil != nil ? {
                        if expandedNodes.contains(flat.node.id) {
                            expandedNodes.remove(flat.node.id)
                        } else {
                            expandedNodes.insert(flat.node.id)
                        }
                    } : nil,
                    selectedTopic: $selectedTopic,
                    selectedJsonPath: $selectedJsonPath
                )
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Tree flattening

    private var flatNodes: [FlatNode] {
        let _ = discovery.treeVersion
        return flattenNodes(filteredRoots, depth: 0)
    }

    private func flattenNodes(_ nodes: [TopicNode], depth: Int) -> [FlatNode] {
        let sorted: [TopicNode]
        if sortOrder == .byUpdateTime {
            sorted = nodes.sorted {
                ($0.latestDescendantUpdate ?? .distantPast) > ($1.latestDescendantUpdate ?? .distantPast)
            }
        } else {
            sorted = nodes
        }
        var result: [FlatNode] = []
        for node in sorted {
            result.append(FlatNode(node: node, depth: depth))
            if !node.children.isEmpty && expandedNodes.contains(node.id) {
                result += flattenNodes(node.children, depth: depth + 1)
            }
        }
        return result
    }

    private var filteredRoots: [TopicNode] {
        guard !searchText.isEmpty else { return discovery.rootNodes }
        let q = searchText.lowercased()
        return discovery.rootNodes.filter { matchesSearch($0, query: q) }
    }

    private func matchesSearch(_ node: TopicNode, query: String) -> Bool {
        if node.fullPath.lowercased().contains(query) { return true }
        return node.children.contains { matchesSearch($0, query: query) }
    }

    private func ancestorPaths(of topic: String) -> Set<String> {
        var parts = topic.split(separator: "/").map(String.init)
        var result: Set<String> = []
        while parts.count > 1 {
            parts.removeLast()
            result.insert(parts.joined(separator: "/"))
        }
        return result
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let topic = selectedTopic {
                    Text(topic)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    if let path = selectedJsonPath {
                        Text("JSON key: \(path)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                } else {
                    Text("No topic selected").foregroundColor(.secondary).font(.caption)
                }
            }
            Spacer()
            Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            Button("Select") {
                if let topic = selectedTopic {
                    onSelect(topic, selectedJsonPath)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .buttonStyle(DefaultButtonStyle())
            .disabled(selectedTopic == nil)
        }
        .padding()
    }
}

// MARK: - Topic Row

private struct TopicRowView: View {
    @ObservedObject var node: TopicNode
    let treeVersion: Int
    let depth: Int
    let isExpanded: Bool
    let subscribedTopics: Set<String>
    var onToggle: (() -> Void)?
    @Binding var selectedTopic: String?
    @Binding var selectedJsonPath: String?

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    private var isLeaf: Bool { node.childrenOrNil == nil }

    private var isSubscribed: Bool {
        isLeaf && subscribedTopics.contains(node.fullPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    Spacer().frame(width: CGFloat(depth) * 16)
                }

                // Disclosure triangle or leaf spacer
                if !isLeaf {
                    Button(action: { onToggle?() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                if isLeaf {
                    // Leaf: [✅] name  count  time
                    if isSubscribed { Text("✅").font(.caption) }
                    Text(node.segment)
                        .font(.system(.body, design: .monospaced))
                    if node.messageCount > 0 {
                        Text("\(node.messageCount) msgs")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.orange)
                        if let t = node.lastReceived {
                            Text(Self.timeFmt.string(from: t))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    // Non-leaf: (N) time  name
                    let count = node.descendantLeafCount
                    Text("(\(count))")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.primary)
                    if let t = node.latestDescendantUpdate {
                        Text(Self.timeFmt.string(from: t))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.blue)
                    }
                    Text(node.segment)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                Spacer()
            }

            // Last message preview for leaf nodes
            if isLeaf && !node.lastMessage.isEmpty {
                HStack(spacing: 0) {
                    Spacer().frame(width: CGFloat(depth) * 16 + 18)
                    Text(node.lastMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // JSON properties when this leaf is selected
            if selectedTopic == node.fullPath, let props = node.jsonProperties {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(props) { prop in
                        JsonPropertyRowView(prop: prop, selectedJsonPath: $selectedJsonPath)
                    }
                }
                .padding(.leading, CGFloat(depth) * 16 + 18)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            Group {
                if selectedTopic == node.fullPath && isLeaf {
                    RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLeaf {
                onToggle?()
            } else if !isSubscribed {
                selectedTopic = node.fullPath
                selectedJsonPath = nil
            }
        }
    }
}

// MARK: - JSON Property Row

private struct JsonPropertyRowView: View {
    @ObservedObject var prop: JsonPropertyNode
    @Binding var selectedJsonPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: prop.children != nil ? "chevron.right" : "circle.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(prop.key)
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(prop.displayValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(selectedJsonPath == prop.dotPath ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedJsonPath = prop.dotPath
            }

            if let children = prop.children {
                ForEach(children) { child in
                    JsonPropertyRowView(prop: child, selectedJsonPath: $selectedJsonPath)
                        .padding(.leading, 12)
                }
            }
        }
    }
}
