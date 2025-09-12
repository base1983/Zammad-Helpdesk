import SwiftUI
import Lottie

struct SplashAnimationView: View {
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            LottieView(animationName: "iPhone")
                .ignoresSafeArea()
                .scaleEffect(1.2)
                .opacity(0.8)

            VStack {
                Spacer()
                
                Button(action: onComplete) {
                    Text("start_setup".localized())
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                }
            }
            .padding(40)
        }
    }
}

