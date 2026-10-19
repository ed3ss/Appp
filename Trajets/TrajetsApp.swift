import SwiftUI

@main
struct TrajetsApp: App {
    @StateObject private var recorder = TripRecorder()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .tint(.mint)
                .preferredColorScheme(.dark)
        }
    }
}
