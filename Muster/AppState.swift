import Foundation
import Combine
import AVFoundation
import CoreLocation
import UIKit

let kHapticsEnabledKey = "haptics_enabled"
let kHapticsStrengthKey = "haptics_strength"

enum AppHaptics {
    private static let defaults = UserDefaults.standard

    static var isEnabled: Bool {
        defaults.object(forKey: kHapticsEnabledKey) as? Bool ?? true
    }

    static var strength: CGFloat {
        let stored = defaults.object(forKey: kHapticsStrengthKey) as? Double ?? 1.0
        return CGFloat(min(max(stored, 0.1), 1.0))
    }

    static func longPressStrong() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred(intensity: strength)
    }
}

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

enum TrackingTransport: String, Codable {
    case cellular
    case xrs
    case stale
    case unavailable
}

struct GroupTrackingInvite: Identifiable, Codable, Hashable {
    var id: String
    var inviterName: String
    var groupName: String
    var token: String
    var joinURL: URL
    var expiresAt: Date
    var phoneNumber: String
    var inviteeName: String
    var status: String
}

struct CellularShareSession: Identifiable, Codable, Hashable {
    var id: String
    var groupID: String
    var participantID: String
    var startedAt: Date
    var endsAt: Date?
    var isActive: Bool
}

struct CellularLocationPing: Codable, Hashable {
    var participantID: String
    var sessionID: String
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var speed: Double?
    var course: Double?
    var horizontalAccuracy: Double
    var batteryLevel: Float?
}

struct ParticipantPresence: Identifiable, Codable, Hashable {
    var id: String { participantID }
    var participantID: String
    var displayName: String
    var cellularLocation: CLLocationCoordinate2D?
    var cellularTimestamp: Date?
    var xrsLocation: CLLocationCoordinate2D?
    var xrsTimestamp: Date?
    var effectiveLocation: CLLocationCoordinate2D?
    var effectiveTransport: TrackingTransport
    var isStale: Bool
    var shareEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case participantID, displayName, cellularTimestamp, xrsTimestamp, effectiveTransport, isStale, shareEndsAt
        case cellularLatitude, cellularLongitude, xrsLatitude, xrsLongitude, effectiveLatitude, effectiveLongitude
    }

    init(
        participantID: String,
        displayName: String,
        cellularLocation: CLLocationCoordinate2D?,
        cellularTimestamp: Date?,
        xrsLocation: CLLocationCoordinate2D?,
        xrsTimestamp: Date?,
        effectiveLocation: CLLocationCoordinate2D?,
        effectiveTransport: TrackingTransport,
        isStale: Bool,
        shareEndsAt: Date?
    ) {
        self.participantID = participantID
        self.displayName = displayName
        self.cellularLocation = cellularLocation
        self.cellularTimestamp = cellularTimestamp
        self.xrsLocation = xrsLocation
        self.xrsTimestamp = xrsTimestamp
        self.effectiveLocation = effectiveLocation
        self.effectiveTransport = effectiveTransport
        self.isStale = isStale
        self.shareEndsAt = shareEndsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        participantID = try c.decode(String.self, forKey: .participantID)
        displayName = try c.decode(String.self, forKey: .displayName)
        cellularTimestamp = try c.decodeIfPresent(Date.self, forKey: .cellularTimestamp)
        xrsTimestamp = try c.decodeIfPresent(Date.self, forKey: .xrsTimestamp)
        effectiveTransport = try c.decode(TrackingTransport.self, forKey: .effectiveTransport)
        isStale = try c.decode(Bool.self, forKey: .isStale)
        shareEndsAt = try c.decodeIfPresent(Date.self, forKey: .shareEndsAt)

        if let lat = try c.decodeIfPresent(Double.self, forKey: .cellularLatitude),
           let lon = try c.decodeIfPresent(Double.self, forKey: .cellularLongitude) {
            cellularLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            cellularLocation = nil
        }
        if let lat = try c.decodeIfPresent(Double.self, forKey: .xrsLatitude),
           let lon = try c.decodeIfPresent(Double.self, forKey: .xrsLongitude) {
            xrsLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            xrsLocation = nil
        }
        if let lat = try c.decodeIfPresent(Double.self, forKey: .effectiveLatitude),
           let lon = try c.decodeIfPresent(Double.self, forKey: .effectiveLongitude) {
            effectiveLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            effectiveLocation = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(participantID, forKey: .participantID)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(cellularTimestamp, forKey: .cellularTimestamp)
        try c.encodeIfPresent(xrsTimestamp, forKey: .xrsTimestamp)
        try c.encode(effectiveTransport, forKey: .effectiveTransport)
        try c.encode(isStale, forKey: .isStale)
        try c.encodeIfPresent(shareEndsAt, forKey: .shareEndsAt)
        try c.encodeIfPresent(cellularLocation?.latitude, forKey: .cellularLatitude)
        try c.encodeIfPresent(cellularLocation?.longitude, forKey: .cellularLongitude)
        try c.encodeIfPresent(xrsLocation?.latitude, forKey: .xrsLatitude)
        try c.encodeIfPresent(xrsLocation?.longitude, forKey: .xrsLongitude)
        try c.encodeIfPresent(effectiveLocation?.latitude, forKey: .effectiveLatitude)
        try c.encodeIfPresent(effectiveLocation?.longitude, forKey: .effectiveLongitude)
    }

    static func == (lhs: ParticipantPresence, rhs: ParticipantPresence) -> Bool {
        lhs.participantID == rhs.participantID &&
        lhs.displayName == rhs.displayName &&
        lhs.cellularTimestamp == rhs.cellularTimestamp &&
        lhs.xrsTimestamp == rhs.xrsTimestamp &&
        lhs.effectiveTransport == rhs.effectiveTransport &&
        lhs.isStale == rhs.isStale &&
        lhs.shareEndsAt == rhs.shareEndsAt &&
        lhs.cellularLocation?.latitude == rhs.cellularLocation?.latitude &&
        lhs.cellularLocation?.longitude == rhs.cellularLocation?.longitude &&
        lhs.xrsLocation?.latitude == rhs.xrsLocation?.latitude &&
        lhs.xrsLocation?.longitude == rhs.xrsLocation?.longitude &&
        lhs.effectiveLocation?.latitude == rhs.effectiveLocation?.latitude &&
        lhs.effectiveLocation?.longitude == rhs.effectiveLocation?.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(participantID)
        hasher.combine(displayName)
        hasher.combine(cellularTimestamp)
        hasher.combine(xrsTimestamp)
        hasher.combine(effectiveTransport)
        hasher.combine(isStale)
        hasher.combine(shareEndsAt)
        hasher.combine(cellularLocation?.latitude)
        hasher.combine(cellularLocation?.longitude)
        hasher.combine(xrsLocation?.latitude)
        hasher.combine(xrsLocation?.longitude)
        hasher.combine(effectiveLocation?.latitude)
        hasher.combine(effectiveLocation?.longitude)
    }
}

