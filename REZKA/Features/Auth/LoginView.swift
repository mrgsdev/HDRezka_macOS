import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mirror = Mirror.current.absoluteString
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 26) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 300)

            Text("Войдите в свой аккаунт HDrezka, чтобы смотреть фильмы и сериалы на Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .onSubmit { Task { await signIn() } }

                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().controlSize(.small) }
                        Text(isLoading ? "Входим…" : "Войти")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 6) {
                Text("Зеркало сайта")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://rezka.fi", text: $mirror)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyMirror)
                Text(SettingsView.mirrorHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 400)
        .padding(44)
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
    }

    private func applyMirror() {
        if let url = Mirror.normalize(mirror) {
            Mirror.current = url
            mirror = url.absoluteString
            errorText = nil
            auth.refresh()
        } else {
            errorText = "Некорректный адрес зеркала"
        }
    }

    private func signIn() async {
        guard !isLoading, !email.isEmpty, !password.isEmpty else { return }
        applyMirror()
        isLoading = true
        errorText = nil
        do {
            try await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
