import Foundation

// Tolerant decoding of `device.pair.list` and `presence.query`.
// Shapes verified against packages/gateway-protocol/src/schema/{devices,presence}.ts and
// src/gateway/device-pairing-list.types.ts. Every field is optional on our side.

struct InstancePendingRequest: Identifiable, Equatable {
    let id: String
    let deviceId: String
    let name: String
    let platform: String?
    let role: String?
    let remoteIp: String?
    let requestedAtMs: Int?
    let isRepair: Bool
    let scopes: [String]

    static func parse(_ raw: [String: Any]) -> InstancePendingRequest? {
        guard let requestId = raw.string("requestId"), !requestId.isEmpty else { return nil }
        let deviceId: String = raw.string("deviceId") ?? requestId
        let name: String = raw.string("displayName") ?? raw.string("clientId") ?? deviceId
        let scopes: [String] = (raw["scopes"] as? [String]) ?? []
        let isRepair: Bool = raw.bool("isRepair") ?? false
        return InstancePendingRequest(
            id: requestId,
            deviceId: deviceId,
            name: name,
            platform: raw.string("platform"),
            role: raw.string("role"),
            remoteIp: raw.string("remoteIp"),
            requestedAtMs: raw.int("ts"),
            isRepair: isRepair,
            scopes: scopes)
    }
}

struct InstancePairedDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let platform: String?
    let deviceFamily: String?
    let roles: [String]
    let connected: Bool?
    let lastSeenAtMs: Int?
    let approvedAtMs: Int?

    static func parse(_ raw: [String: Any]) -> InstancePairedDevice? {
        guard let deviceId = raw.string("deviceId"), !deviceId.isEmpty else { return nil }
        let name: String = raw.string("operatorLabel") ?? raw.string("displayName") ?? deviceId
        var roles: [String] = (raw["roles"] as? [String]) ?? []
        if let role = raw.string("role"), !roles.contains(role) {
            roles.append(role)
        }
        for token in raw.array("tokens") {
            if let role = token.string("role"), !roles.contains(role) {
                roles.append(role)
            }
        }
        return InstancePairedDevice(
            id: deviceId,
            name: name,
            platform: raw.string("platform"),
            deviceFamily: raw.string("deviceFamily"),
            roles: roles,
            connected: raw.bool("connected"),
            lastSeenAtMs: raw.int("lastSeenAtMs"),
            approvedAtMs: raw.int("approvedAtMs"))
    }
}

struct InstancePresenceDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String?
    let personName: String?
    let platform: String?
    let connectionCount: Int
    let lastActivityAtMs: Int?

    static func parse(_ raw: [String: Any], personName: String?) -> InstancePresenceDevice? {
        guard let id = raw.string("id"), !id.isEmpty else { return nil }
        let connections = raw.array("connections")
        let platform: String? = connections.first?.string("platform")
        let activityAt: Int? = raw.dict("activity")?.int("at")
        return InstancePresenceDevice(
            id: id,
            name: raw.string("name") ?? id,
            kind: raw.string("kind"),
            personName: personName,
            platform: platform,
            connectionCount: connections.count,
            lastActivityAtMs: activityAt)
    }

    /// Flattens `people[].devices[]` and the optional top-level `devices[]`, de-duplicated by id.
    static func parseAll(_ root: [String: Any]) -> [InstancePresenceDevice] {
        var seen = Set<String>()
        var result: [InstancePresenceDevice] = []
        for person in root.array("people") {
            let personName: String? = person.string("name")
            for raw in person.array("devices") {
                if let device = parse(raw, personName: personName), seen.insert(device.id).inserted {
                    result.append(device)
                }
            }
        }
        for raw in root.array("devices") {
            if let device = parse(raw, personName: nil), seen.insert(device.id).inserted {
                result.append(device)
            }
        }
        return result
    }
}

struct InstancesSnapshot {
    var pending: [InstancePendingRequest]
    var paired: [InstancePairedDevice]
    var presence: [InstancePresenceDevice]
    var presenceTruncated: Bool
    var pairingError: String?
    var presenceError: String?

    var isEmpty: Bool {
        self.pending.isEmpty && self.paired.isEmpty && self.presence.isEmpty
            && self.pairingError == nil && self.presenceError == nil
    }
}

enum InstanceAction {
    case approve(requestId: String)
    case reject(requestId: String)
    case remove(deviceId: String)
    case rename(deviceId: String, label: String)

    /// Gateway method names verified in core-descriptors.ts (scope: operator.pairing).
    var method: String {
        switch self {
        case .approve: "device.pair.approve"
        case .reject: "device.pair.reject"
        case .remove: "device.pair.remove"
        case .rename: "device.pair.rename"
        }
    }

    /// Params match the closed schemas in schema/devices.ts.
    var params: [String: Any] {
        switch self {
        case let .approve(requestId): ["requestId": requestId]
        case let .reject(requestId): ["requestId": requestId]
        case let .remove(deviceId): ["deviceId": deviceId]
        case let .rename(deviceId, label): ["deviceId": deviceId, "label": label]
        }
    }

    var busyKey: String {
        switch self {
        case let .approve(requestId): requestId
        case let .reject(requestId): requestId
        case let .remove(deviceId): deviceId
        case let .rename(deviceId, _): deviceId
        }
    }
}
