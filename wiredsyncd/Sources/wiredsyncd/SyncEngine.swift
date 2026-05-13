import Foundation
import AppKit
import Network
final class SyncEngine {
    private let state: DaemonState
    private let specPath: String
    private let lock = NSLock()
    private var sessionsByPairID: [String: PairSession] = [:]
    private var networkMonitor: NWPathMonitor?
    private var wakeMonitorTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastNetworkStatus: NWPath.Status?
    private var lastGlobalReconnectSignalAt: Date?
    private let globalSignalDebounce: TimeInterval = 15

    init(state: DaemonState, specPath: String) {
        self.state = state
        self.specPath = specPath
    }

    func start() {
        for pair in state.snapshotPairs().filter({ !$0.paused }) {
            startOrReplaceSession(for: pair.id)
        }
        installNetworkMonitor()
        installWakeMonitor()
    }

    func stop() {
        networkMonitor?.cancel()
        networkMonitor = nil
        wakeMonitorTask?.cancel()
        wakeMonitorTask = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        let sessions: [PairSession]
        lock.lock()
        sessions = Array(sessionsByPairID.values)
        sessionsByPairID.removeAll()
        lock.unlock()
        for session in sessions {
            session.stop()
        }
    }

    func activeCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByPairID.count
    }

    func handlePairAdded(_ pairID: String) {
        startOrReplaceSession(for: pairID)
    }

    func handlePairRemoved(_ pairID: String) {
        let session: PairSession?
        lock.lock()
        session = sessionsByPairID.removeValue(forKey: pairID)
        lock.unlock()
        session?.stop()
        state.clearRuntimeStatus(pairID: pairID)
    }

    func handlePairsRemoved(_ pairIDs: [String]) {
        for pairID in pairIDs {
            handlePairRemoved(pairID)
        }
    }

    func handlePairUpdated(_ pairID: String) {
        startOrReplaceSession(for: pairID)
    }

    func handlePairPaused(_ pairID: String) {
        let session: PairSession?
        lock.lock()
        session = sessionsByPairID.removeValue(forKey: pairID)
        lock.unlock()
        session?.stop()
        state.setRuntimeStatus(pairID: pairID, state: .paused, lastError: .some(nil), retryCount: 0, nextRetryAt: .some(nil))
    }

    func handlePairResumed(_ pairID: String) {
        startOrReplaceSession(for: pairID)
    }

    func handleReload() {
        let pairs = state.snapshotPairs()
        let desired = Set(pairs.filter { !$0.paused }.map(\.id))
        let current = Set(state.runtimeStatusesSnapshot().keys)
        for pairID in current.subtracting(Set(pairs.map(\.id))) {
            handlePairRemoved(pairID)
        }
        for pair in pairs {
            if pair.paused {
                handlePairPaused(pair.id)
            } else {
                startOrReplaceSession(for: pair.id)
            }
        }
        for stale in current.subtracting(desired) {
            handlePairPaused(stale)
        }
    }

    func triggerNow(remotePath: String?, serverURL: String?, login: String?) -> (matched: Int, launched: Int) {
        let normalizedServer = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = state.snapshotPairs().filter { pair in
            guard !pair.paused else { return false }
            guard let remotePath else { return true }
            guard pair.remotePath == remotePath else { return false }
            if let normalizedServer, !normalizedServer.isEmpty, pair.endpoint.serverURL != normalizedServer {
                return false
            }
            if let normalizedLogin, !normalizedLogin.isEmpty, pair.endpoint.login != normalizedLogin {
                return false
            }
            return true
        }

        var launched = 0
        for pair in pairs {
            let existingSession = session(for: pair.id)
            if existingSession == nil {
                startOrReplaceSession(for: pair.id)
                launched += 1
            }
            session(for: pair.id)?.signalSyncNow(reason: "sync_now_rpc")
        }
        return (pairs.count, launched)
    }

    private func startOrReplaceSession(for pairID: String) {
        guard let pair = state.pair(id: pairID), !pair.paused else {
            handlePairPaused(pairID)
            return
        }

        let previous: PairSession?
        let session = PairSession(pairID: pairID, state: state, specPath: specPath)
        lock.lock()
        previous = sessionsByPairID.updateValue(session, forKey: pairID)
        lock.unlock()
        previous?.stop()
        state.setRuntimeStatus(pairID: pairID, state: .disconnected, lastError: .some(nil), retryCount: 0, nextRetryAt: .some(nil))
        session.start()
    }

    private func session(for pairID: String) -> PairSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessionsByPairID[pairID]
    }

    private func signalReconnectAll(reason: String, force: Bool = false) {
        lock.lock()
        let now = Date()
        if !force, let last = lastGlobalReconnectSignalAt, now.timeIntervalSince(last) < globalSignalDebounce {
            lock.unlock()
            state.appendLog("daemon.reconnect_all_skipped reason=\(reason) debounce=true")
            return
        }
        lastGlobalReconnectSignalAt = now
        let sessions: [PairSession]
        sessions = Array(sessionsByPairID.values)
        lock.unlock()
        state.appendLog("daemon.reconnect_all reason=\(reason) sessions=\(sessions.count)")
        for session in sessions {
            session.signalReconnectNow(reason: reason)
        }
    }

    private func signalSyncAll(reason: String, force: Bool = false) {
        lock.lock()
        let now = Date()
        if !force, let last = lastGlobalReconnectSignalAt, now.timeIntervalSince(last) < globalSignalDebounce {
            lock.unlock()
            state.appendLog("daemon.sync_all_skipped reason=\(reason) debounce=true")
            return
        }
        lastGlobalReconnectSignalAt = now
        let sessions: [PairSession]
        sessions = Array(sessionsByPairID.values)
        lock.unlock()
        state.appendLog("daemon.sync_all reason=\(reason) sessions=\(sessions.count)")
        for session in sessions {
            session.signalSyncNow(reason: reason)
        }
    }

    private func installNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            let previous = self.lastNetworkStatus
            let current = path.status
            self.lastNetworkStatus = current
            self.lock.unlock()

            guard let previous else {
                self.state.appendLog("daemon.network_path_initial status=\(current)")
                return
            }
            guard previous != current else { return }

            self.state.appendLog("daemon.network_path_changed from=\(previous) to=\(current)")
            if current == .unsatisfied {
                self.state.appendLog("daemon.network_path_unavailable status=\(current)")
                return
            }
            self.signalSyncAll(reason: "network_path_changed", force: false)
        }
        monitor.start(queue: DispatchQueue(label: "wiredsyncd.network-monitor"))
        networkMonitor = monitor
    }

    private func installWakeMonitor() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.state.appendLog("daemon.did_wake")
            self?.signalSyncAll(reason: "did_wake", force: true)
        }

        wakeMonitorTask = Task.detached(priority: .background) { [weak self] in
            var previous = Date()
            while let self, self.state.isRunning() {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                let now = Date()
                if now.timeIntervalSince(previous) > 120 {
                    self.state.appendLog("daemon.sleep_wake_detected")
                    self.signalSyncAll(reason: "sleep_wake_detected", force: true)
                }
                previous = now
            }
        }
    }
}
