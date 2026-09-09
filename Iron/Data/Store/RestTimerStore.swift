//
//  RestTimerStore.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 12.08.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import Combine
import UIKit
import AudioToolbox

// to be used in other places
let restTimerDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.minute, .second]
    formatter.zeroFormattingBehavior = .pad
    return formatter
}()

let restTimerCustomTimes: [TimeInterval] = {
    stride(from: 30 as TimeInterval, through: 10*60, by: 5).map { $0 }
}()

final class RestTimerStore: ObservableObject {
    static let shared = RestTimerStore() // singleton

    let objectWillChange = ObservableObjectPublisher()
    
    private var userDefaults: UserDefaults
    private var isApplyingWatchUpdate = false
    private var expiryWorkItem: DispatchWorkItem?
    
    private init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }
    
    private convenience init() {
        self.init(userDefaults: UserDefaults.standard)
    }
    
    var restTimerStart: Date? {
        get {
            userDefaults.restTimerStart
        }
        set {
            self.objectWillChange.send()
            userDefaults.restTimerStart = newValue
            updateNotification()
            updateWatch()
            scheduleExpiryAnnouncement()
        }
    }
    
    var restTimerDuration: TimeInterval? {
        get {
            userDefaults.restTimerDuration
        }
        set {
            self.objectWillChange.send()
            userDefaults.restTimerDuration = newValue
            updateNotification()
            updateWatch()
            scheduleExpiryAnnouncement()
        }
    }
    
    var recentRestTimes: [TimeInterval] {
        get {
            userDefaults.recentRestTimes
        }
        set {
            self.objectWillChange.send()
            userDefaults.recentRestTimes = newValue
        }
    }

    /// True when the rest countdown is intentionally frozen by the user.
    var isPaused: Bool {
        userDefaults.restTimerPausedRemaining != nil
    }
    
    func notifyKeepRestTimerRunningChanged() { // TODO in future somehow subscribe to SettingsStore.shared.keepRestTimerRunning changes
        self.objectWillChange.send()
        updateWatch()
    }
    
    private func updateNotification() {
        NotificationManager.shared.updateRestTimerUpNotificationRequest(remainingTime: self.restTimerRemainingTime, totalTime: self.restTimerDuration)
    }
    
    private func updateWatch() {
        guard !isApplyingWatchUpdate else { return }
        if let uuid = WatchConnectionManager.shared.currentWatchWorkoutUuid {
            WatchConnectionManager.shared.updateWatchWorkoutRestTimer(end: restTimerEnd, keepRunning: SettingsStore.shared.keepRestTimerRunning, uuid: uuid)
        }
    }

    /// Local chime when rest ends, even if the app is open and a notification
    /// would be silent or cancelled by overtime.
    private func scheduleExpiryAnnouncement() {
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        guard let remaining = restTimerRemainingTime, remaining > 0.05 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.announceExpiry()
        }
        expiryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func announceExpiry() {
        // The work item is cancelled on skip/adjust, so reaching here means
        // rest actually ended. Do not re-check remaining — overtime and the
        // keep-running preference both make remaining nil or negative.
        if SettingsStore.shared.workoutHaptics {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.warning)
        }
        if SettingsStore.shared.workoutSounds {
            AudioServicesPlayAlertSound(1005)
        }
        objectWillChange.send()
    }
}

extension RestTimerStore {
    var restTimerEnd: Date? {
        guard let duration = restTimerDuration else { return nil }
        return restTimerStart?.addingTimeInterval(duration)
    }
    
    var restTimerRemainingTime: TimeInterval? {
        if let paused = userDefaults.restTimerPausedRemaining {
            return paused
        }
        guard let restTimerEnd = restTimerEnd else { return nil }
        let remainingTime = restTimerEnd.timeIntervalSince(Date())
        guard remainingTime >= 0 || SettingsStore.shared.keepRestTimerRunning else { return nil }
        return max(remainingTime, 0)
    }
}

extension RestTimerStore {
    /// Starts a fresh countdown and clears any paused snapshot.
    func start(duration: TimeInterval) {
        userDefaults.restTimerPausedRemaining = nil
        restTimerStart = Date()
        restTimerDuration = max(duration, 1)
    }

    /// Sets the remaining duration directly from the radial dial. A running
    /// timer restarts from the selected value; a paused timer stays paused.
    func setRemaining(_ remaining: TimeInterval) {
        let adjusted = max(remaining, 1)
        expiryWorkItem?.cancel()

        if isPaused {
            userDefaults.restTimerPausedRemaining = adjusted
            userDefaults.restTimerStart = nil
        } else {
            userDefaults.restTimerPausedRemaining = nil
            userDefaults.restTimerStart = Date()
        }
        userDefaults.restTimerDuration = adjusted

        objectWillChange.send()
        updateNotification()
        updateWatch()
        scheduleExpiryAnnouncement()
    }

    /// Freezes the countdown at its current value without discarding the
    /// configured duration, so the dial can resume at the same notch.
    func pause() {
        guard !isPaused, let remaining = restTimerRemainingTime, remaining > 0 else { return }
        userDefaults.restTimerPausedRemaining = remaining
        restTimerStart = nil
        objectWillChange.send()
        updateNotification()
        updateWatch()
    }

    /// Resumes a paused countdown from its captured remaining value.
    func resume() {
        guard let remaining = userDefaults.restTimerPausedRemaining else { return }
        userDefaults.restTimerPausedRemaining = nil
        restTimerStart = Date()
        restTimerDuration = max(restTimerDuration ?? remaining, remaining)
    }

    func adjust(by interval: TimeInterval) {
        if let paused = userDefaults.restTimerPausedRemaining {
            let adjusted = paused + interval
            guard adjusted > 0 else {
                announceExpiry()
                cancel()
                return
            }
            userDefaults.restTimerPausedRemaining = adjusted
            objectWillChange.send()
            updateNotification()
            updateWatch()
            return
        }
        guard let start = restTimerStart, let end = restTimerEnd else { return }
        let adjustedEnd = end.addingTimeInterval(interval)
        guard adjustedEnd > Date() else {
            announceExpiry()
            cancel()
            return
        }
        restTimerDuration = max(adjustedEnd.timeIntervalSince(start), 1)
    }

    /// Applies a timer created on Apple Watch without echoing the same change
    /// back across WatchConnectivity.
    func applyWatchUpdate(end: Date?) {
        isApplyingWatchUpdate = true
        defer { isApplyingWatchUpdate = false }
        guard let end = end else {
            userDefaults.restTimerPausedRemaining = nil
            restTimerStart = nil
            restTimerDuration = nil
            return
        }
        userDefaults.restTimerPausedRemaining = nil
        let now = Date()
        let duration = max(end.timeIntervalSince(now), 1)
        restTimerStart = end.addingTimeInterval(-duration)
        restTimerDuration = duration
    }

    func cancel() {
        expiryWorkItem?.cancel()
        expiryWorkItem = nil
        userDefaults.restTimerPausedRemaining = nil
        restTimerStart = nil
        restTimerDuration = nil
    }
}
