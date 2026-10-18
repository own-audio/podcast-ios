import StoreKit
import SwiftUI

/// Servers offered to testers: own.audio's canary, where new server versions run first. Shown
/// in TestFlight and development builds only; the App Store build never lists it.
enum TestServers {
    static let canary = "https://api-canary.own.audio"

    static func available() async -> Bool {
        #if DEBUG
        return true
        #else
        // TestFlight installs report the sandbox environment.
        guard let result = try? await AppTransaction.shared, case .verified(let transaction) = result else { return false }
        return transaction.environment == .sandbox
        #endif
    }
}

/// "own.audio canary" as one tap that fills in the address. The caller shows it only where
/// `TestServers.available()` says so: in a Form footer an empty view never appears, so the
/// books app's way of asking from inside the button would never ask.
struct CanaryServerButton: View {
    @Binding var address: String

    var body: some View {
        Button {
            address = TestServers.canary
        } label: {
            Label("own.audio canary (testing)", systemImage: "flask").font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier("addServer.canary")
    }
}
