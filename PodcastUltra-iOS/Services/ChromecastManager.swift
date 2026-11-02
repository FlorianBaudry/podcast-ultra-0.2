import Foundation
import Network
import Security
import Combine

struct CastDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String
    let endpoint: NWEndpoint
}

/// Native Google Cast (CastV2 over TLS :8009 + Bonjour `_googlecast._tcp`) implementation
/// allowing real discovery and audio streaming to Chromecast / Google Home / Android TV devices.
final class ChromecastManager: ObservableObject {
    static let shared = ChromecastManager()
    
    @Published var discoveredDevices: [CastDevice] = []
    @Published var connectedDevice: CastDevice? = nil
    @Published var isScanning: Bool = false
    @Published var isConnecting: Bool = false
    @Published var statusMessage: String? = nil
    @Published var castMediaSessionId: Int? = nil
    
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var heartbeatTimer: Timer?
    private var receiveBuffer = Data()
    private var requestIdCounter: Int = 1
    private var activeTransportId: String? = nil
    private var pendingMediaToLoad: PendingCastMedia? = nil
    
    struct PendingCastMedia {
        let url: String
        let title: String
        let subtitle: String
        let artworkUrl: String?
        let isLive: Bool
        let startTime: Double
    }
    
    private let nsConnection = "urn:x-cast:com.google.cast.tp.connection"
    private let nsHeartbeat  = "urn:x-cast:com.google.cast.tp.heartbeat"
    private let nsReceiver   = "urn:x-cast:com.google.cast.receiver"
    private let nsMedia      = "urn:x-cast:com.google.cast.media"
    private let defaultMediaReceiverAppId = "CC1AD845"
    
    private init() {}
    
