import Foundation

@MainActor
final class ServerDiagnostics: ObservableObject {
    static let shared = ServerDiagnostics()

    enum SyncState: Equatable {
        case idle
        case notConfigured
        case inProgress
        case success
        case failed

        var title: String {
            switch self {
            case .idle: return "Not run yet"
            case .notConfigured: return "Not configured"
            case .inProgress: return "In progress"
            case .success: return "Healthy"
            case .failed: return "Failed"
            }
        }
    }

    struct OperationSnapshot: Equatable {
        var state: SyncState = .idle
        var lastCompletedAt: Date?
        var httpStatus: Int?
        var detail: String?
    }

    @Published private(set) var config = AppConfig.serverConfigurationSnapshot()
    @Published private(set) var upload = OperationSnapshot()
    @Published private(set) var pull = OperationSnapshot()

    private init() {
        refreshConfiguration()
    }

    var isConfigured: Bool { config.isFullyConfigured }
    var serverAvailable: Bool {
        guard isConfigured else { return false }
        return upload.state != .failed && pull.state != .failed
    }
    var localProcessingSummary: String {
        if !isConfigured {
            return "Server not configured — local processing active"
        }
        if !serverAvailable {
            return "Server offline — local processing active"
        }
        return "Server sync available — local processing active"
    }

    func refreshConfiguration() {
        config = AppConfig.serverConfigurationSnapshot()
        if !config.isFullyConfigured {
            if upload.state == .idle || upload.state == .notConfigured {
                upload = OperationSnapshot(state: .notConfigured,
                                           lastCompletedAt: nil,
                                           httpStatus: nil,
                                           detail: "WHOOP_BASE_URL and WHOOP_API_KEY are required.")
            }
            if pull.state == .idle || pull.state == .notConfigured {
                pull = OperationSnapshot(state: .notConfigured,
                                         lastCompletedAt: nil,
                                         httpStatus: nil,
                                         detail: "Server sync is disabled until both values are set.")
            }
        } else {
            if upload.state == .notConfigured { upload.state = .idle; upload.detail = nil }
            if pull.state == .notConfigured { pull.state = .idle; pull.detail = nil }
        }
    }

    func recordUploadStarted(path: String) {
        refreshConfiguration()
        guard config.isFullyConfigured else { return }
        upload.state = .inProgress
        upload.httpStatus = nil
        upload.detail = "POST \(path)"
    }

    func recordUploadFinished(path: String, statusCode: Int?, success: Bool, detail: String?) {
        refreshConfiguration()
        guard config.isFullyConfigured else { return }
        upload.state = success ? .success : .failed
        upload.lastCompletedAt = Date()
        upload.httpStatus = statusCode
        upload.detail = detail ?? "POST \(path)"
    }

    func recordPullStarted(path: String) {
        refreshConfiguration()
        guard config.isFullyConfigured else { return }
        pull.state = .inProgress
        pull.httpStatus = nil
        pull.detail = "GET \(path)"
    }

    func recordPullFinished(path: String, statusCode: Int?, success: Bool, detail: String?) {
        refreshConfiguration()
        guard config.isFullyConfigured else { return }
        pull.state = success ? .success : .failed
        pull.lastCompletedAt = Date()
        pull.httpStatus = statusCode
        pull.detail = detail ?? "GET \(path)"
    }
}
