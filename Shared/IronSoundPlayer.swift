import AVFoundation
import UIKit

/// Original, prewarmed UI cues. Player state belongs to the main queue;
/// audio-session configuration runs on a dedicated queue so launch stays responsive.
final class IronSoundPlayer: NSObject, AVAudioPlayerDelegate {
    enum Sound: String, CaseIterable, Identifiable {
        case setComplete = "set_complete"
        case setRecord = "set_record"
        case tick
        case restComplete = "rest_complete"
        case workoutFinish = "workout_finish"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .setComplete: return "Set Complete"
            case .setRecord: return "Personal Record"
            case .tick: return "Controls & Keypad"
            case .restComplete: return "Rest Complete"
            case .workoutFinish: return "Workout Saved"
            }
        }

        fileprivate var volume: Float {
            switch self {
            case .tick: return 0.35
            case .restComplete: return 0.8
            case .setComplete, .setRecord, .workoutFinish: return 0.6
            }
        }
    }

    static let shared = IronSoundPlayer()

    private var players: [Sound: AVAudioPlayer] = [:]
    private let sessionQueue = DispatchQueue(label: "com.joshpatra.Iron.audio-session", qos: .userInitiated)
    private var isPreloading = false
    private var isAppActive = false
    private var lastTickTime: TimeInterval = -.infinity

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(stopPlayback),
                           name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(stopPlayback),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(audioInterrupted(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
    }

    /// Called at app launch, before the first interaction. Extensions never preload.
    func preload() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.preload() }
            return
        }
        guard Bundle.main.bundleURL.pathExtension != "appex", players.isEmpty, !isPreloading else { return }
        // Launch and scene activation can both request prewarming. Configure once
        // before preparing players, without blocking either main-thread callback.
        isPreloading = true
        sessionQueue.async {
            do {
                // Ambient mixes with the user's music and honors Ring/Silent.
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                DispatchQueue.main.async { self.preparePlayers() }
            } catch {
                DispatchQueue.main.async {
                    self.isPreloading = false
                    print("Could not configure Light sounds: \(error.localizedDescription)")
                }
            }
        }
    }

    private func preparePlayers() {
        defer { isPreloading = false }
        do {
            for sound in Sound.allCases {
                guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else {
                    print("Missing Light sound: \(sound.rawValue).caf")
                    continue
                }
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = sound.volume
                player.delegate = self
                player.prepareToPlay()
                players[sound] = player
            }
        } catch {
            print("Could not prepare Light sounds: \(error.localizedDescription)")
        }
    }

    func play(_ sound: Sound, preview: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.play(sound, preview: preview) }
            return
        }
        guard isAppActive, SettingsStore.shared.workoutSounds else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if sound == .tick {
            guard now - lastTickTime >= 0.035 else { return }
            lastTickTime = now
        }
        if preview {
            for player in players.values where player.isPlaying { player.stop() }
        }
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Keep the next tap warm after AVAudioPlayer releases its playback buffers.
        guard isAppActive else { return }
        player.currentTime = 0
        player.prepareToPlay()
    }

    @objc private func didBecomeActive() {
        isAppActive = true
        preload()
        for player in players.values { player.prepareToPlay() }
    }

    @objc private func stopPlayback() {
        isAppActive = false
        for player in players.values { player.stop() }
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        // Audio-session notifications may arrive off the main queue. Do not resume
        // old cues after a call; the next foreground interaction owns playback.
        DispatchQueue.main.async {
            if type == .began {
                for player in self.players.values { player.stop() }
            } else if self.isAppActive {
                for player in self.players.values { player.prepareToPlay() }
            }
        }
    }
}
