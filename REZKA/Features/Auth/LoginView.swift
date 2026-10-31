import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var mirror = Mirror.current.absoluteString
    @State private var isLoading = false
    @State private var errorText: String?
    /// Once per launch, before the form: posters orbiting the logo, the last one becoming the background.
    @State private var showsIntro = !LoginView.introShown
    /// The intro ends on the first photo, so the screen starts there after it.
    @State private var backdrop = LoginView.introShown ? Int.random(in: 0..<Self.backdrops.count) : 0

    private static let backdrops = [PosterIntro.heroStill, "LoginBackdrop1", "LoginBackdrop2"]
    @MainActor private static var introShown = false

    var body: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 220)

            Text("Войдите в свой аккаунт HDrezka, чтобы смотреть фильмы и сериалы на Mac.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .loginField()
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .onSubmit { Task { await signIn() } }
                    .loginField()

                Button {
                    Task { await signIn() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().controlSize(.small) }
                        Text(isLoading ? "Входим…" : "Войти")
                    }
                }
                .buttonStyle(PrimaryLoginButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .padding(.top, 6)

                if let errorText {
                    Text(errorText)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 36)

            HStack(spacing: 12) {
                line
                Text("Зеркало сайта").font(.caption).foregroundStyle(.white.opacity(0.45))
                line
            }
            .padding(.top, 36)

            TextField("https://rezka.fi", text: $mirror)
                .onSubmit(applyMirror)
                .loginField()
                .padding(.top, 14)

            Text(SettingsView.mirrorHint)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .frame(width: 340)
        .padding(32)
        .opacity(showsIntro ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Backdrop(name: Self.backdrops[backdrop]) }
        .overlay {
            if showsIntro {
                PosterIntro {
                    withAnimation(.easeOut(duration: 0.8)) { showsIntro = false }
                }
                .transition(.opacity)
            }
        }
        .onAppear { Self.introShown = true }
        // The photos are dark whatever the app's theme, and run up under the title bar.
        .environment(\.colorScheme, .dark)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Another photo every so often, crossfading.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                withAnimation(.easeInOut(duration: 1.6)) { backdrop = (backdrop + 1) % Self.backdrops.count }
            }
        }
    }

    private var line: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
    }

    private func applyMirror() {
        if let url = Mirror.normalize(mirror) {
            Mirror.current = url
            mirror = url.absoluteString
            errorText = nil
            auth.refresh()
        } else {
            errorText = String(localized: "Некорректный адрес зеркала")
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

/// A photo filling the window behind the form, darkened enough for the form to read over it:
/// most of all in the middle, where the form stands.
private struct Backdrop: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(name)
            .transition(.opacity)
            .overlay(Color.black.opacity(0.45))
            .overlay(
                RadialGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 520
                )
            )
            .background(.black)
            .ignoresSafeArea()
    }
}

private extension View {
    /// A dark, borderless field like the rest of the form.
    func loginField() -> some View {
        textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1)))
    }
}

/// The white button of the form.
private struct PrimaryLoginButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(.white.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.55), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
