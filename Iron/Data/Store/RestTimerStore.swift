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
    static let shared = RestTimerStore(userDefaults: .standard)

    typealias ExpiryCancellation = () -> Void
    typealias ExpiryScheduler = (_ deadline: Date, _ handler: @escaping () -> Void) -> ExpiryCancellation

    let objectWillChange = ObservableObjectPublisher()

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let keepRunning: () -> Bool
    private let notificationUpdater: (_ deadline: Date?, _ totalTime: TimeInterval?) -> Void
    private let watchUpdater: (_ end: Date?) -> Void
    private let expiryScheduler: ExpiryScheduler
    private let expiryAnnouncement: (() -> Void)?
    private let isAppActive: () -> Bool
    private var cancelScheduledExpiry: ExpiryCancellation?
    private var expiryGeneration: UInt = 0

    init(
        userDefaults: UserDefaults,
        now: @escaping () -> Date = Date.init,
        keepRunning: @escaping () -> Bool = { SettingsStore.shared.keepRestTimerRunning },
        notificationUpdater: @escaping (Date?, TimeInterval?) -> Void = { deadline, totalTime in
            NotificationManager.shared.updateRestTimerUpNotificationRequest(
                deadline: deadline,
                totalTime: totalTime,
                playsSound: SettingsStore.shared.workoutSounds
            )
        },
        watchUpdater: @escaping (Date?) -> Void = { end in
            guard let uuid = WatchConnectionManager.shared.currentWatchWorkoutUuid else { return }
            WatchConnectionManager.shared.updateWatchWorkoutRestTimer(
                end: end,
                keepRunning: SettingsStore.shared.keepRestTimerRunning,
                uuid: uuid
            )
        },
        expiryScheduler: @escaping ExpiryScheduler = { deadline, handler in
            let workItem = DispatchWorkItem(block: handler)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + max(deadline.timeIntervalSinceNow, 0),
                execute: workItem
            )
            return { workItem.cancel() }
        },
        expiryAnnouncement: (() -> Void)? = nil,
        isAppActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.keepRunning = keepRunning
        self.notificationUpdater = notificationUpdater
        self.watchUpdater = watchUpdater
        self.expiryScheduler = expiryScheduler
        self.expiryAnnouncement = expiryAnnouncement
        self.isAppActive = isAppActive
        restorePersistedExpiry()
    }

    var restTimerStart: Date? {
        get { userDefaults.restTimerStart }
        set {
            transition(
                start: newValue,
                duration: restTimerDuration,
                pausedRemaining: newValue == nil ? userDefaults.restTimerPausedRemaining : nil
            )
        }
    }

    var restTimerDuration: TimeInterval? {
        get { userDefaults.restTimerDuration }
        set {
            let duration = Self.validDuration(newValue)
            transition(
                start: duration == nil ? nil : restTimerStart,
                duration: duration,
                pausedRemaining: duration == nil ? nil : userDefaults.restTimerPausedRemaining
            )
        }
    }

    var recentRestTimes: [TimeInterval] {
        get { userDefaults.recentRestTimes }
        set {
            objectWillChange.send()
            userDefaults.recentRestTimes = newValue
        }
    }

    var isPaused: Bool { userDefaults.restTimerPausedRemaining != nil }

    func notifyKeepRestTimerRunningChanged() {
        objectWillChange.send()
        updateWatch()
    }

    private static func validDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    /// Persist a complete snapshot before publishing any timer effects.
    private func transition(
        start: Date?,
        duration: TimeInterval?,
        pausedRemaining: TimeInterval?,
        updateWatch shouldUpdateWatch: Bool = true
    ) {
        let duration = Self.validDuration(duration)
        let pausedRemaining = Self.validDuration(pausedRemaining)
        let start = duration == nil || pausedRemaining != nil ? nil : start

        expiryGeneration &+= 1
        cancelScheduledExpiry?()
        cancelScheduledExpiry = nil

        userDefaults.restTimerStart = start
        userDefaults.restTimerDuration = duration
        userDefaults.restTimerPausedRemaining = pausedRemaining
        objectWillChange.send()

        let deadline = start.flatMap { start in
            duration.map { start.addingTimeInterval($0) }
        }
        notificationUpdater(deadline, duration)
        if shouldUpdateWatch { updateWatch() }
        scheduleExpiryAnnouncement(deadline: deadline)
    }

    private func updateWatch() {
        watchUpdater(restTimerEnd)
    }

    private func scheduleExpiryAnnouncement(deadline: Date?) {
        guard let deadline, deadline.timeIntervalSince(now()) > 0.05 else { return }
        let generation = expiryGeneration
        cancelScheduledExpiry = expiryScheduler(deadline) { [weak self] in
            guard let self, self.expiryGeneration == generation else { return }
            self.cancelScheduledExpiry = nil
            self.announceExpiry()
        }
    }

    private func restorePersistedExpiry() {
        guard userDefaults.restTimerPausedRemaining == nil else { return }
        scheduleExpiryAnnouncement(deadline: restTimerEnd)
    }

    private func announceExpiry() {
        if let expiryAnnouncement {
            expiryAnnouncement()
        } else if isAppActive() {
            if SettingsStore.shared.workoutHaptics {
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                feedback.notificationOccurred(.warning)
            }
            if SettingsStore.shared.workoutSounds {
                IronSoundPlayer.shared.play(.restComplete)
            }
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
        if let paused = userDefaults.restTimerPausedRemaining { return paused }
        guard let restTimerEnd else { return nil }
        let remainingTime = restTimerEnd.timeIntervalSince(now())
        guard remainingTime >= 0 || keepRunning() else { return nil }
        return max(remainingTime, 0)
    }
}

