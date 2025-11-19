import SwiftUI

struct SplashAnimationView: View {
    var onAnimationEnd: () -> Void
    
    @State private var showLogo = false
    @State private var animateOut = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image("zammad_logoW") // Assuming this is in your assets
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .opacity(showLogo ? 1 : 0)
        }
        .opacity(animateOut ? 0 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                showLogo = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.7)) {
                    animateOut = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                onAnimationEnd()
            }
        }
    }
}
