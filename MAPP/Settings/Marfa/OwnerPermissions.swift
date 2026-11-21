import Marfa
import SwiftUI

/// The owner's permissions an app or a key holds, told the same way on both pages: one counted row in the access
/// section, which opens a page of their own that Back returns from.
enum OwnerPermissions {
    private static let suffix = "/permissions"

    /// The sub-page that lists what the thing named by `base` (a sub-page id such as `key:<id>`) holds.
    static func subpage(of base: SettingsSubpage) -> SettingsSubpage {
        SettingsSubpage(id: base.id + suffix, title: String(localized: "Look After This Marfa"))
    }

    /// Whether `id` is the sub-page that lists the permissions of another sub-page, and which one's id that is.
    static func owner(of id: String) -> (base: String, isList: Bool) {
        id.hasSuffix(suffix) ? (String(id.dropLast(suffix.count)), true) : (id, false)
    }
}

/// The one counted row, "5 of 14", that opens the list; with none held it only says so, since there is nothing to open.
struct OwnerPermissionsRow: View {
    let held: Int
    let line: String
    let open: () -> Void

    var body: some View {
        let count = OwnerWording.permissionCount(held, of: InstancePermission.allCases.count)
        if held == 0 {
            SettingsRow(verbatim: String(localized: "Look After This Marfa"), line: line) { SettingsValue(verbatim: count) }
        } else {
            SettingsLinkRow(verbatim: String(localized: "Look After This Marfa"), line: line, value: count, action: open)
        }
    }
}

/// The page the row opens: one switch for each permission held. A thing can only lose a permission, so only what it
/// holds is listed, and turning one off asks first.
struct OwnerPermissionsList: View {
    let held: [String]
    let line: LocalizedStringKey
    let problem: String?
    let remove: (String) -> Void

    var body: some View {
        SettingsPageColumn {
            if let problem { OwnerProblem(title: "Not Changed", line: problem) }
            SettingsSection(name: Text("Look After This Marfa"), line: Text(line)) {
                if held.isEmpty {
                    SettingsRow("No Owner Permissions", look: .off)
                }
                ForEach(held, id: \.self) { permission in
                    SettingsRow(verbatim: OwnerWording.title(of: permission)) {
                        SettingsToggle(title: "Allowed", isOn: Binding { held.contains(permission) } set: { on in
                            if !on { remove(permission) }
                        })
                    }
                }
            }
        }
    }
}
