import Foundation
import CoreLocation
import Combine

private let kXRSRadioMarkerLimitKey = "xrs_radio_marker_limit"      // Int
private let kXRSRadioExpiryMinutesKey = "xrs_radio_expiry_minutes"  // Int

struct XRSRadioContact: Identifiable, Hashable {
    var id: UUID
    var name: String
    var status: String?
    var lat: Double
    var lon: Double
    var updatedAt: Date
    var rawMessage: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var lastHeard: Date {
        updatedAt
    }
}

@MainActor
final class XRSRadioStore: ObservableObject {

    @Published private(set) var contacts: [UUID: XRSRadioContact] = [:]
    @Published var isConnected: Bool = false

    private var latestContactIDByUser: [String: UUID] = [:]
    private var contactIDsByUser: [String: [UUID]] = [:]

    private var markerLimit: Int {
        let value = UserDefaults.standard.integer(forKey: kXRSRadioMarkerLimitKey)
        return min(max(value == 0 ? 1 : value, 1), 10)
    }

    private var expirySeconds: TimeInterval {
        let value = UserDefaults.standard.integer(forKey: kXRSRadioExpiryMinutesKey)
        let minutes = value == 0 ? 120 : value
        let normalized = min(max(minutes, 15), 600)
        return TimeInterval(normalized * 60)
    }

    func setConnected(_ connected: Bool) {
        isConnected = connected
    }

    func upsert(contact: XRSRadioContact) {
        contacts[contact.id] = contact

        let userKey = normalizedUserKey(contact.name)
        if latestContactIDByUser[userKey] == nil {
            latestContactIDByUser[userKey] = contact.id
        }

        var ids = contactIDsByUser[userKey] ?? []
        if !ids.contains(contact.id) {
            ids.append(contact.id)
        }
        contactIDsByUser[userKey] = ids

        enforceMarkerLimits()
    }

    func updateContact(
        name: String,
        status: String?,
        latitude: Double,
        longitude: Double
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard latitude.isFinite, longitude.isFinite else { return }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return }

        let userKey = normalizedUserKey(trimmedName)
        let latestID = latestContactIDByUser[userKey] ?? stableID(for: trimmedName)

        let cleanStatus: String? = {
            let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }()

        let now = Date()
        let newLatest = XRSRadioContact(
            id: latestID,
            name: trimmedName,
            status: cleanStatus,
            lat: latitude,
            lon: longitude,
            updatedAt: now,
            rawMessage: nil
        )

        var ids = contactIDsByUser[userKey] ?? []

        if let previousLatest = contacts[latestID] {
            let shouldKeepHistory =
                markerLimit > 1 &&
                (
                    previousLatest.lat != latitude ||
                    previousLatest.lon != longitude ||
                    previousLatest.status != cleanStatus
                )

            if shouldKeepHistory {
                var historyContact = previousLatest
                historyContact.id = UUID()

                contacts[historyContact.id] = historyContact

                ids.removeAll { $0 == latestID }
                ids.append(historyContact.id)
            } else {
                ids.removeAll { $0 == latestID }
            }
        }

        contacts[latestID] = newLatest
        ids.append(latestID)

        latestContactIDByUser[userKey] = latestID
        contactIDsByUser[userKey] = ids

        enforceMarkerLimit(for: userKey)
        removeStaleContacts()
    }

    func removeStaleContacts(olderThan seconds: TimeInterval? = nil) {
        let cutoff = Date().addingTimeInterval(-(seconds ?? expirySeconds))

        contacts = contacts.filter { _, contact in
            contact.updatedAt > cutoff
        }

        for (userKey, ids) in contactIDsByUser {
            let filtered = ids.filter { contacts[$0] != nil }
            contactIDsByUser[userKey] = filtered.isEmpty ? nil : filtered
        }

        for (userKey, latestID) in latestContactIDByUser {
            if contacts[latestID] == nil {
                if let replacementID = contactIDsByUser[userKey]?.last {
                    latestContactIDByUser[userKey] = replacementID
                } else {
                    latestContactIDByUser[userKey] = nil
                }
            }
        }

        enforceMarkerLimits()
    }

    var allContacts: [XRSRadioContact] {
        Array(contacts.values).sorted { lhs, rhs in
            lhs.updatedAt < rhs.updatedAt
        }
    }

    func load() {
        removeStaleContacts()
        enforceMarkerLimits()
    }

    func save() { }

    private func enforceMarkerLimits() {
        for userKey in contactIDsByUser.keys {
            enforceMarkerLimit(for: userKey)
        }
    }

    private func enforceMarkerLimit(for userKey: String) {
        let limit = markerLimit
        guard limit > 0 else { return }

        var ids = contactIDsByUser[userKey] ?? []
        guard !ids.isEmpty else { return }

        while ids.count > limit {
            let removedID = ids.removeFirst()
            contacts.removeValue(forKey: removedID)

            if latestContactIDByUser[userKey] == removedID {
                latestContactIDByUser[userKey] = ids.last
            }
        }

        contactIDsByUser[userKey] = ids.isEmpty ? nil : ids

        if latestContactIDByUser[userKey] == nil {
            latestContactIDByUser[userKey] = ids.last
        }
    }

    private func normalizedUserKey(_ name: String) -> String {
        name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stableID(for name: String) -> UUID {
        let cleaned = normalizedUserKey(name)

        let hash = cleaned.utf8.reduce(UInt64(1469598103934665603)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }

        let a = UInt32((hash >> 32) & 0xffffffff)
        let b = UInt16((hash >> 16) & 0xffff)
        let c = UInt16(hash & 0xffff)
        let d = UInt16((hash >> 48) & 0xffff)
        let e = UInt64(hash & 0xffffffffffff)

        let uuidString = String(format: "%08X-%04X-%04X-%04X-%012llX", a, b, c, d, e)
        return UUID(uuidString: uuidString) ?? UUID()
    }
}
