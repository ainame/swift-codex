import Foundation

/// Identifies a turn by thread and turn ID. Turn IDs are not assumed to be
/// unique across threads, so routing never keys on a turn ID alone.
struct TurnKey: Hashable, Sendable, CustomStringConvertible {
    let threadID: String
    let turnID: String

    var description: String { "\(threadID)/\(turnID)" }
}

/// Bounds for notification buffering. Exceeding a bound never truncates a
/// stream silently: the affected consumer gets an explicit error instead.
struct NotificationBufferLimits: Sendable, Hashable {
    /// Per-turn replay history retained until the turn completes and is consumed.
    var maxNotificationsPerTurn = 10_000
    /// Completed turns whose stream was never requested, evicted oldest first.
    var maxUnclaimedCompletedTurns = 64
    /// Raw `nextNotification()` backlog, dropped oldest first.
    var maxRawBacklog = 10_000
    /// Remembered retired turn keys, used to explain why a stream is unavailable.
    var maxRetiredTurns = 256
    /// Distinct speculative turns buffered while one turn/start is pending.
    var maxPendingTurnCandidates = 64
}

/// Demultiplexes app-server notifications into per-turn streams.
///
/// The router is a value owned by the `CodexRPCTransport` actor, so every
/// mutation is actor-isolated and ordered with input processing. A route opens
/// when the `turn/start` response is processed, before any later input line,
/// so notifications that arrive before `stream()` is called are replayed.
///
/// Routing policy:
/// - Notifications with both a thread ID and a turn ID go to that turn only.
/// - Notifications with a thread ID but no turn ID (for example
///   `thread/started` or `thread/status/changed`) go to every open turn of
///   that thread.
/// - Notifications without a thread ID are global and are only available via
///   the raw `nextNotification()` queue.
/// - A route finishes on `turn/completed` whose thread and turn both match.
struct TurnStreamRouter {
    typealias Continuation = AsyncThrowingStream<CodexNotification, Error>.Continuation

    private struct Consumer {
        let token: UUID
        let continuation: Continuation
    }

    private struct Route {
        // Full history so a replacement consumer can replay from the start.
        var history: [CodexNotification] = []
        var replayable = true
        var completed = false
        var consumer: Consumer?
    }

    private struct PendingBuffer {
        var events: [(sequence: Int, notification: CodexNotification)] = []
        var overflowed = false
    }

    private struct PendingStart {
        let threadID: String
        var sequence = 0
        var threadEvents = PendingBuffer()
        var turnEvents: [String: PendingBuffer] = [:]
        var candidateLimitExceeded = false
    }

    var limits: NotificationBufferLimits
    private var routes: [TurnKey: Route] = [:]
    private var unclaimedCompleted: [TurnKey] = []
    private var retired: [(key: TurnKey, reason: TurnStreamUnavailableReason)] = []
    private var pendingStarts: [String: PendingStart] = [:]

    init(limits: NotificationBufferLimits = .init()) {
        self.limits = limits
    }

    var openRouteCount: Int { routes.count }

    // MARK: turn/start bookkeeping

    /// Buffers notifications for `threadID` while its `turn/start` is in flight,
    /// in case the server emits turn events before the response.
    mutating func beginTurnStart(requestID: String, threadID: String) {
        pendingStarts[requestID] = PendingStart(threadID: threadID)
    }

    mutating func cancelTurnStart(requestID: String) {
        pendingStarts.removeValue(forKey: requestID)
    }

    mutating func completeTurnStart(requestID: String, key: TurnKey) {
        let pending = pendingStarts.removeValue(forKey: requestID)
        // A reused key (for example after reopening) replaces the old route.
        unclaimedCompleted.removeAll { $0 == key }
        if let stale = routes.removeValue(forKey: key)?.consumer {
            stale.continuation.finish(throwing: CodexError.invalidResponse("Turn \(key) was started again"))
        }
        let threadEvents = pending?.threadEvents ?? PendingBuffer()
        let turnEvents = pending?.turnEvents[key.turnID] ?? PendingBuffer()
        if threadEvents.overflowed || turnEvents.overflowed
            || (pending?.candidateLimitExceeded == true && pending?.turnEvents[key.turnID] == nil) {
            retire(key, reason: .bufferLimitExceeded)
            return
        }
        retired.removeAll { $0.key == key }
        var history = (threadEvents.events + turnEvents.events).sorted { $0.sequence < $1.sequence }.map(\.notification)
        if history.count > limits.maxNotificationsPerTurn {
            retire(key, reason: .bufferLimitExceeded)
            return
        }
        let completion = history.firstIndex { isCompletion($0, for: key) }
        if let completion {
            history.removeSubrange(history.index(after: completion)...)
        }
        routes[key] = Route(history: history)
        if completion != nil {
            markCompleted(key)
        }
    }

    // MARK: routing

    mutating func route(_ notification: CodexNotification) {
        guard let threadID = notification.threadID else { return }
        // Events of an already open turn cannot belong to a turn still starting.
        let belongsToOpenTurn = notification.turnID.map { routes[TurnKey(threadID: threadID, turnID: $0)] != nil } ?? false
        if !belongsToOpenTurn {
            for requestID in pendingStarts.keys where pendingStarts[requestID]?.threadID == threadID {
                bufferPending(notification, requestID: requestID)
            }
        }
        if let turnID = notification.turnID {
            deliver(notification, to: TurnKey(threadID: threadID, turnID: turnID))
        } else {
            for key in routes.keys where key.threadID == threadID {
                deliver(notification, to: key)
            }
        }
    }

