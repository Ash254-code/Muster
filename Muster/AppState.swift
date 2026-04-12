import Foundation
import Combine
import AVFoundation
import CoreLocation

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
    @Published var cellularTracking = CellularGroupTrackingStore() {
        didSet {
            bindCellularTracking()
        }
    }
    @Published var pendingQuickAction: HomeScreenQuickAction? = nil

    private let ble = BLERadioDebugger.shared
    private let radioDuckHoldSeconds: TimeInterval = 10

    private var didBootstrap = false
    private var cancellables: Set<AnyCancellable> = []
    private var xrsCancellables: Set<AnyCancellable> = []
    private var cellularCancellables: Set<AnyCancellable> = []
    private var radioMaintenanceCancellable: AnyCancellable?
    private var radioDuckReleaseCancellable: AnyCancellable?
    private var isRadioAudioDuckActive = false
    private var radioDuckPlayer: AVAudioPlayer?

    init() {
        bindMuster()
        bindXRS()
        bindCellularTracking()
        bindRadio()
    }

    func queueQuickAction(_ action: HomeScreenQuickAction) {
        pendingQuickAction = action
    }

    func clearPendingQuickAction() {
        pendingQuickAction = nil
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        muster.load()
        xrs.load()
        cellularTracking.load()

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

        muster.$mapSets
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

    private func bindCellularTracking() {
        cellularCancellables.removeAll()

        cellularTracking.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cellularCancellables)

        cellularTracking.$members
            .dropFirst()
            .sink { [weak self] _ in
                self?.cellularTracking.save()
            }
            .store(in: &cellularCancellables)
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
            self.cellularTracking.updateRadioFallbackLocation(
                for: contact.name,
                latitude: contact.lat,
                longitude: contact.lon,
                at: contact.updatedAt
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

struct CellularTrackingMember: Identifiable, Codable, Hashable {
    enum InvitationStatus: String, Codable {
        case pending
        case accepted
        case rejected
        case expired
    }

    var id: UUID
    var name: String
    var phoneNumber: String
    var isSharing: Bool
    var invitationStatus: InvitationStatus
    var sharingEndsAt: Date?
    var lastCellularLatitude: Double?
    var lastCellularLongitude: Double?
    var lastCellularUpdate: Date?
    var lastRadioLatitude: Double?
    var lastRadioLongitude: Double?
    var lastRadioUpdate: Date?

    enum Status {
        case live
        case offline
        case expired
        case pending
        case rejected
    }

    var lastCellularCoordinate: CLLocationCoordinate2D? {
        guard let lastCellularLatitude, let lastCellularLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lastCellularLatitude, longitude: lastCellularLongitude)
    }

    var lastRadioCoordinate: CLLocationCoordinate2D? {
        guard let lastRadioLatitude, let lastRadioLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lastRadioLatitude, longitude: lastRadioLongitude)
    }

    var status: Status {
        if invitationStatus == .pending { return .pending }
        if invitationStatus == .rejected { return .rejected }
        guard isSharing else { return .expired }
        if let sharingEndsAt, sharingEndsAt <= Date() { return .expired }
        guard let lastCellularUpdate else {
            return lastRadioUpdate == nil ? .offline : .expired
        }
        let age = Date().timeIntervalSince(lastCellularUpdate)
        if age <= 120 { return .live }
        if age <= 600 { return .offline }
        return .expired
    }

    init(
        id: UUID,
        name: String,
        phoneNumber: String,
        isSharing: Bool,
        invitationStatus: InvitationStatus,
        sharingEndsAt: Date? = nil,
        lastCellularLatitude: Double?,
        lastCellularLongitude: Double?,
        lastCellularUpdate: Date?,
        lastRadioLatitude: Double?,
        lastRadioLongitude: Double?,
        lastRadioUpdate: Date?
    ) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.isSharing = isSharing
        self.invitationStatus = invitationStatus
        self.sharingEndsAt = sharingEndsAt
        self.lastCellularLatitude = lastCellularLatitude
        self.lastCellularLongitude = lastCellularLongitude
        self.lastCellularUpdate = lastCellularUpdate
        self.lastRadioLatitude = lastRadioLatitude
        self.lastRadioLongitude = lastRadioLongitude
        self.lastRadioUpdate = lastRadioUpdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        isSharing = try container.decode(Bool.self, forKey: .isSharing)
        invitationStatus = try container.decodeIfPresent(InvitationStatus.self, forKey: .invitationStatus) ?? .accepted
        sharingEndsAt = try container.decodeIfPresent(Date.self, forKey: .sharingEndsAt)
        lastCellularLatitude = try container.decodeIfPresent(Double.self, forKey: .lastCellularLatitude)
        lastCellularLongitude = try container.decodeIfPresent(Double.self, forKey: .lastCellularLongitude)
        lastCellularUpdate = try container.decodeIfPresent(Date.self, forKey: .lastCellularUpdate)
        lastRadioLatitude = try container.decodeIfPresent(Double.self, forKey: .lastRadioLatitude)
        lastRadioLongitude = try container.decodeIfPresent(Double.self, forKey: .lastRadioLongitude)
        lastRadioUpdate = try container.decodeIfPresent(Date.self, forKey: .lastRadioUpdate)
    }
}

