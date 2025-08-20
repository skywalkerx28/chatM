//
// MockBluetoothMeshService.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import MultipeerConnectivity
@testable import chatM

class MockBluetoothMeshService: BluetoothMeshService {
    var sentMessages: [(message: BitchatMessage, packet: BitchatPacket)] = []
    var sentPackets: [BitchatPacket] = []
    var connectedPeers: Set<String> = []
    var messageDeliveryHandler: ((BitchatMessage) -> Void)?
    var packetDeliveryHandler: ((BitchatPacket) -> Void)?
    var roomMessageDeliveryHandler: ((RoomMessage) -> Void)?
    
    // Static registry to allow peers to find each other
    private static var serviceRegistry: [String: MockBluetoothMeshService] = [:]
    private static let registryQueue = DispatchQueue(label: "com.mockservice.registry", attributes: .concurrent)
    
    /// Clear the service registry (useful for test cleanup)
    static func clearRegistry() {
        registryQueue.sync(flags: .barrier) {
            // Clear seen message IDs for all services before clearing registry
            for service in serviceRegistry.values {
                service.seenMessagesQueue.sync(flags: .barrier) {
                    service.seenMessageIDs.removeAll()
                }
            }
            serviceRegistry.removeAll()
        }
    }
    
    // Room message testing support
    var joinedConversations: Set<Data> = []
    var campusId: String?
    
    // Message tracking for duplicate detection
    private var seenMessageIDs: Set<String> = []
    private let seenMessagesQueue = DispatchQueue(label: "com.mockservice.seenmessages", attributes: .concurrent)
    
    // Override these properties
    var mockNickname: String = "MockUser"
    
    override var myPeerID: String {
        didSet {
            // Update registry when peer ID changes
            MockBluetoothMeshService.registryQueue.sync(flags: .barrier) {
                MockBluetoothMeshService.serviceRegistry.removeValue(forKey: oldValue)
                MockBluetoothMeshService.serviceRegistry[self.myPeerID] = self
            }
        }
    }
    
    var nickname: String {
        return mockNickname
    }
    
    var peerID: String {
        return myPeerID
    }
    
    override init() {
        super.init()
        self.myPeerID = "MOCK1234"
        // Register this service instance
        MockBluetoothMeshService.registryQueue.sync(flags: .barrier) {
            MockBluetoothMeshService.serviceRegistry[self.myPeerID] = self
        }
    }
    
    deinit {
        // Clean up registry
        let currentPeerID = self.myPeerID
        MockBluetoothMeshService.registryQueue.async(flags: .barrier) {
            MockBluetoothMeshService.serviceRegistry.removeValue(forKey: currentPeerID)
        }
    }
    
    func simulateConnectedPeer(_ peerID: String) {
        connectedPeers.insert(peerID)
        delegate?.didConnectToPeer(peerID)
        delegate?.didUpdatePeerList(Array(connectedPeers))
    }
    
    func simulateDisconnectedPeer(_ peerID: String) {
        connectedPeers.remove(peerID)
        delegate?.didDisconnectFromPeer(peerID)
        delegate?.didUpdatePeerList(Array(connectedPeers))
    }
    
