import Foundation
import Testing

@testable import OwnAudioKit

@Suite("Encoding")
struct EncodingDeterminismTests {
    /// The server keys idempotent requests on the body bytes: the same book must encode to the
    /// same bytes every time, or a retry is refused as "a different request".
    @Test("the same body encodes to the same bytes every time")
    func stableBytes() throws {
        struct Body: Encodable { let positionMs: Int64; let fileId: String; let finished: Bool; let clientUpdatedAt: String; let deviceName: String }
        let book = Body(positionMs: 1234, fileId: "f/1", finished: false, clientUpdatedAt: "2026-10-17T12:00:00Z", deviceName: "iPhone")
        let first = try JSONEncoder.ownAudio.encode(book)
        for _ in 0..<200 {
            let again = try JSONEncoder.ownAudio.encode(book)
            #expect(again == first, "\(String(decoding: first, as: UTF8.self)) vs \(String(decoding: again, as: UTF8.self))")
            if again != first { break }
        }
    }
}
