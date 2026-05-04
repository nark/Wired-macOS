import Foundation
import WiredSwift
final class PairSession {
    private let state: DaemonState
    private let specPath: String
    private let pairID: String
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var shouldStop = false
    private var pendingSyncNow = false
    private var pendingReconnect = false
    private var pendingSyncReason: String?
    private var pendingReconnectReason: String?
    private var loopSignal: CheckedContinuation<Void, Never>?
    private var currentConnection: AsyncConnection?
    private var scheduledWakeTask: Task<Void, Never>?
    private var wakeTimedOut = false
    private var retryCount = 0
    private let reconnectSchedule: [TimeInterval] = [1, 2, 4, 8, 15, 30, 60]
    private let steadyStateSyncInterval: TimeInterval = 30

    init(pairID: String, state: DaemonState, specPath: String) {
        self.pairID = pairID
        self.state = state
        self.specPath = specPath
    }

    func start() {
        lock.lock()
        guard task == nil else {
            lock.unlock()
            signalSyncNow(reason: "session_start_existing")
            return
        }
        shouldStop = false
        task = Task.detached(priority: .utility) { [weak self] in
            await self?.run()
        }
        lock.unlock()
    }

    func stop() {
        let taskToCancel: Task<Void, Never>?
        let connection: AsyncConnection?
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        shouldStop = true
        taskToCancel = task
        connection = currentConnection
        currentConnection = nil
        continuation = loopSignal
        loopSignal = nil
        scheduledWakeTask?.cancel()
        scheduledWakeTask = nil
        task = nil
        pendingReconnect = false
        pendingSyncNow = false
        lock.unlock()
        connection?.disconnect()
        continuation?.resume()
        taskToCancel?.cancel()
        state.setRuntimeStatus(pairID: pairID, state: .disconnected, retryCount: 0, nextRetryAt: .some(nil))
        state.appendLog("pair.session_stop id=\(pairID)")
    }

    func signalSyncNow(reason: String = "manual") {
        resumeLoop(syncNow: true, reconnect: false, dueToTimeout: false, reason: reason)
    }

    func signalReconnectNow(reason: String = "manual") {
        resumeLoop(syncNow: true, reconnect: true, dueToTimeout: false, reason: reason)
    }

    private func resumeLoop(syncNow: Bool, reconnect: Bool, dueToTimeout: Bool, reason: String?) {
        let continuation: CheckedContinuation<Void, Never>?
        let connection: AsyncConnection?
        lock.lock()
        if syncNow {
            pendingSyncNow = true
            if let reason {
                pendingSyncReason = reason
            }
        }
        if reconnect {
            pendingReconnect = true
            if let reason {
                pendingReconnectReason = reason
            }
        }
        if dueToTimeout {
            wakeTimedOut = true
        }
        continuation = loopSignal
        loopSignal = nil
        scheduledWakeTask?.cancel()
        scheduledWakeTask = nil
        connection = reconnect ? currentConnection : nil
        if reconnect {
            currentConnection = nil
        }
        lock.unlock()
        connection?.disconnect()
        continuation?.resume()
    }