    private mutating func bufferPending(_ notification: CodexNotification, requestID: String) {
        guard var pending = pendingStarts[requestID] else { return }
        var buffer: PendingBuffer
        if let turnID = notification.turnID {
            if pending.turnEvents[turnID] == nil && pending.turnEvents.count >= limits.maxPendingTurnCandidates {
                pending.candidateLimitExceeded = true
                pendingStarts[requestID] = pending
                return
            }
            buffer = pending.turnEvents[turnID] ?? PendingBuffer()
        } else {
            buffer = pending.threadEvents
        }
        if !buffer.overflowed {
            buffer.events.append((pending.sequence, notification))
            pending.sequence += 1
            if buffer.events.count > limits.maxNotificationsPerTurn {
                buffer.events.removeAll()
                buffer.overflowed = true
            }
        }
        if let turnID = notification.turnID { pending.turnEvents[turnID] = buffer }
        else { pending.threadEvents = buffer }
        pendingStarts[requestID] = pending
    }

    private mutating func deliver(_ notification: CodexNotification, to key: TurnKey) {
        guard var route = routes[key], !route.completed else { return }
        if let consumer = route.consumer, case .terminated = consumer.continuation.yield(notification) {
            // Cancellation can precede the asynchronous detach callback. Keep
            // the event (especially completion) for a replacement consumer.
            route.consumer = nil
        }
        if route.replayable {
            route.history.append(notification)
            if route.history.count > limits.maxNotificationsPerTurn {
                route.history.removeAll()
                route.replayable = false
            }
        }
        routes[key] = route

        if isCompletion(notification, for: key) {
            if let consumer = route.consumer {
                routes.removeValue(forKey: key)
                retire(key, reason: .alreadyConsumed)
                consumer.continuation.finish()
            } else if route.replayable {
                markCompleted(key)
            } else {
                routes.removeValue(forKey: key)
                retire(key, reason: .bufferLimitExceeded)
            }
        } else if route.consumer == nil, !route.replayable {
            // Nobody can ever receive a complete stream for this turn.
            routes.removeValue(forKey: key)
            retire(key, reason: .bufferLimitExceeded)
        }
    }

    private mutating func markCompleted(_ key: TurnKey) {
        guard routes[key] != nil else { return }
        routes[key]?.completed = true
        unclaimedCompleted.append(key)
        while unclaimedCompleted.count > limits.maxUnclaimedCompletedTurns {
            let evicted = unclaimedCompleted.removeFirst()
            routes.removeValue(forKey: evicted)
            retire(evicted, reason: .evicted)
        }
    }

    private func isCompletion(_ notification: CodexNotification, for key: TurnKey) -> Bool {
        notification.method == "turn/completed"
            && notification.threadID == key.threadID
            && notification.turnID == key.turnID
    }

    // MARK: consumers

    /// Attaches the only consumer for `key`, replaying buffered history first.
    mutating func attach(_ key: TurnKey, token: UUID, continuation: Continuation) throws {
        guard var route = routes[key] else {
            let reason = retired.last(where: { $0.key == key })?.reason ?? .unknownTurn
            throw CodexError.turnStreamUnavailable(threadID: key.threadID, turnID: key.turnID, reason: reason)
        }
        if route.consumer != nil {
            throw CodexError.concurrentTurnConsumer(activeTurnID: key.turnID, requestedTurnID: key.turnID)
        }
        for notification in route.history {
            continuation.yield(notification)
        }
        if route.completed {
            routes.removeValue(forKey: key)
            unclaimedCompleted.removeAll { $0 == key }
            retire(key, reason: .alreadyConsumed)
            continuation.finish()
            return
        }
        route.consumer = Consumer(token: token, continuation: continuation)
        routes[key] = route
    }

    /// Token-scoped: a late termination of an old consumer is a no-op.
    mutating func detach(_ key: TurnKey, token: UUID) {
        guard var route = routes[key], route.consumer?.token == token else { return }
        route.consumer = nil
        if route.replayable {
            routes[key] = route
        } else {
            routes.removeValue(forKey: key)
            retire(key, reason: .bufferLimitExceeded)
        }
    }

    /// Terminates every in-progress route. Completed but unclaimed turns keep
    /// their full history, so they can still be streamed after EOF.
    mutating func failAll(_ error: Error) {
        pendingStarts.removeAll()
        for (key, route) in routes where !route.completed {
            routes.removeValue(forKey: key)
            retire(key, reason: .transportClosed)
            route.consumer?.continuation.finish(throwing: error)
        }
    }

    private mutating func retire(_ key: TurnKey, reason: TurnStreamUnavailableReason) {
        retired.removeAll { $0.key == key }
        retired.append((key, reason))
        if retired.count > limits.maxRetiredTurns {
            retired.removeFirst(retired.count - limits.maxRetiredTurns)
        }
    }
}
