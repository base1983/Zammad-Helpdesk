//
//  StyledSection.swift
//  Zammad Helpdesk
//
//  Created by Bas Jonkers on 30/09/2025.
//


import SwiftUI

struct StyledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading) {
            if !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            content
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
        }
    }
}

struct ToolbarButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 36, height: 36)
       //     .background(Color.primary.opacity(0.1))
            .clipShape(Circle())
            .foregroundColor(.primary)
    }
}

extension View {
    func toolbarButtonStyle() -> some View {
        self.modifier(ToolbarButtonStyle())
    }
}

