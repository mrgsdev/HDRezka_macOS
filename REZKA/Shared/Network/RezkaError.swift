import Foundation

enum RezkaError: LocalizedError {
    case loginRequired
    case badStatus(Int)
    case parsing(String)
    case site(String)
    case noStreams

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            "Нужно войти в аккаунт HDrezka."
        case let .badStatus(code):
            "Сервер ответил ошибкой \(code). Попробуйте позже или смените зеркало в настройках."
        case let .parsing(what):
            "Не удалось разобрать ответ сайта (\(what)). Возможно, изменилась вёрстка."
        case let .site(message):
            message
        case .noStreams:
            "Для этой озвучки нет доступных видео. Попробуйте другую озвучку."
        }
    }
}