struct CellularTrackingMember: Identifiable, Codable, Hashable {
    var id: UUID
    var participantID: String
    var name: String
    var phoneNumber: String
    var presence: ParticipantPresence
    var activeSession: CellularShareSession?
    var pendingInvite: GroupTrackingInvite?
}

@MainActor
final class CellularGroupTrackingStore: ObservableObject {
    @Published private(set) var members: [CellularTrackingMember] = []
    @Published private(set) var pendingInvites: [GroupTrackingInvite] = []
    @Published private(set) var activeSessions: [CellularShareSession] = []
    @Published var enableCellularTracking: Bool = false
    @Published var useCellularWhenAvailable: Bool = true
    @Published var fallbackToXRS: Bool = true
    @Published private(set) var inboundInvite: GroupTrackingInvite?
    @Published private(set) var inboundInviteValidationError: String?

    private let defaultsKey = "cellular_group_tracking_members_v1"
    private let invitesKey = "cellular_group_tracking_invites_v1"
    private let sessionsKey = "cellular_group_tracking_sessions_v1"
    private let backend = CellularTrackingAPI()
    private let resolver = EffectiveTransportResolver()
    private var uploadQueue: [CellularLocationPing] = []
    private var lastUploadFailure: Date?
    private var lastUploadAt: Date?

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([CellularTrackingMember].self, from: data) {
            members = decoded
        }
        if let inviteData = UserDefaults.standard.data(forKey: invitesKey),
           let decodedInvites = try? JSONDecoder().decode([GroupTrackingInvite].self, from: inviteData) {
            pendingInvites = decodedInvites
        }
        if let sessionData = UserDefaults.standard.data(forKey: sessionsKey),
           let decodedSessions = try? JSONDecoder().decode([CellularShareSession].self, from: sessionData) {
            activeSessions = decodedSessions
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(members) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(pendingInvites), forKey: invitesKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(activeSessions), forKey: sessionsKey)
    }

    func createInvite(name: String, phoneNumber: String) async -> GroupTrackingInvite? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPhone.isEmpty else { return nil }

        do {
            let invite = try await backend.createInvite(name: trimmedName, phoneNumber: trimmedPhone)
            pendingInvites.removeAll { $0.id == invite.id }
            pendingInvites.append(invite)
            upsertMemberFromInvite(invite)
            save()
            return invite
        } catch {
            print("Invite creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    func updateCellularLocation(for phoneNumber: String, latitude: Double, longitude: Double, at date: Date = Date(), xrsFallback: XRSRadioContact? = nil) {
        guard let index = members.firstIndex(where: { normalizedPhone($0.phoneNumber) == normalizedPhone(phoneNumber) }) else { return }
        members[index].presence.cellularLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        members[index].presence.cellularTimestamp = date
        if let xrsFallback {
            members[index].presence.xrsLocation = CLLocationCoordinate2D(latitude: xrsFallback.lat, longitude: xrsFallback.lon)
            members[index].presence.xrsTimestamp = xrsFallback.updatedAt
        }
        // Resolver layer: prefer cellular when fresh, otherwise read existing XRS freshness.
        members[index].presence = resolver.resolve(for: members[index].presence)
    }

    func updateRadioFallbackLocation(for name: String, latitude: Double, longitude: Double, at date: Date = Date()) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard let index = members.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            return
        }

        members[index].presence.xrsLocation = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        members[index].presence.xrsTimestamp = date
        members[index].presence = resolver.resolve(for: members[index].presence)
    }

    func stopShareSession(_ sessionID: String) async {
        do {
            try await backend.stopSession(sessionID: sessionID)
        } catch {
            print("Failed to stop backend session \(sessionID): \(error.localizedDescription)")
        }
        activeSessions.removeAll { $0.id == sessionID }
        for index in members.indices where members[index].activeSession?.id == sessionID {
            members[index].activeSession?.isActive = false
            members[index].presence.shareEndsAt = Date()
        }
        save()
    }

    func acceptInvite(token: String, participantName: String, duration: TimeInterval?) async -> CellularShareSession? {
        do {
            _ = try await backend.acceptInvite(token: token, participantName: participantName)
            let session = try await backend.startSession(token: token, duration: duration)
            activeSessions.removeAll { $0.id == session.id }
            activeSessions.append(session)
            for index in members.indices where members[index].pendingInvite?.token == token {
                members[index].activeSession = session
                members[index].presence.shareEndsAt = session.endsAt
            }
            pendingInvites.removeAll { $0.token == token }
            save()
            return session
        } catch {
            inboundInviteValidationError = error.localizedDescription
            return nil
        }
    }

    func validateJoinToken(_ token: String) async {
        do {
            inboundInvite = try await backend.validateJoinToken(token)
            inboundInviteValidationError = nil
        } catch {
            inboundInvite = nil
            inboundInviteValidationError = error.localizedDescription
        }
    }

    func queueLocationUpload(location: CLLocation, participantID: String, sessionID: String) async {
        let ping = CellularLocationPing(
            participantID: participantID,
            sessionID: sessionID,
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil
        )
        uploadQueue.append(ping)
        await flushUploadQueueIfNeeded(force: false)
    }

    func flushUploadQueueIfNeeded(force: Bool) async {
        let now = Date()
        if !force, let lastUploadFailure, now.timeIntervalSince(lastUploadFailure) < 10 { return }
        if !force, let lastUploadAt, now.timeIntervalSince(lastUploadAt) < 2 { return }
        guard !uploadQueue.isEmpty else { return }
        let batch = Array(uploadQueue.prefix(3))
        do {
            try await backend.uploadLocations(batch)
            uploadQueue.removeFirst(min(3, uploadQueue.count))
            lastUploadAt = now
        } catch {
            lastUploadFailure = now
        }
    }

    func revokeInvite(_ inviteID: String) async {
        do {
            try await backend.revokeInvite(inviteID: inviteID)
            pendingInvites.removeAll { $0.id == inviteID }
            for index in members.indices where members[index].pendingInvite?.id == inviteID {
                members[index].pendingInvite = nil
            }
            save()
        } catch {
            print("Failed to revoke invite \(inviteID): \(error.localizedDescription)")
        }
    }

    func mappedContactsWithRadioFallback(_ radioContacts: [XRSRadioContact]) -> [XRSRadioContact] {
        var mapped: [XRSRadioContact] = []

        for index in members.indices {
            if let radioMatch = radioContacts.first(where: { $0.name.caseInsensitiveCompare(members[index].name) == .orderedSame }) {
                members[index].presence.xrsLocation = CLLocationCoordinate2D(latitude: radioMatch.lat, longitude: radioMatch.lon)
                members[index].presence.xrsTimestamp = radioMatch.updatedAt
            }
            members[index].presence = resolver.resolve(for: members[index].presence)
        }

        for member in members {
            guard let coordinate = member.presence.effectiveLocation else { continue }
            let status: String
            switch member.presence.effectiveTransport {
            case .cellular:
                status = "CELL"
            case .xrs:
                status = "XRS"
            case .stale:
                status = "STALE"
            case .unavailable:
                continue
            }
            let updatedAt: Date?
            switch member.presence.effectiveTransport {
            case .cellular:
                updatedAt = member.presence.cellularTimestamp ?? member.presence.xrsTimestamp
            case .xrs:
                updatedAt = member.presence.xrsTimestamp ?? member.presence.cellularTimestamp
            case .stale:
                updatedAt = member.presence.cellularTimestamp ?? member.presence.xrsTimestamp
            case .unavailable:
                updatedAt = nil
            }

            if let updatedAt {
                mapped.append(
                    XRSRadioContact(
                        id: member.id,
                        name: member.name,
                        status: status,
                        lat: coordinate.latitude,
                        lon: coordinate.longitude,
                        updatedAt: updatedAt,
                        rawMessage: "TRANSPORT:\(status)"
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

    private func upsertMemberFromInvite(_ invite: GroupTrackingInvite) {
        let phone = normalizedPhone(invite.phoneNumber)
        if let index = members.firstIndex(where: { normalizedPhone($0.phoneNumber) == phone }) {
            members[index].name = invite.inviteeName
            members[index].pendingInvite = invite
            return
        }
        let participantID = invite.id
        let presence = ParticipantPresence(
            participantID: participantID,
            displayName: invite.inviteeName,
            cellularLocation: nil,
            cellularTimestamp: nil,
            xrsLocation: nil,
            xrsTimestamp: nil,
            effectiveLocation: nil,
            effectiveTransport: .unavailable,
            isStale: false,
            shareEndsAt: nil
        )
        members.append(
            CellularTrackingMember(
                id: UUID(),
                participantID: participantID,
                name: invite.inviteeName,
                phoneNumber: invite.phoneNumber,
                presence: presence,
                activeSession: nil,
                pendingInvite: invite
            )
        )
    }
}

private struct EffectiveTransportResolver {
    private let cellularFreshSeconds: TimeInterval = 45
    private let cellularStaleUpperBoundSeconds: TimeInterval = 5 * 60

    func resolve(for presence: ParticipantPresence, now: Date = Date()) -> ParticipantPresence {
        var resolved = presence
        let cellularAge = presence.cellularTimestamp.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude

        // Resolver policy layer: prefers cellular (<=45s), otherwise falls back to current XRS source data.
        if let cellular = presence.cellularLocation, cellularAge <= cellularFreshSeconds {
            resolved.effectiveLocation = cellular
            resolved.effectiveTransport = .cellular
            resolved.isStale = false
            return resolved
        }

        if let xrs = presence.xrsLocation, presence.xrsTimestamp != nil {
            resolved.effectiveLocation = xrs
            resolved.effectiveTransport = .xrs
            resolved.isStale = false
            return resolved
        }

        if let cellular = presence.cellularLocation, cellularAge <= cellularStaleUpperBoundSeconds {
            resolved.effectiveLocation = cellular
            resolved.effectiveTransport = .stale
            resolved.isStale = true
            return resolved
        }

        resolved.effectiveTransport = .unavailable
        resolved.effectiveLocation = nil
        resolved.isStale = true
        return resolved
    }
}

private actor CellularTrackingAPI {
    private struct CreateInviteRequest: Encodable { let inviteeName: String; let phoneNumber: String }
    private struct AcceptInviteRequest: Encodable { let participantName: String }
    private struct StartSessionRequest: Encodable { let token: String; let durationSeconds: Double? }
    private struct StopSessionRequest: Encodable { let sessionID: String }
    private struct UploadRequest: Encodable { let pings: [CellularLocationPing] }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private var baseURL: URL {
        let value = UserDefaults.standard.string(forKey: "cellular_group_tracking_backend_base_url")
            ?? "https://YOURDOMAIN.com"
        return URL(string: value) ?? URL(string: "https://YOURDOMAIN.com")!
    }

    func createInvite(name: String, phoneNumber: String) async throws -> GroupTrackingInvite {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/invites"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(CreateInviteRequest(inviteeName: name, phoneNumber: phoneNumber))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(GroupTrackingInvite.self, from: data)
    }

    func validateJoinToken(_ token: String) async throws -> GroupTrackingInvite {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("join/\(token)"))
        return try decoder.decode(GroupTrackingInvite.self, from: data)
    }

    func acceptInvite(token: String, participantName: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/invites/\(token)/accept"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(AcceptInviteRequest(participantName: participantName))
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try decoder.decode([String: String].self, from: data)
        return response["participantID"] ?? ""
    }

    func startSession(token: String, duration: TimeInterval?) async throws -> CellularShareSession {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/sessions/start"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(StartSessionRequest(token: token, durationSeconds: duration))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(CellularShareSession.self, from: data)
    }

    func stopSession(sessionID: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/sessions/stop"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(StopSessionRequest(sessionID: sessionID))
        _ = try await URLSession.shared.data(for: request)
    }

    func uploadLocations(_ pings: [CellularLocationPing]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/location"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(UploadRequest(pings: pings))
        _ = try await URLSession.shared.data(for: request)
    }

    func revokeInvite(inviteID: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("group-tracking/invites/\(inviteID)/revoke"))
        request.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: request)
    }
}