    private func run() async {
        state.appendLog("pair.session_start id=\(pairID)")
        while state.isRunning() && !isStopped {
            guard let pair = state.pair(id: pairID) else {
                state.clearRuntimeStatus(pairID: pairID)
                break
            }
            if pair.paused {
                state.setRuntimeStatus(pairID: pairID, state: .paused, retryCount: 0, nextRetryAt: .some(nil))
                break
            }

            let spec = P7Spec(withPath: specPath)
            let worker = SyncPairWorker(pair: pair, store: state.store, secrets: state.secrets, specPath: specPath) { [weak state] line in
                state?.appendLog(line)
            }
            let control = AsyncConnection(withSpec: spec)
            control.clientInfoDelegate = DaemonClientInfoDelegate()
            control.nick = DaemonIdentity.nick(forRemotePath: pair.remotePath)
            control.icon = DaemonIdentity.folderIconBase64()
            control.interactive = true
            setConnection(control)

            do {
                state.setRuntimeStatus(
                    pairID: pairID,
                    state: retryCount == 0 ? .connecting : .reconnecting,
                    lastError: retryCount == 0 ? .some(nil) : nil,
                    nextRetryAt: .some(nil)
                )
                state.appendLog("pair.connecting id=\(pairID)")
                let url = try await worker.connectControlIfNeeded(connection: control)
                let now = Date()
                retryCount = 0
                state.setRuntimeStatus(
                    pairID: pairID,
                    state: .connected,
                    lastError: .some(nil),
                    retryCount: 0,
                    nextRetryAt: .some(nil),
                    lastConnectedAt: .some(now)
                )
                state.appendLog("pair.connected id=\(pairID)")
                let shouldReconnect = await runConnectedLoop(pair: pair, worker: worker, control: control, spec: spec, url: url)
                worker.disconnectControl(connection: control)
                clearConnection(control)
                if shouldReconnect {
                    continue
                }
                break
            } catch {
                worker.disconnectControl(connection: control)
                clearConnection(control)
                if handleCycleError(error, pair: pair, duringConnect: true) {
                    let delay = state.runtimeStatus(pairID: pairID)?.nextRetryAt?.timeIntervalSinceNow ?? jitteredBackoff()
                    await sleepBeforeReconnect(delay: max(0.1, delay))
                    continue
                }
                break
            }
        }
        if let pair = state.pair(id: pairID), !pair.paused, state.runtimeStatus(pairID: pairID)?.state != .paused {
            state.setRuntimeStatus(pairID: pairID, state: .disconnected, retryCount: 0, nextRetryAt: .some(nil))
        }
    }

    private func runConnectedLoop(
        pair: SyncPair,
        worker: SyncPairWorker,
        control: AsyncConnection,
        spec: P7Spec,
        url: Url
    ) async -> Bool {
        var runImmediateCycle = true
        var nextSyncAt = Date()
        while state.isRunning() && !isStopped {
            let decision = consumeSignals()
            if decision.forceReconnect {
                state.appendLog("pair.reconnect_aborted id=\(pairID) reason=\(decision.reconnectReason ?? "signal")")
                return true
            }

            let now = Date()
            let shouldRunSync = runImmediateCycle || decision.runSyncNow || now >= nextSyncAt
            if shouldRunSync {
                do {
                    state.setRuntimeStatus(pairID: pairID, state: .syncing, lastSyncStartedAt: .some(Date()))
                    let cycleReason = runImmediateCycle ? "initial_connect" : (decision.syncReason ?? "scheduled")
                    state.appendLog("pair.sync_cycle_start id=\(pairID) reason=\(cycleReason)")
                    let remoteInventoryAvailable = try await worker.runCycle(connection: control, spec: spec, url: url)
                    let completedAt = Date()
                    state.setRuntimeStatus(
                        pairID: pairID,
                        state: .connected,
                        lastError: .some(nil),
                        lastSyncCompletedAt: .some(completedAt),
                        remoteInventoryAvailable: .some(remoteInventoryAvailable)
                    )
                    state.appendLog("pair.sync_cycle_done id=\(pairID) reason=\(cycleReason)")
                    runImmediateCycle = false
                    nextSyncAt = completedAt.addingTimeInterval(steadyStateSyncInterval)
                    continue
                } catch {
                    let shouldReconnect = handleCycleError(error, pair: pair, duringConnect: false)
                    if shouldReconnect {
                        return true
                    }
                    runImmediateCycle = false
                    let retryAt = Date()
                    nextSyncAt = retryAt.addingTimeInterval(steadyStateSyncInterval)
                    continue
                }
            }

            let waitSeconds = max(0.1, nextSyncAt.timeIntervalSinceNow)
            runImmediateCycle = await waitForNextEvent(seconds: waitSeconds)
        }
        return false
    }

