import Foundation
import Network

public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.tgplayer.networkmonitor")
    
    @Published public var isConnected: Bool = true
    @Published public var isExpensive: Bool = false
    
    public var onConnectedAgain: (() -> Void)?
    
    private var isFirstCheck = true
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            
            DispatchQueue.main.async {
                let wasDisconnected = !self.isConnected
                self.isConnected = connected
                self.isExpensive = expensive
                
                // Автоматическая фоновая синхронизация при возвращении интернета
                if connected && wasDisconnected && !self.isFirstCheck {
                    self.onConnectedAgain?()
                }
                self.isFirstCheck = false
            }
        }
        monitor.start(queue: queue)
    }
}
