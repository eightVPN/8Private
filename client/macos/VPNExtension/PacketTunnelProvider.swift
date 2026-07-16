import NetworkExtension
import Foundation

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    static var shared: PacketTunnelProvider?

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        PacketTunnelProvider.shared = self
        
        // Register the callback so Go can send packets to the macOS IP stack
        let writeCallback: @convention(c) (UnsafeRawPointer?, Int32) -> Void = { packet, length in
            guard let packet = packet else { return }
            let data = Data(bytes: packet, count: Int(length))
            // AF_INET is 2
            PacketTunnelProvider.shared?.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
        }
        
        SetSwiftWriteCallback(writeCallback)
        
        // We expect the configuration to be passed via protocolConfiguration
        guard let conf = self.protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = conf.providerConfiguration else {
            completionHandler(NSError(domain: "VPN8", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing configuration"]))
            return
        }
        
        let serverAddr = providerConfig["serverAddr"] as? String ?? "127.0.0.1:51820"
        let accessKey = providerConfig["accessKey"] as? String ?? ""
        let hwid = providerConfig["hwid"] as? String ?? "macos_client"
        let pskHex = providerConfig["pskHex"] as? String ?? ""
        
        // Start the Go VPN core
        var result: Int32 = -1
        
        serverAddr.withCString { cServer in
            accessKey.withCString { cKey in
                hwid.withCString { cHwid in
                    pskHex.withCString { cPsk in
                        result = StartVPN(UnsafeMutablePointer(mutating: cServer),
                                          UnsafeMutablePointer(mutating: cKey),
                                          UnsafeMutablePointer(mutating: cHwid),
                                          UnsafeMutablePointer(mutating: cPsk))
                    }
                }
            }
        }
        
        if result != 0 {
            completionHandler(NSError(domain: "VPN8", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to start Go Core. Code: \(result)"]))
            return
        }
        
        // Set up the tunnel network settings
        // For a full VPN, we typically route 0.0.0.0/0
        // We will assign a dummy IP first, but ideally the server assigns the IP.
        // Our Go core handles the handshake. Wait, Go core needs to tell Swift what IP it was assigned!
        // For now, to keep it simple, we use a generic placeholder or read it from Go.
        // Actually, Apple requires setting network settings before routing works.
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverAddr)
        let ipv4Settings = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        networkSettings.ipv4Settings = ipv4Settings
        
        self.setTunnelNetworkSettings(networkSettings) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            
            // Start reading packets from the OS to send to Go
            self.readPacketsFromOS()
            completionHandler(nil)
        }
    }
    
    private func readPacketsFromOS() {
        self.packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            
            for packet in packets {
                packet.withUnsafeBytes { rawBuffer in
                    if let baseAddress = rawBuffer.baseAddress {
                        PushPacketToGo(UnsafeMutableRawPointer(mutating: baseAddress), Int32(rawBuffer.count))
                    }
                }
            }
            
            // Loop continuously
            self.readPacketsFromOS()
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        StopVPN()
        PacketTunnelProvider.shared = nil
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Can be used to pass status back to Flutter (e.g. current mode: UDP/TCP)
        if let handler = completionHandler {
            handler(messageData)
        }
    }
}