    private func handleCycleError(_ error: Error, pair: SyncPair, duringConnect: Bool) -> Bool {
        let errorText = describeSyncError(error)
        state.appendLog("pair.sync_cycle_error id=\(pairID) during_connect=\(duringConnect) error=\(errorText)")

        let nsError = error as NSError
        if nsError.domain == "wiredsyncd.sync", nsError.code == 950 {
            if (try? state.setPaused(id: pair.id, paused: true)) == true {
                state.appendLog("pair.paused id=\(pair.id) reason=local_path_missing_client_to_server")
                state.setRuntimeStatus(pairID: pairID, state: .paused, lastError: .some(errorText))
                return false
            }
        }

        let reconnect = duringConnect || shouldReconnect(for: error)
        if reconnect {
            retryCount += 1
            let nextRetryAt = Date().addingTimeInterval(jitteredBackoff())
            state.setRuntimeStatus(
                pairID: pairID,
                state: .reconnecting,
                lastError: .some(errorText),
                retryCount: retryCount,
                nextRetryAt: .some(nextRetryAt)
            )
            state.appendLog("pair.reconnecting id=\(pairID) during_connect=\(duringConnect) error=\(errorText)")
            state.appendLog("pair.reconnect_scheduled id=\(pairID) retry=\(retryCount) at=\(ISO8601DateFormatter().string(from: nextRetryAt))")
            return true
        }

        state.setRuntimeStatus(pairID: pairID, state: .error, lastError: .some(errorText), nextRetryAt: .some(nil))
        return false
    }

    private func waitForNextEvent(seconds: TimeInterval) async -> Bool {
        let decision = consumeSignals()
        if decision.forceReconnect || decision.runSyncNow {
            return decision.runSyncNow
        }
        _ = await waitForSignalOrTimeout(seconds: seconds, timeoutTriggersSync: false)
        return false
    }

    private func sleepBeforeReconnect(delay: TimeInterval) async {
        _ = await waitForSignalOrTimeout(seconds: delay, timeoutTriggersSync: false)
    }

    private func waitForSignalOrTimeout(seconds: TimeInterval, timeoutTriggersSync: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            var shouldResumeImmediately = false
            lock.lock()
            if pendingSyncNow || pendingReconnect || shouldStop {
                shouldResumeImmediately = true
            } else {
                loopSignal = continuation
                let timeoutTask = Task.detached(priority: .utility) { [weak self] in
                    guard let self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0.05, seconds) * 1_000_000_000))
                    } catch {
                        return
                    }
                    self.resumeLoop(syncNow: timeoutTriggersSync, reconnect: false, dueToTimeout: true, reason: timeoutTriggersSync ? "timer" : nil)
                }
                scheduledWakeTask = timeoutTask
            }
            lock.unlock()
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
        return consumeWakeTimeoutState()
    }

    private func jitteredBackoff() -> TimeInterval {
        let index = min(max(retryCount - 1, 0), reconnectSchedule.count - 1)
        let base = reconnectSchedule[index]
        let jitter = base * 0.2
        return max(0.5, base + Double.random(in: -jitter...jitter))
    }

    private func shouldReconnect(for error: Error) -> Bool {
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           shouldReconnect(for: underlying) {
            return true
        }
        if let asyncError = error as? AsyncConnectionError {
            switch asyncError {
            case .notConnected, .writeFailed:
                return true
            case .serverError(let message):
                let code = message.enumeration(forField: "wired.error") ?? 0
                return code == 0
            }
        }
        if nsError.domain == "wiredsyncd.sync" {
            return [200, 201, 202, 203, 204, 902, 903].contains(nsError.code)
        }
        return false
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return shouldStop
    }

    private func consumeSignals() -> (runSyncNow: Bool, forceReconnect: Bool, syncReason: String?, reconnectReason: String?) {
        lock.lock()
        let decision = (pendingSyncNow, pendingReconnect, pendingSyncReason, pendingReconnectReason)
        pendingSyncNow = false
        pendingReconnect = false
        pendingSyncReason = nil
        pendingReconnectReason = nil
        lock.unlock()
        return decision
    }

    private func setConnection(_ connection: AsyncConnection) {
        lock.lock()
        currentConnection = connection
        lock.unlock()
    }

    private func clearConnection(_ connection: AsyncConnection) {
        lock.lock()
        if currentConnection === connection {
            currentConnection = nil
        }
        lock.unlock()
    }

    private func consumeWakeTimeoutState() -> Bool {
        lock.lock()
        let timedOut = wakeTimedOut
        wakeTimedOut = false
        scheduledWakeTask?.cancel()
        scheduledWakeTask = nil
        loopSignal = nil
        lock.unlock()
        return timedOut
    }
}

