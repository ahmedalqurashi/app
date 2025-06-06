import SwiftUI

public struct GlowingEdgeView: View {
    let isActive: Bool
    @State private var gradientAngle: Double = 0
    @State private var show: Bool = false
    
    // Neon gradient colors
    private let colors: [Color] = [
        Color(red: 0.63, green: 0.18, blue: 1.0), // purple
        Color(red: 0.22, green: 0.78, blue: 1.0), // blue
        Color(red: 1.0, green: 0.71, blue: 0.35), // orange
        Color(red: 1.0, green: 0.36, blue: 0.66), // pink
        Color(red: 0.63, green: 0.18, blue: 1.0)  // purple (loop)
    ]
    
    public var body: some View {
        ZStack {
            Color.red.opacity(0.3) // Debug background
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 36)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: colors),
                                center: .center,
                                angle: .degrees(gradientAngle)
                            ),
                            lineWidth: 24
                        )
                        .blur(radius: 8)
                        .opacity(show ? 1.0 : 0.2)
                        .animation(.easeInOut(duration: 0.7), value: show)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .border(Color.yellow, width: 4) // Debug border
                        .edgesIgnoringSafeArea(.all)
                }
                .onAppear {
                    print("GlowingEdgeView size: \(geo.size)")
                    if isActive {
                        show = true
                        animateGradient()
                    }
                }
                .onChange(of: isActive) { active in
                    if active {
                        show = true
                        animateGradient()
                    } else {
                        show = false
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
    
    private func animateGradient() {
        withAnimation(Animation.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            gradientAngle = 360
        }
    }
} 
