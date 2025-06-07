import SwiftUI

public struct GlowingEdgeView: View {
    let isActive: Bool
    @State private var gradientAngle: Double = 0
    @State private var show: Bool = false
    @State private var timer: Timer? = nil
    
    // Neon gradient colors
    private let colors: [Color] = [
        Color(red: 0.38, green: 0.0, blue: 0.65), // deep purple
        Color(red: 0.0, green: 0.22, blue: 0.65), // deep blue
        Color(red: 0.95, green: 0.38, blue: 0.0), // deep orange
        Color(red: 0.8, green: 0.0, blue: 0.38),  // deep pink
        Color(red: 0.38, green: 0.0, blue: 0.65)  // deep purple (loop)
    ]
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 36)
                    // --- outer glow ---
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: colors),
                            center: .center,
                            angle: .degrees(gradientAngle)
                        ),
                        lineWidth: 18
                    )
                    .blur(radius: 34)               // soft halo
                    .brightness(0.25)               // 🔆
                    .saturation(1.3)                // 🎨
                    .padding(-28)                   // let halo spill out
                    // --- inner highlight ---
                    .overlay(
                        RoundedRectangle(cornerRadius: 36)
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    )
                    .compositingGroup()             // isolate first…
                    .blendMode(.plusLighter)        // …then blend the whole group
                    .opacity(show ? 0.85 : 0)
                    .animation(.easeInOut(duration: 0.7), value: show)
                    .frame(width: geo.size.width + 64, height: geo.size.height + 64)
                    .offset(x: -32, y: -32)
                    .edgesIgnoringSafeArea(.all)
            }
            .onAppear {
                if isActive {
                    show = true
                    startAnimating()
                }
            }
            .onDisappear {
                stopAnimating()
                show = false
                gradientAngle = 0
            }
            .onChange(of: isActive) { active in
                if active {
                    show = true
                    startAnimating()
                } else {
                    show = false
                    stopAnimating()
                    gradientAngle = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
    
    private func startAnimating() {
        stopAnimating()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            gradientAngle += 0.2
            if gradientAngle > 360 { gradientAngle -= 360 }
        }
    }
    
    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }
} 
