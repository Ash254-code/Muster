import Foundation
import AVFoundation

@MainActor
final class RadioAudioDucker {

    static let shared = RadioAudioDucker()

    private var releaseTimer: Timer?
    private var isDucking = false

    func radioActivityDetected() {
        beginDuck()
        restartReleaseTimer()
    }

    func endDuckImmediately() {
        releaseTimer?.invalidate()
        releaseTimer = nil

        guard isDucking else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Audio session release failed: \(error)")
        }

        isDucking = false
    }

    private func beginDuck() {
        guard !isDucking else { return }

        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )

            try session.setActive(true)

            isDucking = true
        } catch {
            print("Audio duck start failed: \(error)")
        }
    }

    private func restartReleaseTimer() {
        releaseTimer?.invalidate()

        releaseTimer = Timer.scheduledTimer(
            withTimeInterval: 10,
            repeats: false
        ) { _ in
            Task { @MainActor in
                RadioAudioDucker.shared.endDuckImmediately()
            }
        }
    }
}
