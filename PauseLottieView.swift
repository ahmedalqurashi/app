import SwiftUI
import Lottie

struct PauseLottieView: UIViewRepresentable {
    func makeUIView(context: Context) -> some UIView {
        let animationView = LottieAnimationView(name: "pause_animation") // Ensure this matches your Lottie file name
        animationView.loopMode = .loop
        animationView.play()
        return animationView
    }
    func updateUIView(_ uiView: UIViewType, context: Context) {}
} 
