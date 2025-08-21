import Foundation

/// Configuration and feature flags for CampusGate
struct CampusGateConfig {
    // Feature flags
    static var jwtGatingEnabled = true  // Default: use JWT-based gating
    static var legacyPresenceEnabled = false  // Fallback to presence (deprecated)
    
    // Cache configuration
    static let neighborCacheSize = 256
    static let globalCacheSize = 8192
    static let negativeCacheTTL: TimeInterval = 60.0
    static let maxCredentialAge: TimeInterval = 1800.0 // 30 minutes
    
    // Rate limiting
    static let attestationRequestInterval: TimeInterval = 30.0
    static let proactiveAttestationInterval: TimeInterval = 300.0 // 5 minutes
    
    // Timing
    static let pruneInterval: TimeInterval = 150.0 // 2.5 minutes
    static let messageBufferWindow: TimeInterval = 2.0 // Buffer first message for 2s
    
    // Metrics
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
