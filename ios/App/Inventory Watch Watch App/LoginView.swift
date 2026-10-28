//
//  LoginView.swift
//  Inventory Watch Watch App
//

import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    /// Set when opened from "התחבר עם חשבון אחר": called after a successful
    /// sign-in, which adds the account to the watch and switches to it.
    var onSignedIn: (() -> Void)? = nil

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(onSignedIn == nil ? "ניהול מלאי" : "חשבון נוסף")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                if let message = model.signedOutMessage {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.lowStock)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 2) {
                    Text("להתחברות מהאייפון:")
                        .foregroundStyle(Theme.text)
                    Text("ניהול מלאי ← ⚙︎ הגדרות כלליות ← חבר את השעון לחשבון הזה")
                        .foregroundStyle(Theme.accent)
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Text("או התחבר כאן:")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                TextField("שם משתמש", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("סיסמה", text: $password)
                    .textContentType(.password)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.outOfStock)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await logIn() }
                } label: {
                    if isLoading {
                        ProgressView().tint(Theme.onAccent)
                    } else {
                        Text("התחבר").bold()
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
        }
        .background(Theme.background)
    }

    private func logIn() async {
        isLoading = true
        errorText = nil
        do {
            try await model.logIn(username: username, password: password)
            onSignedIn?()
        } catch {
            errorText = model.handle(error)
        }
        isLoading = false
    }
}
