import Foundation
import Network

struct DiscoveredDesktop: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var host: String?
    var port: Int?

    var isResolved: Bool { host != nil && port != nil && port! > 0 }

    static func == (lhs: DiscoveredDesktop, rhs: DiscoveredDesktop) -> Bool {
        lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port
    }
}

class DesktopDiscovery: NSObject, ObservableObject {
    @Published var desktops: [DiscoveredDesktop] = []
    @Published var isSearching = false

    private var browser: NWBrowser?
    private var resolvers: [String: NetService] = [:]

    func startSearching() {
        guard browser == nil else { return }
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_screenshottool._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }

                var updated: [DiscoveredDesktop] = []
                for result in results {
                    if case .service(let name, let type, let domain, _) = result.endpoint {
                        let desktop = DiscoveredDesktop(name: name)
                        updated.append(desktop)

                        // Always re-resolve to pick up port changes (e.g. desktop restart)
                        self.resolvers[name]?.stop()
                        self.resolvers.removeValue(forKey: name)
                        self.resolveService(name: name, type: type, domain: domain)
                    }
                }
                self.desktops = updated
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed, .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser?.start(queue: .main)
    }

    private func resolveService(name: String, type: String, domain: String) {
        guard resolvers[name] == nil else { return }

        let service = NetService(domain: domain, type: type, name: name)
        service.delegate = self
        service.resolve(withTimeout: 10.0)
        resolvers[name] = service
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        resolvers.removeAll()
        isSearching = false
    }

    deinit {
        stopSearching()
    }
}

extension DesktopDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = sender.port
        let name = sender.name

        // Extract IPv4 address from resolved addresses
        var hostString: String?
        if let addresses = sender.addresses {
            for addressData in addresses {
                var storage = sockaddr_storage()
                (addressData as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)

                if storage.ss_family == sa_family_t(AF_INET) {
                    var addr = withUnsafePointer(to: &storage) {
                        $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    }
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                    hostString = String(cString: buffer)
                    break
                }
            }
        }

        // Fallback to hostname (strip trailing dot)
        if hostString == nil, let hostName = sender.hostName {
            hostString = hostName.hasSuffix(".") ? String(hostName.dropLast()) : hostName
        }

        guard let host = hostString else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.desktops.firstIndex(where: { $0.name == name }) {
                self.desktops[index].host = host
                self.desktops[index].port = port
            }
        }

        resolvers.removeValue(forKey: name)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("Failed to resolve service \(sender.name): \(errorDict)")
        resolvers.removeValue(forKey: sender.name)
    }
}
