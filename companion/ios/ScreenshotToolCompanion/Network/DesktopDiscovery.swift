import Foundation
import Network

struct DiscoveredDesktop: Identifiable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int
}

class DesktopDiscovery: ObservableObject {
    @Published var desktops: [DiscoveredDesktop] = []
    @Published var isSearching = false

    private var browser: NWBrowser?

    func startSearching() {
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_screenshottool._tcp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.desktops = results.compactMap { result -> DiscoveredDesktop? in
                    switch result.endpoint {
                    case .service(let name, let type, let domain, _):
                        return DiscoveredDesktop(
                            name: name,
                            host: "\(name).\(domain)",
                            port: 0 // Resolved during connection
                        )
                    default:
                        return nil
                    }
                }
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

    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    deinit {
        stopSearching()
    }
}
