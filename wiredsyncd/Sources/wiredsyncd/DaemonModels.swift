import Foundation
import SQLite3
import WiredSwift
let kDaemonVersion = "29"
let kDaemonNick = "wiredsyncd"

enum SQLiteBindings {
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

final class DaemonClientInfoDelegate: ClientInfoDelegate {
    private let applicationInfo = WiredApplicationInfo.current().overriding(name: "wiredsyncd")

    func clientInfoApplicationName(for connection: Connection) -> String? {
        applicationInfo.name
    }

    func clientInfoApplicationVersion(for connection: Connection) -> String? {
        applicationInfo.version
    }

    func clientInfoApplicationBuild(for connection: Connection) -> String? {
        applicationInfo.build
    }
}

enum SyncMode: String, Codable {
    case serverToClient = "server_to_client"
    case clientToServer = "client_to_server"
    case bidirectional = "bidirectional"
}

struct SyncEndpoint: Codable {
    var serverURL: String
    var login: String
    var password: String

    enum CodingKeys: String, CodingKey {
        case serverURL
        case login
    }

    enum LegacyCodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case login
        case password
    }

    init(serverURL: String, login: String, password: String) {
        self.serverURL = serverURL
        self.login = login
        self.password = password
    }

    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           c.contains(.serverURL) || c.contains(.login) {
            let lc = try decoder.container(keyedBy: LegacyCodingKeys.self)
            serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
                ?? lc.decodeIfPresent(String.self, forKey: .serverURL)
                ?? ""
            login = try c.decodeIfPresent(String.self, forKey: .login)
                ?? lc.decodeIfPresent(String.self, forKey: .login)
                ?? ""
            password = try lc.decodeIfPresent(String.self, forKey: .password) ?? ""
            return
        }

        let lc = try decoder.container(keyedBy: LegacyCodingKeys.self)
        serverURL = try lc.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        login = try lc.decodeIfPresent(String.self, forKey: .login) ?? ""
        password = try lc.decodeIfPresent(String.self, forKey: .password) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serverURL, forKey: .serverURL)
        try c.encode(login, forKey: .login)
    }
}

struct SyncPair: Codable {
    var id: String
    var remotePath: String
    var localPath: String
    var mode: SyncMode
    var deleteRemoteEnabled: Bool
    /// Newline-separated glob patterns for files to exclude from sync.
    var excludePatterns: [String]
    var endpoint: SyncEndpoint
    var paused: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case remotePath
        case localPath
        case mode
        case deleteRemoteEnabled
        case excludePatterns
        case endpoint
        case paused
        case createdAt
        case updatedAt
    }

    enum LegacyCodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case login
        case password
    }

    init(
        id: String,
        remotePath: String,
        localPath: String,
        mode: SyncMode,
        deleteRemoteEnabled: Bool,
        excludePatterns: [String] = [],
        endpoint: SyncEndpoint,
        paused: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.remotePath = remotePath
        self.localPath = localPath
        self.mode = mode
        self.deleteRemoteEnabled = deleteRemoteEnabled
        self.excludePatterns = excludePatterns
        self.endpoint = endpoint
        self.paused = paused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        remotePath = try c.decode(String.self, forKey: .remotePath)
        localPath = try c.decode(String.self, forKey: .localPath)
        mode = try c.decodeIfPresent(SyncMode.self, forKey: .mode) ?? .bidirectional
        deleteRemoteEnabled = try c.decodeIfPresent(Bool.self, forKey: .deleteRemoteEnabled) ?? false
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? []
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        if let endpoint = try c.decodeIfPresent(SyncEndpoint.self, forKey: .endpoint) {
            self.endpoint = endpoint
        } else {
            let lc = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let url = try lc.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
            let login = try lc.decodeIfPresent(String.self, forKey: .login) ?? ""
            let password = try lc.decodeIfPresent(String.self, forKey: .password) ?? ""
            self.endpoint = SyncEndpoint(serverURL: url, login: login, password: password)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(remotePath, forKey: .remotePath)
        try c.encode(localPath, forKey: .localPath)
        try c.encode(mode, forKey: .mode)
        try c.encode(deleteRemoteEnabled, forKey: .deleteRemoteEnabled)
        try c.encode(excludePatterns, forKey: .excludePatterns)
        try c.encode(endpoint, forKey: .endpoint)
        try c.encode(paused, forKey: .paused)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

enum PairConnectionState: String {
    case disconnected
    case connecting
    case connected
    case syncing
    case reconnecting
    case error
    case paused
}

struct PairRuntimeStatus {
    let pairID: String
    var state: PairConnectionState
    var lastError: String?
    var retryCount: Int
    var nextRetryAt: Date?
    var lastConnectedAt: Date?
    var lastSyncStartedAt: Date?
    var lastSyncCompletedAt: Date?
    var remoteInventoryAvailable: Bool?

    init(
        pairID: String,
        state: PairConnectionState = .disconnected,
        lastError: String? = nil,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastConnectedAt: Date? = nil,
        lastSyncStartedAt: Date? = nil,
        lastSyncCompletedAt: Date? = nil,
        remoteInventoryAvailable: Bool? = nil
    ) {
        self.pairID = pairID
        self.state = state
        self.lastError = lastError
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastConnectedAt = lastConnectedAt
        self.lastSyncStartedAt = lastSyncStartedAt
        self.lastSyncCompletedAt = lastSyncCompletedAt
        self.remoteInventoryAvailable = remoteInventoryAvailable
    }
}

struct DaemonConfig: Codable {
    var pairs: [SyncPair] = []
}

struct RPCRequest: Codable {
    var jsonrpc: String?
    var id: String?
    var method: String
    var params: [String: String]?
}

struct UploadedItemSnapshot {
    let relativePath: String
    let size: UInt64
    let modificationTime: TimeInterval
}

