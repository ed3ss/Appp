import SwiftUI

/// Native glass on iOS 26; an accessible material fallback on iOS 17–18.
struct TrajetGlass: ViewModifier {
    var radius: CGFloat = 24
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.18), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular,
                                in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.14), lineWidth: 1) }
        }
    }
}

extension View {
    func trajetGlass(radius: CGFloat = 24, interactive: Bool = false) -> some View {
        modifier(TrajetGlass(radius: radius, interactive: interactive))
    }

    @ViewBuilder
    func trajetAction(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

struct TrajetBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.025, green: 0.13, blue: 0.14), .black,
                                Color(red: 0.04, green: 0.07, blue: 0.15)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}
