import AppKit
import SwiftUI

/// Settings → «Детский режим»: what it does, its level, and the way in and out.
struct ParentalSection: View {
    @State private var sheet: ParentalSheet.Mode?
    private let parental = ParentalControl.shared

    var body: some View {
        Section {
            if parental.isUnreadable {
                Label("Не удалось прочитать настройки детского режима из связки ключей, поэтому включён самый строгий уровень.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Повторить", action: parental.load)
            } else if let limit = parental.limit {
                LabeledContent("Возраст", value: String(localized: "до \(limit.title)"))
                Button("Изменить или выключить…") { sheet = .manage }
            } else {
                Button("Включить детский режим…") { sheet = .setup }
            }
        } header: {
            Text("Детский режим")
        } footer: {
            Text("Скрывает фильмы и сериалы старше выбранного возраста и отзывы, не даёт их смотреть. Изменить или выключить его можно только с PIN-кодом.")
                .foregroundStyle(.secondary)
        }
        .sheet(item: $sheet) { mode in
            ParentalSheet(mode: mode)
        }
    }
}

/// The steps of turning kid mode on, changing it and getting back in with the recovery code.
struct ParentalSheet: View {
    enum Mode: String, Identifiable {
        case setup, manage
        var id: String { rawValue }
    }

    private enum Step {
        case chooseLevel
        case enterPIN
        case forgotPIN
        case manage
        /// Choosing a PIN, the first time or after the old one or the recovery code.
        case newPIN
        case showCode(String)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var level = AgeLimit.age12
    @State private var pin = ""
    @State private var pinAgain = ""
    @State private var code = ""
    @State private var message: String?

    private let parental = ParentalControl.shared

    init(mode: Mode) {
        self.mode = mode
        _step = State(initialValue: mode == .setup ? .chooseLevel : .enterPIN)
        _level = State(initialValue: ParentalControl.shared.limit ?? .age12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .chooseLevel:
            title("Детский режим", "Выберите, до какого возраста показывать фильмы и сериалы.")
            levelPicker
            footer(cancel: true) {
                Button("Дальше") { go(.newPIN) }
                    .keyboardShortcut(.defaultAction)
            }

        case .newPIN:
            title("Придумайте PIN-код", "4 цифры. Он понадобится, чтобы изменить или выключить детский режим.")
            PINField(prompt: String(localized: "PIN-код"), pin: $pin)
            PINField(prompt: String(localized: "Ещё раз"), pin: $pinAgain)
            footer(cancel: true) {
                Button(mode == .setup && parental.limit == nil ? "Включить" : "Сохранить", action: savePIN)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pin.count < 4 || pinAgain.count < 4)
            }

        case let .showCode(recovery):
            title("Код восстановления", "Сохраните его: запишите или положите в «Пароли». Если вы забудете PIN-код, этот код поможет задать новый. Больше он показан не будет.")
            HStack {
                Text(verbatim: recovery)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Button("Скопировать") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recovery, forType: .string)
                }
            }
            .padding(14)
            .background(Brand.panel, in: RoundedRectangle(cornerRadius: 10))
            footer(cancel: false) {
                Button("Я сохранил код") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

        case .enterPIN:
            title("Введите PIN-код", "Чтобы изменить или выключить детский режим.")
            PINField(prompt: String(localized: "PIN-код"), pin: $pin)
                .onSubmit(checkPIN)
            Button("Забыли PIN-код?") { go(.forgotPIN) }
                .buttonStyle(.link)
            footer(cancel: true) {
                Button("Продолжить", action: checkPIN)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pin.count < 4)
            }

        case .forgotPIN:
            title("Код восстановления", "Введите код, который был показан при включении детского режима или последней смене PIN-кода.")
            TextField(text: $code, prompt: Text(verbatim: "XXXX-XXXX-XXXX")) { EmptyView() }
                .font(.system(.title3, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit(checkCode)
            footer(cancel: true) {
                Button("Продолжить", action: checkCode)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 12)
            }

        case .manage:
            title("Детский режим", "Возраст, до которого показывать фильмы и сериалы.")
            levelPicker
            HStack {
                Button("Сменить PIN-код…") { go(.newPIN) }
                Spacer()
                Button("Выключить детский режим", role: .destructive) {
                    parental.setLimit(nil)
                    dismiss()
                }
            }
            footer(cancel: true) {
                Button("Сохранить") {
                    parental.setLimit(level)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var levelPicker: some View {
        Picker("Возраст", selection: $level) {
            ForEach(AgeLimit.allCases) { Text(verbatim: $0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func title(_ text: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.title2.bold())
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func footer(cancel: Bool, @ViewBuilder actions: () -> some View) -> some View {
        HStack {
            Spacer()
            if cancel {
                Button("Отмена", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            actions()
        }
        .padding(.top, 6)
    }

    // MARK: Steps

    private func go(_ next: Step) {
        message = nil
        pin = ""
        pinAgain = ""
        code = ""
        step = next
    }

    private func savePIN() {
        guard pin == pinAgain else {
            message = String(localized: "PIN-коды не совпадают.")
            pinAgain = ""
            return
        }
        let recovery = parental.limit == nil ? parental.enable(limit: level, pin: pin) : parental.resetPIN(to: pin)
        go(.showCode(recovery))
    }

    private func checkPIN() {
        guard pin.count == 4 else { return }
        handle(parental.check(pin: pin), next: .manage)
        pin = ""
    }

    private func checkCode() {
        handle(parental.check(recoveryCode: code), next: .newPIN)
    }

    private func handle(_ result: ParentalControl.CheckResult, next: Step) {
        switch result {
        case .ok:
            go(next)
        case .wrong:
            message = String(localized: "Неверно. Попробуйте ещё раз.")
        case let .locked(until):
            let minutes = max(1, Int(until.timeIntervalSinceNow / 60 + 0.99))
            message = String(localized: "Слишком много неверных попыток. Попробуйте через \(minutes) мин.")
        }
    }
}

/// A 4-digit PIN: digits only, no more than four.
private struct PINField: View {
    let prompt: String
    @Binding var pin: String

    var body: some View {
        SecureField(text: $pin, prompt: Text(prompt)) { EmptyView() }
            .font(.system(.title3, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
            .onChange(of: pin) { _, value in
                let digits = String(value.filter(\.isNumber).prefix(4))
                if digits != value { pin = digits }
            }
    }
}
