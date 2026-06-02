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
                .foregroundStyle(.white, .blue)
                .symbolRenderingMode(.palette)

            Text("app_locked".localized())
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Button(action: onUnlock) {
                Label("unlock".localized(), systemImage: "faceid")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(30)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

