import Cocoa
import FlutterMacOS
import NetworkExtension

class MainFlutterWindow: NSWindow {
  var vpnManager: NETunnelProviderManager?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    setupVPNChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private func setupVPNChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.eightvpn/bridge", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      switch call.method {
      case "startVPN":
        if let args = call.arguments as? [String: Any] {
            self.startVPN(args: args, result: result)
        } else {
            result(FlutterError(code: "INVALID_ARGS", message: "Arguments missing", details: nil))
        }
      case "stopVPN":
        self.stopVPN(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func loadVPNManager(completion: @escaping (NETunnelProviderManager?) -> Void) {
      NETunnelProviderManager.loadAllFromPreferences { managers, error in
          if let managers = managers, let manager = managers.first(where: { $0.localizedDescription == "VPN 8" }) {
              completion(manager)
          } else {
              let manager = NETunnelProviderManager()
              let protocolConfiguration = NETunnelProviderProtocol()
              
              guard let bundleId = Bundle.main.bundleIdentifier else {
                  completion(nil)
                  return
              }
              
              protocolConfiguration.providerBundleIdentifier = bundleId + ".VPNExtension"
              protocolConfiguration.serverAddress = "VPN 8 Server"
              manager.protocolConfiguration = protocolConfiguration
              manager.localizedDescription = "VPN 8"
              
              manager.saveToPreferences { error in
                  if let error = error {
                      print("Error saving VPN manager: \(error)")
                      completion(nil)
                  } else {
                      manager.loadFromPreferences { _ in
                          completion(manager)
                      }
                  }
              }
          }
      }
  }

  private func startVPN(args: [String: Any], result: @escaping FlutterResult) {
      loadVPNManager { manager in
          guard let manager = manager else {
              result(FlutterError(code: "VPN_INIT_FAILED", message: "Failed to initialize VPN profile", details: nil))
              return
          }
          
          self.vpnManager = manager
          
          // Pass arguments to the Provider
          if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol {
              proto.providerConfiguration = args
              manager.protocolConfiguration = proto
          }
          
          manager.saveToPreferences { error in
              if let error = error {
                  result(FlutterError(code: "VPN_SAVE_FAILED", message: error.localizedDescription, details: nil))
                  return
              }
              
              manager.loadFromPreferences { error in
                  do {
                      try manager.connection.startVPNTunnel()
                      result(true)
                  } catch {
                      result(FlutterError(code: "VPN_START_FAILED", message: error.localizedDescription, details: nil))
                  }
              }
          }
      }
  }

  private func stopVPN(result: @escaping FlutterResult) {
      vpnManager?.connection.stopVPNTunnel()
      result(true)
  }
}
