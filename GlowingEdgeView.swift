import SwiftUI

public struct GlowingEdgeView: View {
    // ── inputs ────────────────────────────────────────────
    let isActive:  Bool
    var lineWidth: CGFloat      = 4
    var cornerRadius: CGFloat   = 36
    var inset: CGFloat          = 0        // shrink all sides equally
    var xOffset: CGFloat        = 0
    var yOffset: CGFloat        = 0

    // ── animation driver ─────────────────────────────────
    @State private var animate = false

    // Apple-style neon gradient
    private let colors: [Color] = [
        Color(hue: 0.63, saturation: 0.85, brightness: 1.0), // electric blue
        Color(hue: 0.85, saturation: 0.85, brightness: 1.0), // violet-pink
        Color(hue: 0.03, saturation: 0.90, brightness: 1.0), // hot orange
        Color(hue: 0.63, saturation: 0.85, brightness: 1.0)  // loop back to blue
    ]

    public var body: some View {
        GeometryReader { geo in
            // draw once, then rotate entirely on the GPU
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: inset)                      // shorten edges
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: colors),
                        center: .center,
                        angle: .degrees(animate ? 360 : 0)
                    ),
                    lineWidth: lineWidth
                )
                .offset(x: xOffset, y: yOffset)        // move anywhere
                .opacity(isActive ? 1 : 0)
                .animation(
                    .linear(duration: 6)
                        .repeatForever(autoreverses: false),
                    value: animate
                )
                .drawingGroup(opaque: false,           // cache to GPU
                              colorMode: .extendedLinear)
                .allowsHitTesting(false)               // let touches pass through
        }
        .onAppear { animate = true }
    }
} 