extension RestTimerStore {
    func start(duration: TimeInterval) {
        guard let duration = Self.validDuration(duration) else {
            cancel()
            return
        }
        transition(start: now(), duration: duration, pausedRemaining: nil)
    }

    func setRemaining(_ remaining: TimeInterval) {
        guard let remaining = Self.validDuration(remaining) else {
            cancel()
            return
        }
        if isPaused {
            transition(start: nil, duration: remaining, pausedRemaining: remaining)
        } else {
            transition(start: now(), duration: remaining, pausedRemaining: nil)
        }
    }

    func pause() {
        guard !isPaused, let remaining = restTimerRemainingTime, remaining > 0 else { return }
        transition(start: nil, duration: restTimerDuration, pausedRemaining: remaining)
    }

    func resume() {
        guard let remaining = userDefaults.restTimerPausedRemaining else { return }
        let total = max(restTimerDuration ?? remaining, remaining)
        let resumedAt = now().addingTimeInterval(-(total - remaining))
        transition(start: resumedAt, duration: total, pausedRemaining: nil)
    }

    func adjust(by interval: TimeInterval) {
        guard interval.isFinite else { return }
        IronSoundPlayer.shared.play(.tick)

        if let paused = userDefaults.restTimerPausedRemaining {
            let adjusted = paused + interval
            guard adjusted.isFinite, adjusted > 0 else {
                cancel()
                announceExpiry()
                return
            }
            let total = max((restTimerDuration ?? paused) + interval, adjusted)
            transition(start: nil, duration: total, pausedRemaining: adjusted)
            return
        }

        guard let end = restTimerEnd else { return }

        let currentTime = now()
        if end <= currentTime {
            guard interval > 0 else {
                cancel()
                announceExpiry()
                return
            }
            transition(start: currentTime, duration: interval, pausedRemaining: nil)
            return
        }

        guard let duration = restTimerDuration,
              let adjustedDuration = Self.validDuration(duration + interval),
              end.addingTimeInterval(interval) > currentTime else {
            cancel()
            announceExpiry()
            return
        }
        transition(start: restTimerStart, duration: adjustedDuration, pausedRemaining: nil)
    }

    func applyWatchUpdate(end: Date?, pausedRemaining: TimeInterval? = nil) {
        if let pausedRemaining, let remaining = Self.validDuration(pausedRemaining) {
            transition(start: nil, duration: max(restTimerDuration ?? remaining, remaining),
                       pausedRemaining: remaining, updateWatch: false)
            return
        }
        guard let end else {
            transition(start: nil, duration: nil, pausedRemaining: nil, updateWatch: false)
            return
        }
        let duration = end.timeIntervalSince(now())
        guard let duration = Self.validDuration(duration) else {
            transition(start: nil, duration: nil, pausedRemaining: nil, updateWatch: false)
            return
        }
        transition(
            start: end.addingTimeInterval(-duration),
            duration: duration,
            pausedRemaining: nil,
            updateWatch: false
        )
    }

    func cancel() {
        transition(start: nil, duration: nil, pausedRemaining: nil)
    }
}
