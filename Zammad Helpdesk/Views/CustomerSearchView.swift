//
//  CustomerSearchView.swift
//  Zammad Helpdesk
//
//  Created by Gemini on 27.11.2025.
//

import SwiftUI

struct CustomerSearchView: View {
    @Binding var selectedCustomerId: Int?
    @ObservedObject var viewModel: TicketViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    
    private var filteredCustomers: [User] {
        if searchText.isEmpty {
            return viewModel.allUsers
        } else {
            let lowercasedQuery = searchText.lowercased()
            return viewModel.allUsers.filter { user in
                let nameMatch = user.fullname.lowercased().contains(lowercasedQuery)
                let orgNameMatch = viewModel.organizationName(for: user.organization_id)?.lowercased().contains(lowercasedQuery) ?? false
                return nameMatch || orgNameMatch
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $searchText)
                List(filteredCustomers) { user in
                    Button(action: {
                        selectedCustomerId = user.id
                        dismiss()
                    }) {
                        Text(viewModel.userName(for: user.id))
                    }
                }
            }
            .navigationTitle("select_customer".localized())
            .navigationBarItems(leading: Button("cancel".localized()) {
                dismiss()
            })
        }
    }
}
