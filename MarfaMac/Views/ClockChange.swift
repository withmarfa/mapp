import Combine
import SwiftUI

extension View {
    /// Runs `change` when the calendar day turns or the system time zone changes, which are the two things that make a
    /// label made from today (a date column, a row's date, a group's heading) read wrongly. A view that shows such labels
    /// bumps a counter its body reads.
    func onClockChange(perform change: @escaping () -> Void) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
        ) { _ in change() }
    }
}
