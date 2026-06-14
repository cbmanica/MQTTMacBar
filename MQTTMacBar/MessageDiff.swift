import Foundation

enum DiffLineKind { case added, removed, changed }

struct DiffLine {
    let text: String
    let kind: DiffLineKind?
}

func buildDiffLines(old: String?, new: String) -> [DiffLine] {
    guard let old = old, old != new else { return [] }

    if let oldJson = parseJSONObject(old), let newJson = parseJSONObject(new) {
        let allKeys = Set(oldJson.keys).union(newJson.keys).sorted()
        var lines: [DiffLine] = []
        for key in allKeys {
            let o = oldJson[key]
            let n = newJson[key]
            switch (o, n) {
            case (nil, let n?):
                lines.append(DiffLine(text: "+ \(key): \(anyToString(n))", kind: .added))
            case (let o?, nil):
                lines.append(DiffLine(text: "- \(key): \(anyToString(o))", kind: .removed))
            case (let o?, let n?) where anyToString(o) != anyToString(n):
                lines.append(DiffLine(text: "~ \(key): \(anyToString(o)) → \(anyToString(n))", kind: .changed))
            default:
                break
            }
        }
        return lines
    }

    return [DiffLine(text: "~ \(old) → \(new)", kind: .changed)]
}

func anyToString(_ value: Any) -> String {
    if let dict = value as? [String: Any],
       let data = try? JSONSerialization.data(withJSONObject: dict),
       let s = String(data: data, encoding: .utf8) { return s }
    if let arr = value as? [Any],
       let data = try? JSONSerialization.data(withJSONObject: arr),
       let s = String(data: data, encoding: .utf8) { return s }
    return "\(value)"
}

func prettyPrintJSON(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
          let s = String(data: pretty, encoding: .utf8) else {
        return raw
    }
    return s
}

private func parseJSONObject(_ s: String) -> [String: Any]? {
    guard let data = s.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}