    override func sendMessage(_ content: String, mentions: [String], to room: String? = nil, messageID: String? = nil, timestamp: Date? = nil) {
        let message = BitchatMessage(
            id: messageID ?? UUID().uuidString,
            sender: mockNickname,
            content: content,
            timestamp: timestamp ?? Date(),
            isRelay: false,
            originalSender: nil,
            isPrivate: false,
            recipientNickname: nil,
            senderPeerID: myPeerID,
            mentions: mentions.isEmpty ? nil : mentions
        )
        
        if let payload = message.toBinaryPayload() {
            let packet = BitchatPacket(
                type: 0x01,
                senderID: myPeerID.data(using: .utf8) ?? Data(),
                recipientID: nil,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                payload: payload,
                signature: nil,
                ttl: 2
            )
            
            sentMessages.append((message, packet))
            sentPackets.append(packet)
            
            // Simulate local echo
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceiveMessage(message)
            }
            
            // Deliver message to all connected peers
            deliverMessageToConnectedPeers(message)
        }
    }
    
    override func sendPrivateMessage(_ content: String, to recipientPeerID: String, recipientNickname: String, messageID: String? = nil) {
        let message = BitchatMessage(
            id: messageID ?? UUID().uuidString,
            sender: mockNickname,
            content: content,
            timestamp: Date(),
            isRelay: false,
            originalSender: nil,
            isPrivate: true,
            recipientNickname: recipientNickname,
            senderPeerID: myPeerID,
            mentions: nil
        )
        
        if let payload = message.toBinaryPayload() {
            let packet = BitchatPacket(
                type: 0x01,
                senderID: myPeerID.data(using: .utf8) ?? Data(),
                recipientID: recipientPeerID.data(using: .utf8) ?? Data(),
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                payload: payload,
                signature: nil,
                ttl: 2
            )
            
            sentMessages.append((message, packet))
            sentPackets.append(packet)
            
            // Simulate local echo
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceiveMessage(message)
            }
            
            // Deliver private message to specific recipient
            deliverPrivateMessageToRecipient(message, recipientPeerID: recipientPeerID)
        }
    }
    
    func simulateIncomingMessage(_ message: BitchatMessage) {
        delegate?.didReceiveMessage(message)
    }
    
    func simulateIncomingPacket(_ packet: BitchatPacket) {
        // This simulates a packet arriving from the network
        // It should trigger both message delivery and packet handling for relay
        
        // Handle different packet types
        if packet.type == MessageType.roomMessage.rawValue {
            // Handle room message
            if let roomMessage = RoomMessage.decode(from: packet.payload) {
                // Check if we should accept this room message
                guard let peerCampusId = self.campusId else { return }
                let isAnnouncements = roomMessage.conversationId == TopicManager.announcementsId(campusId: peerCampusId)
                
                if isAnnouncements || joinedConversations.contains(roomMessage.conversationId) {
                    // Check for duplicate
                    let messageKey = "\(roomMessage.messageId)-\(self.myPeerID)"
                    let shouldDeliver = seenMessagesQueue.sync(flags: .barrier) {
                        if seenMessageIDs.contains(messageKey) {
                            return false
                        } else {
                            seenMessageIDs.insert(messageKey)
                            return true
                        }
                    }
                    
                    if shouldDeliver {
                        DispatchQueue.main.async {
                            self.roomMessageDeliveryHandler?(roomMessage)
                        }
                    }
                }
            }
        } else {
            // Handle regular message
            if let message = BitchatMessage.fromBinaryPayload(packet.payload) {
                // Check for duplicate
                let messageKey = "\(message.id)-\(self.myPeerID)"
                let shouldDeliver = seenMessagesQueue.sync(flags: .barrier) {
                    if seenMessageIDs.contains(messageKey) {
                        return false
                    } else {
                        seenMessageIDs.insert(messageKey)
                        return true
                    }
                }
                
                if shouldDeliver {
                    DispatchQueue.main.async {
                        self.delegate?.didReceiveMessage(message)
                        self.messageDeliveryHandler?(message)
                    }
                }
            }
        }
        
        // Trigger packet handler for relay logic
        DispatchQueue.main.async {
            self.packetDeliveryHandler?(packet)
        }
        
        // Implement automatic relay if no explicit relay handler is set
        if packetDeliveryHandler == nil {
            if packet.type == MessageType.roomMessage.rawValue {
                self.performAutomaticRoomMessageRelay(packet)
            } else {
                self.performAutomaticMessageRelay(packet)
            }
        }
    }
    
    func getConnectedPeers() -> [String] {
        return Array(connectedPeers)
    }
    
    /// Automatic relay logic for room messages when no explicit packetDeliveryHandler is set
    private func performAutomaticRoomMessageRelay(_ packet: BitchatPacket) {
        // Check if should relay (TTL > 1)
        guard packet.ttl > 1 else { return }
        
        // Don't relay own messages
        let originalSenderID = packet.senderID.hexEncodedString()
        guard originalSenderID != myPeerID else { return }
        
        // Decode room message
        guard let roomMessage = RoomMessage.decode(from: packet.payload) else { return }
        
        // Check if we should accept this room message (same campus check)
        guard let myCampusId = self.campusId else { return }
        let isAnnouncements = roomMessage.conversationId == TopicManager.announcementsId(campusId: myCampusId)
        guard isAnnouncements || joinedConversations.contains(roomMessage.conversationId) else { return }
        
        // Create relay packet with decremented TTL
        let relayPacket = BitchatPacket(
            type: MessageType.roomMessage.rawValue,
            senderID: packet.senderID, // Keep original sender
            recipientID: SpecialRecipients.broadcast,
            timestamp: packet.timestamp,
            payload: packet.payload,   // Keep original payload
            signature: packet.signature,
            ttl: packet.ttl - 1       // Decrement TTL
        )
        
        // Relay to all connected peers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self = self else { return }
            
            // Send relay packet to all connected peers
            for peerID in self.connectedPeers {
                MockBluetoothMeshService.registryQueue.sync {
                    if let peerService = MockBluetoothMeshService.serviceRegistry[peerID] {
                        DispatchQueue.main.async {
                            peerService.simulateIncomingPacket(relayPacket)
                        }
                    }
                }
            }
        }
    }
    
    /// Automatic relay logic for regular messages when no explicit packetDeliveryHandler is set
    private func performAutomaticMessageRelay(_ packet: BitchatPacket) {
        // Check if should relay (TTL > 1)
        guard packet.ttl > 1 else { return }
        
        // Don't relay own messages
        let originalSenderID = packet.senderID.hexEncodedString()
        guard originalSenderID != myPeerID else { return }
        
        // Decode regular message
        guard let message = BitchatMessage.fromBinaryPayload(packet.payload) else { return }
        
        // Create relay message
        let relayMessage = BitchatMessage(
            id: message.id,
            sender: message.sender,
            content: message.content,
            timestamp: message.timestamp,
            isRelay: true,
            originalSender: message.isRelay ? message.originalSender : message.sender,
            isPrivate: message.isPrivate,
            recipientNickname: message.recipientNickname,
            senderPeerID: message.senderPeerID,
            mentions: message.mentions
        )
        
        // Create relay packet with decremented TTL
        guard let relayPayload = relayMessage.toBinaryPayload() else { return }
        let relayPacket = BitchatPacket(
            type: packet.type,
            senderID: packet.senderID, // Keep original sender
            recipientID: packet.recipientID,
            timestamp: packet.timestamp,
            payload: relayPayload,
            signature: packet.signature,
            ttl: packet.ttl - 1       // Decrement TTL
        )
        
        // Relay to all connected peers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self = self else { return }
            
            // Send relay packet to all connected peers
            for peerID in self.connectedPeers {
                MockBluetoothMeshService.registryQueue.sync {
                    if let peerService = MockBluetoothMeshService.serviceRegistry[peerID] {
                        DispatchQueue.main.async {
                            peerService.simulateIncomingPacket(relayPacket)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Room Message Testing Support
    
    func setupCampusPresence(campusId: String) {
        self.campusId = campusId
        // Simulate valid campus presence for testing
    }
    
    func joinConversation(_ conversationId: Data) {
        joinedConversations.insert(conversationId)
    }
    
    func leaveConversation(_ conversationId: Data) {
        joinedConversations.remove(conversationId)
    }
    
    override func sendRoomMessage(_ content: String, in conversationId: Data, mentions: [String] = [], messageID: String? = nil) {
        let roomMessage = RoomMessage(
            conversationId: conversationId,
            messageId: messageID,
            sender: mockNickname,
            content: content,
            mentions: mentions.isEmpty ? nil : mentions
        )
        
        guard let roomMessageData = roomMessage.encode() else { return }
        
        let packet = BitchatPacket(
            type: MessageType.roomMessage.rawValue,
            senderID: Data(hexString: myPeerID) ?? Data(),
            recipientID: SpecialRecipients.broadcast,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: roomMessageData,
            signature: nil,
            ttl: 2
        )
        
        sentPackets.append(packet)
        
        // Deliver room message to all connected peers
        deliverRoomMessageToConnectedPeers(roomMessage)
    }
    
    func simulateReceiveRoomMessage(_ roomMessage: RoomMessage, from senderID: String) {
        // Simulate receiving a room message from another peer
        guard let roomMessageData = roomMessage.encode() else { return }
        
        let packet = BitchatPacket(
            type: MessageType.roomMessage.rawValue,
            senderID: Data(hexString: senderID) ?? Data(),
            recipientID: SpecialRecipients.broadcast,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: roomMessageData,
            signature: nil,
            ttl: 2
        )
        
        // Simulate campus gate check
        if let currentCampusId = campusId {
            // For testing, assume sender has valid presence if campus matches
            if roomMessage.conversationId.starts(with: TopicManager.blake3_8("campus|\(currentCampusId)").prefix(8)) {
                // Campus matches, check if joined (except for announcements)
                let announcementsId = TopicManager.announcementsId(campusId: currentCampusId)
                if roomMessage.conversationId == announcementsId || joinedConversations.contains(roomMessage.conversationId) {
                    roomMessageDeliveryHandler?(roomMessage)
                }
            }
        }
    }
    
    // MARK: - Message Delivery Simulation
    
    /// Deliver a regular message to all connected peers
    private func deliverMessageToConnectedPeers(_ message: BitchatMessage) {
        for peerID in connectedPeers {
            MockBluetoothMeshService.registryQueue.sync {
                if let peerService = MockBluetoothMeshService.serviceRegistry[peerID] {
                    // Check for duplicate delivery to this peer
                    let messageKey = "\(message.id)-\(peerID)"
                    let shouldDeliver = peerService.seenMessagesQueue.sync(flags: .barrier) {
                        if peerService.seenMessageIDs.contains(messageKey) {
                            return false // Already delivered
                        } else {
                            peerService.seenMessageIDs.insert(messageKey)
                            return true
                        }
                    }
                    
                    if shouldDeliver {
                        // Deliver on main queue to simulate async network delivery
                        DispatchQueue.main.async {
                            peerService.messageDeliveryHandler?(message)
                        }
                        
                        // Trigger relay logic separately to avoid recursion
                        if let payload = message.toBinaryPayload() {
                            // Preserve original sender information for relay logic
                            let originalSenderID = Data(hexString: message.senderPeerID ?? self.myPeerID) ?? Data()
                            let packet = BitchatPacket(
                                type: 0x01,
                                senderID: originalSenderID,  // Keep original sender for relay logic
                                recipientID: nil,
                                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                payload: payload,
                                signature: nil,
                                ttl: 2
                            )
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                peerService.packetDeliveryHandler?(packet)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Deliver a private message to a specific recipient
    private func deliverPrivateMessageToRecipient(_ message: BitchatMessage, recipientPeerID: String) {
        MockBluetoothMeshService.registryQueue.sync {
            if let recipientService = MockBluetoothMeshService.serviceRegistry[recipientPeerID] {
                // Check if we're connected to this recipient
                if connectedPeers.contains(recipientPeerID) {
                    // Check for duplicate delivery
                    let messageKey = "\(message.id)-\(recipientPeerID)"
                    let shouldDeliver = recipientService.seenMessagesQueue.sync(flags: .barrier) {
                        if recipientService.seenMessageIDs.contains(messageKey) {
                            return false // Already delivered
                        } else {
                            recipientService.seenMessageIDs.insert(messageKey)
                            return true
                        }
                    }
                    
                    if shouldDeliver {
                        // Deliver on main queue to simulate async network delivery
                        DispatchQueue.main.async {
                            recipientService.messageDeliveryHandler?(message)
                        }
                    }
                }
            }
        }
    }
    
    /// Deliver a room message to all connected peers
    private func deliverRoomMessageToConnectedPeers(_ roomMessage: RoomMessage) {
        for peerID in connectedPeers {
            MockBluetoothMeshService.registryQueue.sync {
                if let peerService = MockBluetoothMeshService.serviceRegistry[peerID] {
                    // Check if the peer should receive this room message based on campus and join status
                    guard let peerCampusId = peerService.campusId else { return }
                    
                    // Simple campus check (for testing)
                    if peerCampusId == self.campusId {
                        let isAnnouncements = roomMessage.conversationId == TopicManager.announcementsId(campusId: peerCampusId)
                        if isAnnouncements || peerService.joinedConversations.contains(roomMessage.conversationId) {
                            // Check for duplicate delivery
                            let messageKey = "\(roomMessage.messageId)-\(peerID)"
                            let shouldDeliver = peerService.seenMessagesQueue.sync(flags: .barrier) {
                                if peerService.seenMessageIDs.contains(messageKey) {
                                    return false // Already delivered
                                } else {
                                    peerService.seenMessageIDs.insert(messageKey)
                                    return true
                                }
                            }
                            
                            if shouldDeliver {
                                // Deliver on main queue to simulate async network delivery
                                DispatchQueue.main.async {
                                    peerService.roomMessageDeliveryHandler?(roomMessage)
                                }
                                
                                // Trigger relay logic separately to avoid recursion  
                                if let roomMessageData = roomMessage.encode() {
                                    // For room messages, preserve the original sender's peer ID for relay logic
                                    // self.myPeerID is the original sender (Alice), which is what we want for relay
                                    let originalSenderID = Data(hexString: self.myPeerID) ?? Data()
                                    let packet = BitchatPacket(
                                        type: MessageType.roomMessage.rawValue,
                                        senderID: originalSenderID,  // Keep original sender for relay logic
                                        recipientID: SpecialRecipients.broadcast,
                                        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                                        payload: roomMessageData,
                                        signature: nil,
                                        ttl: 2
                                    )
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                        peerService.packetDeliveryHandler?(packet)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}