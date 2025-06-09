import SwiftUI
import MetalKit

struct RippleEffectModifier: ViewModifier {
    var amplitude: CGFloat = 0.12
    var frequency: CGFloat = 2.0
    var speed: CGFloat = 0.6
    var color: Color = Color.purple

    func body(content: Content) -> some View {
        content
            .overlay(
                RippleEffectView(amplitude: amplitude, frequency: frequency, speed: speed, color: color)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func rippleEffect(amplitude: CGFloat = 0.12, frequency: CGFloat = 2.0, speed: CGFloat = 0.6, color: Color = .purple) -> some View {
        self.modifier(RippleEffectModifier(amplitude: amplitude, frequency: frequency, speed: speed, color: color))
    }
}

struct RippleEffectView: UIViewRepresentable {
    var amplitude: CGFloat
    var frequency: CGFloat
    var speed: CGFloat
    var color: Color

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.isOpaque = false
        mtkView.backgroundColor = .clear
        // Metal setup will be handled in GlowingEdgeView
        return mtkView
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
} 