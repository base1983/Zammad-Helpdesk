//
//  PickerEditView.swift
//  Zammad Helpdesk
//
//  Created by Bas Jonkers on 03/10/2025.
//


import SwiftUI

// A generic view for picking a value from a list.
// It automatically saves the change and dismisses itself ONLY if a subsequent action is not required.
struct PickerEditView<Item: Identifiable & Hashable>: View where Item.ID == Int {
    let title: String
    @Binding var selection: Int
    let items: [Item]
    let displayName: (Item) -> String
    let onSave: () async -> Bool // Returns true if the view should stay open, false if it should dismiss.

    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Picker(title, selection: $selection) {
                ForEach(items) { item in
                    Text(displayName(item)).tag(item.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, _ in
            Task {
                let shouldStayOpen = await onSave()
                if !shouldStayOpen {
                    // Dismiss the view after a short delay to allow the user to see the selection.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            }
        }
    }
}
