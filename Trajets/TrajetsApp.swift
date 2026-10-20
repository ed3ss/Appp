import SwiftUI

@main
struct TrajetsApp: App {
    @StateObject private var recorder = TripRecorder()
    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(recorder)
                .tint(.mint)
                .preferredColorScheme(.dark)
        }
    }
    @ViewBuilder private var root: some View {
        #if DEBUG
        if let screen = PreviewGallery.screen { PreviewGalleryView(screen: screen) }
        else { ContentView() }
        #else
        ContentView()
        #endif
    }
}
