import Foundation

// MARK: - Configuration

/// Configuration and metrics for CampusGate
extension CampusGate {
    struct Config {
        static let neighborCacheSize = 256
        static let globalCacheSize = 8192
        static let negativeCacheTTL: TimeInterval = 60.0
        static let maxCredentialAge: TimeInterval = 1800.0 // 30 minutes
        static let attestationRequestInterval: TimeInterval = 30.0
        static let pruneInterval: TimeInterval = 150.0 // 2.5 minutes
    }
    
    struct Metrics {
        static var jwtVerifications = 0
        static var popVerifications = 0
        static var cacheHits = 0
        static var cacheMisses = 0
        static var attestationRequests = 0
        static var attestationDenials = 0
        
        static func reset() {
            jwtVerifications = 0
            popVerifications = 0
            cacheHits = 0
            cacheMisses = 0
            attestationRequests = 0
            attestationDenials = 0
        }
        
        static func logStats() {
            SecureLogger.log("CampusGate Metrics - JWT:\(jwtVerifications) PoP:\(popVerifications) Hits:\(cacheHits) Miss:\(cacheMisses) Req:\(attestationRequests) Deny:\(attestationDenials)", 
                           category: SecureLogger.session, level: .info)
        }
    }
}

// MARK: - Cache Entry

struct AttestationCacheEntry {
    let campusPrefix16: Data       // 16-byte campus prefix for fast comparison
    let campusId: String          // Original campus ID
    let exp: Date                 // Credential expiration
    let lastVerifiedAt: Date      // When attestation was verified
    var lastAccessAt: Date        // Last time entry was accessed
    
    var isExpired: Bool {
        return Date() > exp || Date().timeIntervalSince(lastVerifiedAt) > 1800 // 30 min max
    }
}

// MARK: - Rate Limiter

struct AttestationRequestLimiter {
    private var lastRequests: [String: Date] = [:]
    private let minInterval: TimeInterval = 30.0 // 30 seconds between requests per peer
    
    mutating func canRequest(for peerID: String) -> Bool {
        let now = Date()
        if let lastRequest = lastRequests[peerID] {
            if now.timeIntervalSince(lastRequest) < minInterval {
                return false
            }
        }
        lastRequests[peerID] = now
        return true
    }
    
    mutating func cleanup() {
        let cutoff = Date().addingTimeInterval(-minInterval * 2)
        lastRequests = lastRequests.filter { $0.value > cutoff }
    }
}

// MARK: - CampusGate Actor