@MainActor
final class CellularGroupTrackingStore: ObservableObject {
    @Published private(set) var members: [CellularTrackingMember] = []

    private let defaultsKey = "cellular_group_tracking_members_v1"

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([CellularTrackingMember].self, from: data) else { return }
        members = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(members) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    func sendInvitation(name: String, phoneNumber: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPhone.isEmpty else { return }

        if let index = members.firstIndex(where: { normalizedPhone($0.phoneNumber) == normalizedPhone(trimmedPhone) }) {
            members[index].name = trimmedName
            members[index].phoneNumber = trimmedPhone
            members[index].isSharing = false
            members[index].invitationStatus = .pending
            members[index].sharingEndsAt = nil
            return
        }

        members.append(
            CellularTrackingMember(
                id: UUID(),
                name: trimmedName,
                phoneNumber: trimmedPhone,
                isSharing: false,
                invitationStatus: .pending,
                sharingEndsAt: nil,
                lastCellularLatitude: nil,
                lastCellularLongitude: nil,
                lastCellularUpdate: nil,
                lastRadioLatitude: nil,
                lastRadioLongitude: nil,
                lastRadioUpdate: nil
            )
        )
    }

    func updateCellularLocation(for phoneNumber: String, latitude: Double, longitude: Double, at date: Date = Date()) {
        guard let index = members.firstIndex(where: { normalizedPhone($0.phoneNumber) == normalizedPhone(phoneNumber) }) else { return }
        members[index].lastCellularLatitude = latitude
        members[index].lastCellularLongitude = longitude
        members[index].lastCellularUpdate = date
        members[index].isSharing = true
        if members[index].invitationStatus == .pending {
            members[index].invitationStatus = .accepted
        }
    }

    func updateRadioFallbackLocation(for name: String, latitude: Double, longitude: Double, at date: Date = Date()) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let index = members.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            return
        }

        members[index].lastRadioLatitude = latitude
        members[index].lastRadioLongitude = longitude
        members[index].lastRadioUpdate = date
    }

    func setSharing(_ isSharing: Bool, for memberID: UUID) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        members[index].isSharing = isSharing
        if !isSharing {
            members[index].invitationStatus = .expired
        }
    }

    func respondToInvitation(for memberID: UUID, accepted: Bool, duration: TimeInterval?) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        members[index].invitationStatus = accepted ? .accepted : .rejected
        members[index].isSharing = accepted
        members[index].sharingEndsAt = accepted ? duration.map { Date().addingTimeInterval($0) } : nil
    }

    func expireSharesIfNeeded(now: Date = Date()) {
        for index in members.indices {
            guard members[index].isSharing, let sharingEndsAt = members[index].sharingEndsAt else { continue }
            if sharingEndsAt <= now {
                members[index].isSharing = false
                members[index].invitationStatus = .expired
            }
        }
    }

    func mappedContactsWithRadioFallback(_ radioContacts: [XRSRadioContact]) -> [XRSRadioContact] {
        var mapped: [XRSRadioContact] = []

        for member in members where member.isSharing {
            let cellularAge = member.lastCellularUpdate.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            if cellularAge <= 600, let coordinate = member.lastCellularCoordinate, let updatedAt = member.lastCellularUpdate {
                mapped.append(
                    XRSRadioContact(
                        id: member.id,
                        name: member.name,
                        status: "Cellular",
                        lat: coordinate.latitude,
                        lon: coordinate.longitude,
                        updatedAt: updatedAt,
                        rawMessage: "CELLULAR"
                    )
                )
                continue
            }

            if let radioMatch = radioContacts.first(where: { $0.name.caseInsensitiveCompare(member.name) == .orderedSame }) {
                mapped.append(radioMatch)
            } else if let radioCoordinate = member.lastRadioCoordinate, let radioDate = member.lastRadioUpdate {
                mapped.append(
                    XRSRadioContact(
                        id: member.id,
                        name: member.name,
                        status: "Radio fallback",
                        lat: radioCoordinate.latitude,
                        lon: radioCoordinate.longitude,
                        updatedAt: radioDate,
                        rawMessage: "RADIO_FALLBACK"
                    )
                )
            }
        }

        let managedNames = Set(mapped.map { normalizedName($0.name) })
        let unmanagedRadio = radioContacts.filter { !managedNames.contains(normalizedName($0.name)) }
        return (mapped + unmanagedRadio).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func normalizedPhone(_ value: String) -> String {
        value.filter { $0.isNumber }
    }

    private func normalizedName(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
