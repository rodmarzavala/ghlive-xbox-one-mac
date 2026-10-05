import Foundation
import Testing

@testable import GIPProtocol

@Suite("Hex string")
struct HexStringTests {
    @Test("formats bytes as space-separated lowercase hex")
    func formats() {
        #expect(Data([0x21, 0x00, 0x4B, 0xFF]).hexString == "21 00 4b ff")
        #expect(Data().hexString == "")
    }
}