actor CampusGate {
    // Two-tier cache
    private var neighborCache: [String: AttestationCacheEntry] = [:]  // Direct connections
    private var globalCache: [String: AttestationCacheEntry] = [:]    // All peers
    private var negativeCache: [String: Date] = [:]                   // Failed attestations
    
    // Rate limiting
    private var requestLimiter = AttestationRequestLimiter()
    
    // Use configuration from nested struct
    private var neighborCacheSize: Int { Config.neighborCacheSize }
    private var globalCacheSize: Int { Config.globalCacheSize }
    private var negativeCacheTTL: TimeInterval { Config.negativeCacheTTL }
    
    // Timer for periodic cleanup
    private var pruneTimer: Timer?
    
    init() {
        startPruneTimer()
    }
    
    deinit {
        pruneTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    /// Accept and cache campus attestation
    func acceptAttestation(peerID: String, campusId: String, exp: Date, campusPrefix16: Data) {
        let entry = AttestationCacheEntry(
            campusPrefix16: campusPrefix16,
            campusId: campusId,
            exp: exp,
            lastVerifiedAt: Date(),
            lastAccessAt: Date()
        )
        
        // Add to appropriate cache tier
        if neighborCache[peerID] != nil {
            neighborCache[peerID] = entry
        } else {
            globalCache[peerID] = entry
            trimGlobalCache()
        }
        
        // Remove from negative cache if present
        negativeCache.removeValue(forKey: peerID)
    }
    
    /// Check if message from peer is allowed for conversation
    func isAllowed(conversationId: Data, senderPeerID: String) -> Bool {
        guard let conversationPrefix = TopicManager.extractCampusPrefix16(from: conversationId) else {
            return false
        }
        
        // Check neighbor cache first
        if var entry = neighborCache[senderPeerID] {
            if !entry.isExpired && entry.campusPrefix16 == conversationPrefix {
                entry.lastAccessAt = Date()
                neighborCache[senderPeerID] = entry
                Metrics.cacheHits += 1
                return true
            } else if entry.isExpired {
                neighborCache.removeValue(forKey: senderPeerID)
            }
        }
        
        // Check global cache
        if var entry = globalCache[senderPeerID] {
            if !entry.isExpired && entry.campusPrefix16 == conversationPrefix {
                entry.lastAccessAt = Date()
                globalCache[senderPeerID] = entry
                Metrics.cacheHits += 1
                return true
            } else if entry.isExpired {
                globalCache.removeValue(forKey: senderPeerID)
            }
        }
        
        Metrics.cacheMisses += 1
        return false
    }
    
    /// Check if attestation request should be sent (rate-limited)
    func shouldRequestAttestation(for peerID: String) -> Bool {
        // Check negative cache first
        if let negativeTime = negativeCache[peerID] {
            if Date().timeIntervalSince(negativeTime) < negativeCacheTTL {
                return false
            } else {
                negativeCache.removeValue(forKey: peerID)
            }
        }
        
        let canRequest = requestLimiter.canRequest(for: peerID)
        if canRequest {
            Metrics.attestationRequests += 1
        }
        return canRequest
    }
    
    /// Mark attestation request as failed (negative cache)
    func markAttestationFailed(for peerID: String) {
        negativeCache[peerID] = Date()
        Metrics.attestationDenials += 1
    }
    
    /// Promote peer to neighbor cache (on connect)
    func promoteToNeighbor(peerID: String) {
        if let entry = globalCache.removeValue(forKey: peerID) {
            neighborCache[peerID] = entry
            trimNeighborCache()
        }
    }
    
    /// Demote peer to global cache (on disconnect)  
    func demoteToGlobal(peerID: String) {
        if let entry = neighborCache.removeValue(forKey: peerID) {
            globalCache[peerID] = entry
            trimGlobalCache()
        }
    }
    
    // MARK: - Cache Management
    
    private func trimNeighborCache() {
        if neighborCache.count > neighborCacheSize {
            let sorted = neighborCache.sorted { $0.value.lastAccessAt < $1.value.lastAccessAt }
            let toRemove = sorted.prefix(neighborCache.count - neighborCacheSize)
            for (peerID, _) in toRemove {
                neighborCache.removeValue(forKey: peerID)
            }
        }
    }
    
    private func trimGlobalCache() {
        if globalCache.count > globalCacheSize {
            let sorted = globalCache.sorted { $0.value.lastAccessAt < $1.value.lastAccessAt }
            let toRemove = sorted.prefix(globalCache.count - globalCacheSize)
            for (peerID, _) in toRemove {
                globalCache.removeValue(forKey: peerID)
            }
        }
    }
    
    func prune() {
        let now = Date()
        
        // Remove expired entries
        neighborCache = neighborCache.filter { !$0.value.isExpired }
        globalCache = globalCache.filter { !$0.value.isExpired }
        
        // Clean negative cache
        negativeCache = negativeCache.filter { 
            now.timeIntervalSince($0.value) < negativeCacheTTL 
        }
        
        // Clean rate limiter
        requestLimiter.cleanup()
        
        // Trim caches to size
        trimNeighborCache()
        trimGlobalCache()
    }
    
    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 150.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.prune()
            }
        }
    }
    
    // MARK: - Debug Info
    
    func getCacheStats() -> (neighborCount: Int, globalCount: Int, negativeCount: Int) {
        return (neighborCache.count, globalCache.count, negativeCache.count)
    }
}