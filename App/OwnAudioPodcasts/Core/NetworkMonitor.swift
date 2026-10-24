import Network
import Observation

/// The phone's network path: whether there is one, whether it costs (mobile data, a hotspot),
/// whether iOS Low Data Mode is on, and a signature that changes whenever the path does —
/// Wi-Fi to mobile data, a VPN coming up — which is when the best address to a server can
/// change. It can't tell a Wi-Fi with no internet from a working one; short request timeouts
/// and the saved answers cover that case.
///
/// The properties follow the path at once; `onChange` waits until the path has been quiet for
/// `debounce`, because a car hands over between cells and Wi-Fi flickers several times in a few
/// seconds, and each call races every server's addresses.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    /// Mobile data or a phone's hotspot: the system's own idea of a connection that costs.
    private(set) var isExpensive = false
    /// iOS Low Data Mode, the listener's phone-wide choice.
    private(set) var isConstrained = false
    /// Changes with every change of path; used to remember which address worked where.
    private(set) var signature = ""
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    /// At once, before the debounce, whenever there comes to be a network or none: a player
    /// streaming into a gap has to know now, not in three seconds.
    @ObservationIgnored var onConnectivity: ((Bool) -> Void)?
    @ObservationIgnored private let monitor: NWPathMonitor?
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pendingChange: Task<Void, Never>?

    /// `monitoring` false for tests, which feed paths in through `pathChanged`.
    init(debounce: Duration = .seconds(3), monitoring: Bool = true) {
        self.debounce = debounce
        monitor = monitoring ? NWPathMonitor() : nil
        monitor?.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let interfaces = path.availableInterfaces.map { "\($0.type)-\($0.name)" }
            Task { @MainActor in
                self?.pathChanged(connected: connected, expensive: expensive, constrained: constrained, interfaces: interfaces)
            }
        }
        monitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    /// Interface names carry the VPN (utun…) as well as Wi-Fi and cellular. Sorted: iOS reorders
    /// the same interfaces by preference now and then, which is no new network.
    nonisolated static func signature(connected: Bool, interfaces: [String]) -> String {
        ([connected ? "up" : "down"] + Set(interfaces).sorted()).joined(separator: ",")
    }

    func pathChanged(connected: Bool, expensive: Bool, constrained: Bool, interfaces: [String]) {
        let signature = Self.signature(connected: connected, interfaces: interfaces)
        guard self.signature != signature || isExpensive != expensive || isConstrained != constrained else { return }
        let flipped = isConnected != connected
        isConnected = connected
        isExpensive = expensive
        isConstrained = constrained
        self.signature = signature
        if flipped { onConnectivity?(connected) }
        pendingChange?.cancel()
        pendingChange = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.onChange?(self.isConnected)
        }
    }
}

/// What the app does once the network has settled on a change.
enum NetworkChangeResponse: Equatable {
    /// Gone: nothing to ask anyone.
    case nothing
    /// In the background: only the positions waiting for a server, after finding which of its
    /// addresses answers on this network (only when there are any to send).
    case sendPositions(chooseAddresses: Bool)
    /// On screen: the addresses again, then a refresh if one is due.
    case full

    static func decide(connected: Bool, inBackground: Bool, hasPendingPositions: Bool) -> Self {
        guard connected else { return .nothing }
        return inBackground ? .sendPositions(chooseAddresses: hasPendingPositions) : .full
    }
}