    // MARK: - Bonjour / mDNS Discovery (`_googlecast._tcp`)
    func startDiscovery() {
        stopDiscovery()
        isScanning = true
        statusMessage = nil
        
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_googlecast._tcp", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true
        
        let newBrowser = NWBrowser(for: descriptor, using: params)
        newBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .failed(let err):
                    self?.statusMessage = "Recherche réseau : \(err.localizedDescription)"
                    self?.isScanning = false
                case .cancelled:
                    self?.isScanning = false
                default:
                    break
                }
            }
        }
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            var devices: [CastDevice] = []
            for result in results {
                var friendlyName = ""
                var modelName = "Chromecast"
                var deviceId = ""
                
                if case let .bonjour(txtRecord) = result.metadata {
                    let dict = txtRecord.dictionary
                    friendlyName = dict["fn"] ?? ""
                    modelName = dict["md"] ?? "Chromecast"
                    deviceId = dict["id"] ?? ""
                }
                if friendlyName.isEmpty {
                    if case let .service(name, _, _, _) = result.endpoint {
                        friendlyName = name
                    } else {
                        friendlyName = "Chromecast"
                    }
                }
                if deviceId.isEmpty {
                    deviceId = friendlyName
                }
                devices.append(CastDevice(id: deviceId, name: friendlyName, model: modelName, endpoint: result.endpoint))
            }
            DispatchQueue.main.async {
                self?.discoveredDevices = devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
        
        newBrowser.start(queue: .global(qos: .userInitiated))
        self.browser = newBrowser
    }
    
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }
    
    // Manual IP connection fallback
    func connectToIP(_ ipAddress: String, name: String? = nil) {
        let trimmed = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let host = NWEndpoint.Host(trimmed)
        let port = NWEndpoint.Port(rawValue: 8009)!
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let device = CastDevice(
            id: "manual-\(trimmed)",
            name: (name?.isEmpty == false ? name! : "Chromecast (\(trimmed))"),
            model: "Cast Receiver",
            endpoint: endpoint
        )
        connect(to: device)
    }
    
    // MARK: - CastV2 TLS Connection
    func connect(to device: CastDevice) {
        disconnect()
        isConnecting = true
        statusMessage = "Connexion à \(device.name)..."
        
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in
                // Chromecast uses self-signed device certificates
                completionHandler(true)
            },
            .global(qos: .userInitiated)
        )
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let conn = NWConnection(to: device.endpoint, using: params)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isConnecting = false
                    self.connectedDevice = device
                    self.statusMessage = "Connecté à \(device.name)"
                    self.onConnectionReady()
                case .failed(let error):
                    self.isConnecting = false
                    self.statusMessage = "Échec connexion : \(error.localizedDescription)"
                    self.disconnect()
                case .cancelled:
                    self.isConnecting = false
                default:
                    break
                }
            }
        }
        
        conn.start(queue: .global(qos: .userInitiated))
    }
    
    func disconnect() {
        if let transportId = activeTransportId {
            sendJSON(["type": "STOP", "requestId": nextRequestId()], namespace: nsReceiver, destinationId: "receiver-0")
            sendJSON(["type": "CLOSE"], namespace: nsConnection, destinationId: transportId)
        }
        sendJSON(["type": "CLOSE"], namespace: nsConnection, destinationId: "receiver-0")
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        activeTransportId = nil
        castMediaSessionId = nil
        connectedDevice = nil
        isConnecting = false
    }
    
    private func onConnectionReady() {
        receiveBuffer.removeAll()
        receiveNextChunk()
        
        // 1. Connect to receiver-0
        sendJSON(["type": "CONNECT", "origin": [:]], namespace: nsConnection, destinationId: "receiver-0")
        
        // 2. Start heartbeat every 5s
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.sendJSON(["type": "PING"], namespace: self.nsHeartbeat, destinationId: "receiver-0")
        }
        
        // 3. Launch Default Media Receiver (CC1AD845)
        sendJSON(
            ["type": "LAUNCH", "appId": defaultMediaReceiverAppId, "requestId": nextRequestId()],
            namespace: nsReceiver,
            destinationId: "receiver-0"
        )
        
        // 4. If AudioPlayerManager is already playing/loaded, queue it to cast immediately
        AudioPlayerManager.shared.syncCurrentTrackToChromecastIfConnected()
    }
    
    // MARK: - Media Control Commands
    func loadMedia(url: String, title: String, subtitle: String, artworkUrl: String?, isLive: Bool, startTime: Double) {
        let media = PendingCastMedia(
            url: url,
            title: title,
            subtitle: subtitle,
            artworkUrl: artworkUrl,
            isLive: isLive,
            startTime: startTime
        )
        self.pendingMediaToLoad = media
        
        guard connectedDevice != nil else { return }
        
        if let transportId = activeTransportId {
            sendLoadMessage(media, to: transportId)
        } else {
            // Ensure Default Media Receiver is launching
            sendJSON(
                ["type": "LAUNCH", "appId": defaultMediaReceiverAppId, "requestId": nextRequestId()],
                namespace: nsReceiver,
                destinationId: "receiver-0"
            )
        }
    }
    
    private func sendLoadMessage(_ media: PendingCastMedia, to transportId: String) {
        var metadata: [String: Any] = [
            "metadataType": 3, // MusicTrack / Audio
            "title": media.title,
            "artist": media.subtitle,
            "subtitle": media.subtitle
        ]
        if let art = media.artworkUrl, !art.isEmpty {
            metadata["images"] = [["url": art]]
        }
        
        let contentType = media.url.lowercased().contains(".m3u8") ? "application/x-mpegurl" : "audio/mpeg"
        let mediaDict: [String: Any] = [
            "contentId": media.url,
            "streamType": media.isLive ? "LIVE" : "BUFFERED",
            "contentType": contentType,
            "metadata": metadata
        ]
        
        let payload: [String: Any] = [
            "type": "LOAD",
            "requestId": nextRequestId(),
            "autoplay": true,
            "currentTime": media.isLive ? 0 : media.startTime,
            "media": mediaDict
        ]
        
        sendJSON(payload, namespace: nsMedia, destinationId: transportId)
        pendingMediaToLoad = nil
    }
    
    func play() {
        guard let transportId = activeTransportId, let sessionId = castMediaSessionId else { return }
        sendJSON(
            ["type": "PLAY", "mediaSessionId": sessionId, "requestId": nextRequestId()],
            namespace: nsMedia,
            destinationId: transportId
        )
    }
    
    func pause() {
        guard let transportId = activeTransportId, let sessionId = castMediaSessionId else { return }
        sendJSON(
            ["type": "PAUSE", "mediaSessionId": sessionId, "requestId": nextRequestId()],
            namespace: nsMedia,
            destinationId: transportId
        )
    }
    
    func seek(to seconds: Double) {
        guard let transportId = activeTransportId, let sessionId = castMediaSessionId else { return }
        sendJSON(
            ["type": "SEEK", "mediaSessionId": sessionId, "currentTime": seconds, "requestId": nextRequestId()],
            namespace: nsMedia,
            destinationId: transportId
        )
    }
    
    private func nextRequestId() -> Int {
        defer { requestIdCounter += 1 }
        return requestIdCounter
    }
    
    // MARK: - CastV2 Protobuf Wire Framing
    private func sendJSON(_ dictionary: [String: Any], namespace: String, destinationId: String) {
        guard let conn = connection,
              let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        let packet = Self.encodeCastMessage(
            sourceId: "sender-0",
            destinationId: destinationId,
            namespace: namespace,
            payloadUtf8: jsonString
        )
        conn.send(content: packet, completion: .contentProcessed { _ in })
    }
    
    private func receiveNextChunk() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
            }
            if error == nil && !isComplete {
                self.receiveNextChunk()
            }
        }
    }
    
    private func processReceiveBuffer() {
        while receiveBuffer.count >= 4 {
            let length = receiveBuffer.withUnsafeBytes { rawPtr -> UInt32 in
                let b0 = UInt32(rawPtr[0]) << 24
                let b1 = UInt32(rawPtr[1]) << 16
                let b2 = UInt32(rawPtr[2]) << 8
                let b3 = UInt32(rawPtr[3])
                return b0 | b1 | b2 | b3
            }
            let totalFrameSize = 4 + Int(length)
            guard receiveBuffer.count >= totalFrameSize else { break }
            
            let protoData = receiveBuffer.subdata(in: 4..<totalFrameSize)
            receiveBuffer.removeSubrange(0..<totalFrameSize)
            
            if let decoded = Self.decodeCastMessage(protoData) {
                handleIncomingCastMessage(namespace: decoded.namespace, payload: decoded.payloadUtf8)
            }
        }
    }
    
    private func handleIncomingCastMessage(namespace: String, payload: String) {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        if namespace == nsHeartbeat && type == "PING" {
            sendJSON(["type": "PONG"], namespace: nsHeartbeat, destinationId: "receiver-0")
            return
        }
        
        if namespace == nsReceiver && type == "RECEIVER_STATUS" {
            if let status = json["status"] as? [String: Any],
               let apps = status["applications"] as? [[String: Any]],
               let firstApp = apps.first,
               let transportId = firstApp["transportId"] as? String {
                if self.activeTransportId != transportId {
                    self.activeTransportId = transportId
                    sendJSON(["type": "CONNECT", "origin": [:]], namespace: nsConnection, destinationId: transportId)
                    sendJSON(["type": "GET_STATUS", "requestId": nextRequestId()], namespace: nsMedia, destinationId: transportId)
                }
                if let pending = self.pendingMediaToLoad {
                    sendLoadMessage(pending, to: transportId)
                }
            }
        } else if namespace == nsMedia && type == "MEDIA_STATUS" {
            if let statuses = json["status"] as? [[String: Any]],
               let first = statuses.first,
               let mediaSessionId = first["mediaSessionId"] as? Int {
                DispatchQueue.main.async {
                    self.castMediaSessionId = mediaSessionId
                }
            }
        }
    }
    
    // Minimal Protobuf encoder/decoder for CastMessage
    private static func encodeVarint(_ value: UInt64) -> Data {
        var val = value
        var data = Data()
        while val >= 0x80 {
            data.append(UInt8((val & 0x7F) | 0x80))
            val >>= 7
        }
        data.append(UInt8(val))
        return data
    }
    
    private static func encodeStringField(fieldNumber: Int, value: String) -> Data {
        let utf8 = Data(value.utf8)
        var out = Data()
        let tag = UInt64((fieldNumber << 3) | 2)
        out.append(encodeVarint(tag))
        out.append(encodeVarint(UInt64(utf8.count)))
        out.append(utf8)
        return out
    }
    
    private static func encodeVarintField(fieldNumber: Int, value: UInt64) -> Data {
        var out = Data()
        let tag = UInt64((fieldNumber << 3) | 0)
        out.append(encodeVarint(tag))
        out.append(encodeVarint(value))
        return out
    }
    
    private static func encodeCastMessage(
        sourceId: String,
        destinationId: String,
        namespace: String,
        payloadUtf8: String
    ) -> Data {
        var body = Data()
        body.append(encodeVarintField(fieldNumber: 1, value: 0)) // protocol_version = CASTV2_1_0
        body.append(encodeStringField(fieldNumber: 2, value: sourceId))
        body.append(encodeStringField(fieldNumber: 3, value: destinationId))
        body.append(encodeStringField(fieldNumber: 4, value: namespace))
        body.append(encodeVarintField(fieldNumber: 5, value: 0)) // payload_type = STRING
        body.append(encodeStringField(fieldNumber: 6, value: payloadUtf8))
        
        var lengthPrefix = UInt32(body.count).bigEndian
        var frame = Data(bytes: &lengthPrefix, count: 4)
        frame.append(body)
        return frame
    }
    
    private static func decodeCastMessage(_ data: Data) -> (namespace: String, payloadUtf8: String)? {
        var idx = 0
        var namespace = ""
        var payload = ""
        let bytes = [UInt8](data)
        
        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while idx < bytes.count {
                let b = bytes[idx]
                idx += 1
                result |= UInt64(b & 0x7F) << shift
                if (b & 0x80) == 0 { return result }
                shift += 7
                if shift >= 64 { return nil }
            }
            return nil
        }
        
        while idx < bytes.count {
            guard let tag = readVarint() else { break }
            let fieldNum = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            if wireType == 0 {
                _ = readVarint()
            } else if wireType == 2 {
                guard let len = readVarint() else { break }
                let count = Int(len)
                guard idx + count <= bytes.count else { break }
                let slice = Data(bytes[idx..<(idx + count)])
                idx += count
                if fieldNum == 4 {
                    namespace = String(data: slice, encoding: .utf8) ?? ""
                } else if fieldNum == 6 {
                    payload = String(data: slice, encoding: .utf8) ?? ""
                }
            } else {
                break
            }
        }
        return (namespace, payload)
    }
}

