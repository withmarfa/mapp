import Foundation

nonisolated extension SyncedSetting {
    /// A returning row must decode on its own before it joins a stored setting. One bad row
    /// could otherwise cause the reader to discard its readable neighbors.
    struct Reader: Sendable {
        let accepts: @MainActor @Sendable (String, PreferenceUnit) -> Bool

        static func json<T: Decodable>(_ type: T.Type) -> Self {
            Self { text, _ in
                do {
                    _ = try JSONDecoder().decode(T.self, from: Data(text.utf8))
                    return true
                } catch {
                    return false
                }
            }
        }

        static func word<T: RawRepresentable>(_ type: T.Type) -> Self where T.RawValue == String {
            Self { text, _ in
                guard let word = PreferenceJSON.value(text) as? String else { return false }
                return T(rawValue: word) != nil
            }
        }

        static let sidebar = Self { text, unit in
            let layout = PreferencesSidebar.layout(from: [unit: text])
            guard !layout.isEmpty, let encoded = try? JSONSerialization.data(withJSONObject: layout) else { return false }
            return (try? JSONDecoder().decode(SidebarLayout.self, from: encoded)) != nil
        }
    }

    @MainActor func setAsideRejected(_ text: String, in defaults: UserDefaults) {
        if key == DateFormat.key {
            Self.setAside((PreferenceJSON.value(text) as? String) ?? text, in: .string(DateFormat.setAsideKey), defaults)
        } else if let kind = setAsideKind {
            Self.setAside(text, in: kind, defaults)
        }
    }
}
