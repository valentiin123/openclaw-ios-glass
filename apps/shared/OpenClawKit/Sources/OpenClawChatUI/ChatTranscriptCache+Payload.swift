import Foundation
import GRDB

extension OpenClawChatSQLiteTranscriptCache {
    // MARK: - Payload encoding (soft-migrated compression) and byte budgets

    /// Marker for a compressed `cached_messages.payload_json`. Raw JSON rows
    /// always start with `{`, so old rows and new rows are told apart without
    /// a schema change: readers accept both, writers compress only large rows.
    static let compressedPayloadPrefix: String = "lzfse1:"

    /// Rows smaller than this stay plain JSON (cheap to read, easy to inspect).
    static let compressedPayloadMinimumBytes: Int = 4096

    /// Stored-size budget for one cached transcript. The newest message is
    /// always kept, older ones are dropped first.
    static let maxCachedTranscriptBytes: Int = 1_500_000

    /// Stored-size budget for all cached transcripts of one gateway. The least
    /// recently written transcripts are evicted first.
    static let maxCachedTranscriptBytesPerGateway: Int = 24_000_000

    /// The gateway-wide byte scan only runs when the transcript just written is
    /// at least this big. With at most `maxCachedTranscripts` (50) transcripts,
    /// 50 x 400 KB = 20 MB stays below the gateway budget, so smaller writes can
    /// never push the total over it and need no scan.
    static let transcriptBudgetCheckThresholdBytes: Int = 400_000

    /// Deterministic JSON (sorted keys) so that an unchanged message always
    /// yields an identical row, which lets the writer skip unchanged snapshots.
    nonisolated static func encodeCachedPayload(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let raw: Data = try encoder.encode(value)
        let json = String(decoding: raw, as: UTF8.self)
        guard raw.count >= Self.compressedPayloadMinimumBytes,
              let compressed = try? (raw as NSData).compressed(using: .lzfse)
        else { return json }
        let candidate = Self.compressedPayloadPrefix + (compressed as Data).base64EncodedString()
        // Base64 costs a third; keep the compressed form only when it still wins.
        return candidate.utf8.count < raw.count ? candidate : json
    }

    /// Accepts both the legacy plain-JSON row and the compressed row.
    nonisolated static func cachedPayloadData(_ payload: String) throws -> Data {
        guard payload.hasPrefix(Self.compressedPayloadPrefix) else { return Data(payload.utf8) }
        let body = String(payload.dropFirst(Self.compressedPayloadPrefix.count))
        guard let compressed = Data(base64Encoded: body) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "cached payload is not valid base64"))
        }
        let restored = try (compressed as NSData).decompressed(using: .lzfse)
        return restored as Data
    }

    nonisolated static func decodeCachedPayload<Value: Decodable>(
        _ type: Value.Type,
        from payload: String,
        using decoder: JSONDecoder = JSONDecoder()) throws -> Value
    {
        let data: Data = try Self.cachedPayloadData(payload)
        return try decoder.decode(type, from: data)
    }

    /// Evicts the least recently written transcripts of a gateway until the
    /// stored byte total fits. The transcript that was just written is never
    /// evicted, even when it alone exceeds the budget.
    nonisolated static func enforceTranscriptByteBudget(
        _ db: Database,
        gatewayID: String,
        keepingSessionKey: String,
        keepingAgentID: String) throws
    {
        let total: Int = try Int.fetchOne(
            db,
            sql: """
            SELECT COALESCE(SUM(LENGTH(CAST(payload_json AS BLOB))), 0)
            FROM cached_messages WHERE gateway_id = ?
            """,
            arguments: [gatewayID]) ?? 0
        guard total > Self.maxCachedTranscriptBytesPerGateway else { return }
        let rows: [Row] = try Row.fetchAll(
            db,
            sql: """
            SELECT t.session_key AS session_key, t.agent_id AS agent_id,
                   COALESCE(SUM(LENGTH(CAST(m.payload_json AS BLOB))), 0) AS bytes
            FROM cached_transcripts t
            LEFT JOIN cached_messages m
              ON m.gateway_id = t.gateway_id AND m.session_key = t.session_key
                AND m.agent_id = t.agent_id
            WHERE t.gateway_id = ?
            GROUP BY t.session_key, t.agent_id
            ORDER BY t.updated_at ASC
            """,
            arguments: [gatewayID])
        var remaining: Int = total
        for row in rows {
            guard remaining > Self.maxCachedTranscriptBytesPerGateway else { break }
            let sessionKey: String = row["session_key"]
            let agentID: String = row["agent_id"]
            if sessionKey == keepingSessionKey, agentID == keepingAgentID { continue }
            let bytes: Int = row["bytes"]
            try db.execute(
                sql: """
                DELETE FROM cached_transcripts
                WHERE gateway_id = ? AND session_key = ? AND agent_id = ?
                """,
                arguments: [gatewayID, sessionKey, agentID])
            remaining -= bytes
        }
    }
}
