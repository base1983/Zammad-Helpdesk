//
//  LockedView.swift
//  Zammad Helpdesk
//
//  Created by Bas Jonkers on 30/09/2025.
//


import SwiftUI

struct LockedView: View {
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("app_locked".localized())
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Button(action: onUnlock) {
                Label("unlock".localized(), systemImage: "faceid")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

