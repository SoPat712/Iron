//
//  PhoneConnectionManager.swift
//  WatchIron Extension
//
//  Created by Karim Abou Zeid on 02.11.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import WatchConnectivity
import Combine
import HealthKit
import os.log

class PhoneConnectionManager: NSObject, ObservableObject {
    static let shared = PhoneConnectionManager()
    
    private let session = WCSession.default
    
    var objectWillChange = ObservableObjectPublisher() // called when something with the connection changes
    
    func activateSession() {
        assert(WCSession.isSupported())
        session.delegate = self
        session.activate()
    }
    
    var isReachable: Bool {
        session.isReachable
    }
    
    var isActivated: Bool {
        session.activationState == .activated
    }
    
    private let scheduleDiscardUnstartedWorkoutSessionSubject = PassthroughSubject<Void, Never>()
    private var cancellable: AnyCancellable?
    private var pendingUserInfo: [[String: Any]] = []
    private var eventSendInFlight = Set<UUID>()
    private var eventTransferSent = Set<UUID>()

    override init() {
        cancellable = scheduleDiscardUnstartedWorkoutSessionSubject
            .debounce(for: .seconds(60), scheduler: RunLoop.main) // seems to be a bug in watchOS, when using the accessQueue, debounce fires immediately (watchOS 6.2)
            .receive(on: WorkoutSessionManager.accessQueue)
            .sink {
                os_log("Running scheduled check whether current workout session was never started")
                guard let state = WorkoutSessionManagerStore.shared.workoutSessionManager?.state, state == .prepared || state == .notStarted else { return } // not really necessary
                guard WorkoutSessionManagerStore.shared.workoutSessionManager?.uuid == nil else { return } // make sure the UUID is nil
                os_log("Discarding workout session that is still in the prepared state after 60 seconds have passed since last prepare message")
                WorkoutSessionManagerStore.shared.discardUnstartedWorkoutSession()
            }
    }

    private func queueUntilActivated(_ userInfo: [String: Any]) {
        // Keep only a bounded number of legacy commands. Durable workout edits
        // use the outbox below and are never held in this transient queue.
        if pendingUserInfo.count >= 32 {
            pendingUserInfo.removeFirst()
        }
        pendingUserInfo.append(userInfo)
    }

    private func flushPendingUserInfo() {
        guard isActivated else { return }
        let pending = pendingUserInfo
        pendingUserInfo.removeAll()
        pending.forEach { sendUserInfo(userInfo: $0) }
    }
}

