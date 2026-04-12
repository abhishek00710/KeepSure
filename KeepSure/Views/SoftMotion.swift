import SwiftUI

struct SoftEntranceModifier: ViewModifier {
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.985)
            .task {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                    return
                }
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.easeOut(duration: 0.45)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func softEntrance(delay: Double = 0) -> some View {
        modifier(SoftEntranceModifier(delay: delay))
    }
}
