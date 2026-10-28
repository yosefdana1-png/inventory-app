//
//  AccountsView.swift
//  Inventory Watch Watch App
//

import SwiftUI

/// Navigation value for the "החלף חשבון" screen.
struct AccountsRoute: Hashable {}

/// The accounts saved on this watch. Tapping one switches to it without a
/// password; each can be removed; "התחבר עם חשבון אחר" adds another.
struct AccountsView: View {
    @Environment(AppModel.self) private var model

    @State private var switchingTo: String?
    @State private var errorText: String?
    @State private var accountToRemove: StoredAccount?
    @State private var showAddAccount = false

    var body: some View {
        List {
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(Theme.outOfStock)
                    .listRowBackground(Color.clear)
            }

            ForEach(model.accounts) { account in
                Button {
                    Task { await select(account) }
                } label: {
                    row(for: account)
                }
                .disabled(switchingTo != nil)
                .listRowBackground(CardBackground())
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        accountToRemove = account
                    } label: {
                        Label("הסר", systemImage: "trash")
                    }
                }
            }

            Button {
                showAddAccount = true
            } label: {
                Label("התחבר עם חשבון אחר", systemImage: "person.badge.plus")
                    .foregroundStyle(Theme.text)
            }
            .listRowBackground(CardBackground())

            Text("להסרת חשבון מהשעון: החלק אותו הצידה.")
                .font(.footnote)
                .foregroundStyle(Theme.mutedText)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("החלף חשבון")
        .containerBackground(Theme.background, for: .navigation)
        .confirmationDialog(
            "להסיר את \(accountToRemove?.shownName ?? "") מהשעון?",
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
        ) {
            Button("הסר", role: .destructive) {
                if let account = accountToRemove {
                    Task { await model.removeAccount(account.username) }
                }
                accountToRemove = nil
            }
            Button("ביטול", role: .cancel) { accountToRemove = nil }
        }
        .sheet(isPresented: $showAddAccount) {
            LoginView(onSignedIn: { showAddAccount = false })
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    private func row(for account: StoredAccount) -> some View {
        let isActive = account.username == model.activeUsername
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.shownName)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(account.username)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if switchingTo == account.username {
                ProgressView()
                    .frame(width: 20, height: 20)
            } else if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("פעיל")
            }
        }
    }

    private func select(_ account: StoredAccount) async {
        guard account.username != model.activeUsername else { return }
        switchingTo = account.username
        errorText = nil
        errorText = await model.switchAccount(to: account.username)
        switchingTo = nil
    }
}