// MARK: - Receiving
extension PhoneConnectionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print(#function + " \(activationState)")
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.flushPendingUserInfo()
            self.flushEventOutbox()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print(#function + " \(applicationContext)")
        
        receive(message: applicationContext)
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print(#function + " \(userInfo)")
        
        receive(message: userInfo)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print(#function + " \(message)")
        
        receive(message: message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print(#function + " \(message)")
        
        receive(message: message)
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print(#function + " \(session.isReachable)")
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.flushEventOutbox()
        }
    }
}

// MARK: - Message Handling
extension PhoneConnectionManager {
    private func receive(message: [String : Any]) {
        if let snapshotData = message[PayloadKey.workoutSnapshot] as? Data,
           let snapshot = WatchWorkoutWire.decode(WatchWorkoutSnapshot.self, from: snapshotData) {
            WorkoutSessionManagerStore.shared.applyWorkoutSnapshot(snapshot)
        } else if let ackData = message[PayloadKey.workoutEventAck] as? Data,
                  let ack = WatchWorkoutWire.decode(WatchWorkoutEventAck.self, from: ackData) {
            do {
                try WatchWorkoutStore.shared.acknowledge(eventIDs: ack.eventIDs)
            } catch {
                // The durable outbox still contains these events. Allow a later
                // connectivity transition to redeliver them and obtain another
                // idempotent ACK, but avoid an immediate retry loop.
                ack.eventIDs.forEach {
                    eventSendInFlight.remove($0)
                    eventTransferSent.remove($0)
                }
                WorkoutSessionManagerStore.shared.reportPersistenceFailure(error)
                return
            }
            ack.eventIDs.forEach {
                eventSendInFlight.remove($0)
                eventTransferSent.remove($0)
            }
            WorkoutSessionManagerStore.shared.notifySyncStateChanged()
            flushEventOutbox()
        } else if let startMessage = message[PayloadKey.startWorkoutSession] as? [String : Any] {
            handleStartWorkoutSessionMessage(message: startMessage)
        } else if let endMessage = message[PayloadKey.endWorkoutSession] as? [String : Any] {
            handleEndWorkoutSessionMessage(message: endMessage)
        } else if let updateStartMessage = message[PayloadKey.updateWorkoutSessionStart] as? [String : Any] {
            handleUpdateWorkoutSessionStartMessage(message: updateStartMessage)
        } else if let updateEndMessage = message[PayloadKey.updateWorkoutSessionEnd] as? [String : Any] {
            handleUpdateWorkoutSessionEndMessage(message: updateEndMessage)
        } else if let updateRestTimerMessage = message[PayloadKey.updateWorkoutSessionRestTimer] as? [String : Any] {
            handleUpdateRestTimerMessage(message: updateRestTimerMessage)
        } else if let updateSelectedSetMessage = message[PayloadKey.updateWorkoutSessionSelectedSet] as? [String : Any] {
            handleUpdateSelectedSetMessage(message: updateSelectedSetMessage)
        } else if let discardMessage = message[PayloadKey.discardWorkoutSession] as? [String : Any] {
            handleDiscardWorkoutSessionMessage(message: discardMessage)
        } else if let unprepare = message[PayloadKey.ignoredPreparedWorkoutSession] as? Bool, unprepare {
            handleIgnoredPreparedWorkoutSession()
        } else {
            assertionFailure("Unrecognized message: \(message)")
        }
    }
    
    /**
     starts the workout session with the given uuid
     if there is a current workout session with the same uuid, only the start date will be updated
     if there is a current workout session with a different uuid, it is discarded and a new workout session is started
     */
    private func handleStartWorkoutSessionMessage(message: [String : Any]) {
        guard let start = message[PayloadKey.Arg.start] as? Date else {
            assertionFailure("start workout with no start parameter")
            return
        }
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("start workout with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.startWorkoutSession(start: start, uuid: uuid)
    }
    
    private func handleEndWorkoutSessionMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        guard let start = message[PayloadKey.Arg.start] as? Date else {
            assertionFailure("end workout with no start parameter")
            return
        }
        guard let end = message[PayloadKey.Arg.end] as? Date else {
            assertionFailure("end workout with no end parameter")
            return
        }
        let title = message[PayloadKey.Arg.title] as? String // nil is allowed
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("end workout with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.endWorkoutSession(start: start, end: end,
                                                            title: title, uuid: uuid,
                                                            notifyPhone: false)
    }
    
    private func handleUpdateWorkoutSessionStartMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        guard let start = message[PayloadKey.Arg.start] as? Date else {
            assertionFailure("update workout start with no start parameter")
            return
        }
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("update workout start with no uuid parameter")
            return
        }

        WorkoutSessionManagerStore.shared.updateWorkoutSessionStart(start: start, uuid: uuid)
    }
    
    private func handleUpdateWorkoutSessionEndMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        let end = message[PayloadKey.Arg.end] as? Date // nil is allowed
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("update workout end with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.updateWorkoutSessionEnd(end: end, uuid: uuid)
    }
    
    private func handleUpdateRestTimerMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        let end = message[PayloadKey.Arg.end] as? Date // nil is allowed
        let keepRunning = message[PayloadKey.Arg.keepRestTimerRunning] as? Bool // nil is allowed
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("update rest timer with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.updateWorkoutSessionRestTimer(end: end, keepRunning: keepRunning, uuid: uuid)
    }
    
    private func handleUpdateSelectedSetMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        let text = message[PayloadKey.Arg.text] as? String // nil is allowed
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("update selected set with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.updateWorkoutSessionSelectedSetText(text: text, uuid: uuid)
    }
    
    private func handleDiscardWorkoutSessionMessage(message: [String : Any]) {
        // this message is only valid if the current workoutSession was started with the same UUID
        
        guard let uuidString = message[PayloadKey.Arg.uuid] as? String, let uuid = UUID(uuidString: uuidString) else {
            assertionFailure("discard workout with no uuid parameter")
            return
        }
        
        WorkoutSessionManagerStore.shared.discardWorkoutSession(uuid: uuid,
                                                                notifyPhone: false)
    }
    
    private func handleIgnoredPreparedWorkoutSession() {
        WorkoutSessionManagerStore.shared.discardUnstartedWorkoutSession()
    }
}

extension PhoneConnectionManager {
    func handlePrepareWorkoutSession(_ workoutConfiguration: HKWorkoutConfiguration) {
        os_log("Ensuring we have a workout session that keeps the app alive")
        WorkoutSessionManagerStore.shared.ensurePreparedWorkoutSession(configuration: workoutConfiguration) { [weak self] result in
            switch result {
            case .success:
                self?.sendPreparedWorkoutSession()
                self?.scheduleDiscardUnstartedWorkoutSessionSubject.send()
            case .failure(let error):
                os_log("Could not prepare workout session: %@", error.localizedDescription)
            }
        }
    }
}

// MARK: - Sending
extension PhoneConnectionManager {
    /// wrapper to send either via message or transfer, depending on what's available
    private func sendUserInfo(userInfo: [String : Any]) {
        guard isActivated else {
            // Activation is asynchronous. Keep the command bounded in memory
            // and flush it from activationDidComplete instead of recursively
            // scheduling an unbounded retry chain.
            queueUntilActivated(userInfo)
            return
        }
        if isReachable {
            os_log("Messaging userInfo=%@", type: .debug, userInfo)
            session.sendMessage(userInfo, replyHandler: nil) { error in
                os_log("Messaging not possible, falling back to transfering", type: .debug)
                self.session.transferUserInfo(userInfo)
            }
        } else {
            os_log("Transfering userInfo=%@", type: .debug, userInfo)
            session.transferUserInfo(userInfo)
        }
    }
    
    func sendPreparedWorkoutSession() {
        os_log("Sending prepared message")
        sendUserInfo(userInfo: [PayloadKey.preparedWorkoutSession : true])
    }

    /// Sends every local edit through transferUserInfo for durability and also
    /// sends an immediate message when reachable. The phone acknowledges by
    /// event ID; duplicate deliveries are therefore safe for the phone adapter.
    func flushEventOutbox() {
        guard isActivated else { return }
        for event in WatchWorkoutStore.shared.pendingEvents() {
            guard !eventSendInFlight.contains(event.id),
                  let data = WatchWorkoutWire.encode(event) else { continue }

            let payload: [String: Any] = [PayloadKey.workoutEvent: data]
            if !eventTransferSent.contains(event.id) {
                session.transferUserInfo(payload)
                eventTransferSent.insert(event.id)
            }
            guard isReachable else { continue }

            eventSendInFlight.insert(event.id)
            session.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.receive(message: reply)
            }, errorHandler: { [weak self] _ in
                // transferUserInfo above remains queued; allow a later
                // reachability/activation transition to try the fast path.
                self?.eventSendInFlight.remove(event.id)
                self?.eventTransferSent.remove(event.id)
            })
        }
    }
}
