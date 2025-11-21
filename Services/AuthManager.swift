import Foundation

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var accessToken: String?

    init() {
        accessToken = "DEV_BYPASS_TOKEN"
    }
}
