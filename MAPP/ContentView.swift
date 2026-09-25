import SwiftUI

struct ContentView: View {
    var body: some View {
        ContentUnavailableView("No Note Selected", systemImage: "note.text")
            .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
