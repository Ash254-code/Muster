import Foundation
import Combine
import AVFoundation

@MainActor
final class AppState: ObservableObject {
    @Published var muster = MusterStore() {
        didSet {
            bindMuster()
        }
    }

    @Published var xrs = XRSRadioStore() {
        didSet {
            bindXRS()
            bindRadio()
        }
    }

    private let ble = BLERadioDebugger.shared
    private let radioDuckHoldSeconds: TimeInterval = 10

    private var didBootstrap = false
    private var cancellables: Set<AnyCancellable> = []
    private var xrsCancellables: Set<AnyCancellable> = []
    private var radioMaintenanceCancellable: AnyCancellable?
    private var radioDuckReleaseCancellable: AnyCancellable?
    private var isRadioAudioDuckActive = false
    private var radioDuckPlayer: AVAudioPlayer?

    init() {
        bindMuster()
        bindXRS()
        bindRadio()
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        muster.load()
        xrs.load()

        bindRadio()
        ble.reconnectLastKnownPeripheralIfPossible()
        startRadioMaintenanceLoop()
    }

    func noteRadioTransmissionActivity() {
        noteRadioActivity()
    }

    func endRadioAudioDuckIfNeeded() {
        radioDuckReleaseCancellable?.cancel()
        radioDuckReleaseCancellable = nil

        guard isRadioAudioDuckActive else { return }

        radioDuckPlayer?.stop()
        radioDuckPlayer?.currentTime = 0

        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            print("Failed to end radio audio duck: \(error.localizedDescription)")
        }

        isRadioAudioDuckActive = false
    }

    private func bindMuster() {
        cancellables.removeAll()

        muster.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        muster.$sessions
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$markerTemplates
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$mapMarkers
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$importedMapFiles
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$activeSessionID
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$activeSheepTargetMarkerID
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)

        muster.$showPreviousTracksOnMap
            .dropFirst()
            .sink { [weak self] _ in
                self?.muster.save()
            }
            .store(in: &cancellables)
    }

    private func bindXRS() {
        xrsCancellables.removeAll()

        xrs.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &xrsCancellables)

        xrs.$contacts
            .dropFirst()
            .sink { [weak self] _ in
                self?.xrs.save()
            }
            .store(in: &xrsCancellables)
    }

    private func bindRadio() {
        ble.onReceiveActivity = { [weak self] in
            self?.noteRadioActivity()
        }

        ble.onDecodedContact = { [weak self] contact in
            guard let self else { return }

            self.xrs.updateContact(
                name: contact.name,
                status: contact.status,
                latitude: contact.lat,
                longitude: contact.lon
            )
        }

        ble.onTransmitActivity = { [weak self] in
            self?.noteRadioTransmissionActivity()
        }

        ble.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            self.xrs.setConnected(connected)
        }
    }

    private func startRadioMaintenanceLoop() {
        radioMaintenanceCancellable?.cancel()

        radioMaintenanceCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                self.xrs.removeStaleContacts()

                if !self.ble.isConnected {
                    self.ble.reconnectLastKnownPeripheralIfPossible()
                }
            }
    }

    private func noteRadioActivity() {
        beginRadioAudioDuckIfNeeded()
        scheduleRadioDuckRelease()
    }

    private func beginRadioAudioDuckIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )

            try session.setActive(true)

            try ensureRadioDuckPlayer()
            if radioDuckPlayer?.isPlaying != true {
                radioDuckPlayer?.play()
            }

            isRadioAudioDuckActive = true
        } catch {
            print("Failed to begin radio audio duck: \(error.localizedDescription)")
        }
    }

    private func scheduleRadioDuckRelease() {
        radioDuckReleaseCancellable?.cancel()

        radioDuckReleaseCancellable = Just(())
            .delay(for: .seconds(radioDuckHoldSeconds), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.endRadioAudioDuckIfNeeded()
            }
    }

    private func ensureRadioDuckPlayer() throws {
        if radioDuckPlayer != nil { return }

        let data = makeNearSilentWAVData(duration: 1.0, sampleRate: 44_100, frequency: 440.0)
        let player = try AVAudioPlayer(data: data)
        player.numberOfLoops = -1
        player.volume = 1.0
        player.prepareToPlay()
        radioDuckPlayer = player
    }

    private func makeNearSilentWAVData(
        duration: TimeInterval,
        sampleRate: Int,
        frequency: Double
    ) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let frameCount = max(1, Int(Double(sampleRate) * duration))
        let byteRate = UInt32(sampleRate * Int(channelCount) * bytesPerSample)
        let blockAlign = UInt16(Int(channelCount) * bytesPerSample)
        let dataSize = frameCount * Int(channelCount) * bytesPerSample
        let riffChunkSize = 36 + dataSize

        var data = Data()

        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(riffChunkSize).littleEndian, Array.init))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: channelCount.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian, Array.init))

        let amplitude = 1.0
        let twoPi = Double.pi * 2.0

        for i in 0..<frameCount {
            let t = Double(i) / Double(sampleRate)
            let sample = sin(twoPi * frequency * t) * amplitude
            let intSample = Int16(max(Double(Int16.min), min(Double(Int16.max), sample))).littleEndian
            data.append(contentsOf: withUnsafeBytes(of: intSample, Array.init))
        }

        return data
    }
}
