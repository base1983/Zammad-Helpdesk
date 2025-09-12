//
//  LottieView.swift
//  ZammadMobile
//
//  Created by Bas Jonkers on 09/09/2025.
//


import SwiftUI
import Lottie

// Een herbruikbare SwiftUI-view die een Lottie-animatie kan afspelen.
// Dit is een 'brug' naar de UIKit-gebaseerde Lottie-bibliotheek.
struct LottieView: UIViewRepresentable {
    let animationName: String
    
    // Maakt de Lottie-animatieview aan.
    func makeUIView(context: Context) -> some UIView {
        let view = UIView(frame: .zero)
        let animationView = LottieAnimationView()
        
        // Laad de animatie uit het opgegeven JSON-bestand.
        animationView.animation = LottieAnimation.named(animationName)
        animationView.contentMode = .scaleAspectFill
        animationView.loopMode = .loop // Zorgt ervoor dat de animatie oneindig doorgaat.
        animationView.play() // Start de animatie.
        
        // Zorg ervoor dat de animatie de hele view vult.
        animationView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.heightAnchor.constraint(equalTo: view.heightAnchor),
            animationView.widthAnchor.constraint(equalTo: view.widthAnchor)
        ])
        
        return view
    }

    // Deze functie is vereist, maar we hoeven niets te updaten.
    func updateUIView(_ uiView: UIViewType, context: Context) {}
}
