import SwiftUI

struct SplashAnimationView: View {
    var onAnimationEnd: () -> Void
    
    @State private var showLogo = false
    @State private var animateOut = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image("zammad_logoW")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .opacity(showLogo ? 1 : 0)
        }
        .opacity(animateOut ? 0 : 1)
        .task {
            withAnimation(.easeInOut(duration: 1.0)) {
                showLogo = true
            }
            
            try? await Task.sleep(for: .seconds(2.5))
            
            withAnimation(.easeInOut(duration: 0.7)) {
                animateOut = true
            }
            
            try? await Task.sleep(for: .seconds(0.7))
            onAnimationEnd()
        }
    }
}
