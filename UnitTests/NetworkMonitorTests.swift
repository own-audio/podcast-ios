import Foundation
import Testing
@testable import OwnAudioPodcasts

@MainActor
@Suite("Network changes")
struct NetworkMonitorTests {
    final class Calls { var values: [Bool] = [] }

    private func monitor() -> (NetworkMonitor, Calls) {
        let monitor = NetworkMonitor(debounce: .milliseconds(200), monitoring: false)
        let calls = Calls()
        monitor.onChange = { calls.values.append($0) }
        return (monitor, calls)
    }

    @Test("the same interfaces in another order are the same network")
    func reorder() async throws {
        #expect(NetworkMonitor.signature(connected: true, interfaces: ["wifi-en0", "cellular-pdp_ip0"])
                == NetworkMonitor.signature(connected: true, interfaces: ["cellular-pdp_ip0", "wifi-en0"]))
        let (monitor, calls) = monitor()
        monitor.pathChanged(connected: true, expensive: false, constrained: false, interfaces: ["wifi-en0", "cellular-pdp_ip0"])
        try await Task.sleep(for: .milliseconds(400))
        monitor.pathChanged(connected: true, expensive: false, constrained: false, interfaces: ["cellular-pdp_ip0", "wifi-en0"])
        try await Task.sleep(for: .milliseconds(400))
        #expect(calls.values == [true], "only the first change counts")
    }

    @Test("a burst of changes is one call once the path is quiet, with how it ended")
    func debounce() async throws {
        let (monitor, calls) = monitor()
        monitor.pathChanged(connected: true, expensive: false, constrained: false, interfaces: ["wifi-en0"])
        monitor.pathChanged(connected: false, expensive: false, constrained: false, interfaces: [])
        monitor.pathChanged(connected: true, expensive: true, constrained: false, interfaces: ["cellular-pdp_ip0"])
        #expect(monitor.isExpensive && monitor.isConnected, "the properties follow at once")
        #expect(calls.values.isEmpty, "the call waits")
        try await Task.sleep(for: .milliseconds(500))
        #expect(calls.values == [true])
    }

    @Test("losing the network and getting it back is told at once, before the debounce")
    func connectivityAtOnce() async throws {
        let (monitor, calls) = monitor()
        let flips = Calls()
        monitor.onConnectivity = { flips.values.append($0) }
        monitor.pathChanged(connected: true, expensive: false, constrained: false, interfaces: ["wifi-en0"])
        monitor.pathChanged(connected: true, expensive: true, constrained: false, interfaces: ["cellular-pdp_ip0"])
        #expect(flips.values.isEmpty, "Wi-Fi to mobile data is no loss")
        monitor.pathChanged(connected: false, expensive: false, constrained: false, interfaces: [])
        #expect(flips.values == [false], "at once")
        monitor.pathChanged(connected: true, expensive: true, constrained: false, interfaces: ["cellular-pdp_ip0"])
        #expect(flips.values == [false, true])
        #expect(calls.values.isEmpty, "the debounced call still waits")
        try await Task.sleep(for: .milliseconds(500))
        #expect(calls.values == [true])
    }

    @Test("in the background only waiting positions go out; on screen the full round")
    func response() {
        #expect(NetworkChangeResponse.decide(connected: false, inBackground: false, hasPendingPositions: true) == .nothing)
        #expect(NetworkChangeResponse.decide(connected: true, inBackground: true, hasPendingPositions: true) == .sendPositions(chooseAddresses: true))
        #expect(NetworkChangeResponse.decide(connected: true, inBackground: true, hasPendingPositions: false) == .sendPositions(chooseAddresses: false))
        #expect(NetworkChangeResponse.decide(connected: true, inBackground: false, hasPendingPositions: false) == .full)
    }
}
