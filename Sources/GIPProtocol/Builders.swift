import Foundation

// MS-GIPUSB power message: mode 0x00 = on.
private let powerModeOn: UInt8 = 0x00
// LED payload as used for every Xbox One device: reserved, mode "on", brightness.
private let ledReserved: UInt8 = 0x00
private let ledModeOn: UInt8 = 0x01
private let ledBrightnessDefault: UInt8 = 0x14
// Tells the device the console finished authentication.
private let authenticationComplete = Data([0x01, 0x00])
// PlasticBand "6-Fret Guitar/Xbox One.md": sub-command 0x02, must go out every 8 s for input to flow.
private let ghlKeepAlivePayload = Data([0x02, 0x08, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00])
// PlasticBand: the keep-alive always uses sequence 0.
private let ghlKeepAliveSequence: UInt8 = 0x00
// MS-GIPUSB acknowledge message: reserved, command, options, length (LE16), padding (LE16), remaining (LE16).
private let acknowledgeReserved: UInt8 = 0x00
private let acknowledgePadding: UInt16 = 0x0000
private let acknowledgeBytesRemaining: UInt16 = 0x0000

extension GipPacket {
    public static func powerOn(sequence: UInt8) -> GipPacket {
        GipPacket(command: .power, flags: .system, sequence: sequence, payload: Data([powerModeOn]))
    }

    public static func ledOn(sequence: UInt8) -> GipPacket {
        let payload = Data([ledReserved, ledModeOn, ledBrightnessDefault])
        return GipPacket(command: .led, flags: .system, sequence: sequence, payload: payload)
    }

    public static func authenticationDone(sequence: UInt8) -> GipPacket {
        GipPacket(command: .authenticate, flags: .system, sequence: sequence, payload: authenticationComplete)
    }

    public static func ghlKeepAlive() -> GipPacket {
        GipPacket(command: .ghlOutput, flags: [], sequence: ghlKeepAliveSequence, payload: ghlKeepAlivePayload)
    }

    /// Acknowledges this packet, echoing its sequence and client id.
    public func acknowledgement() -> GipPacket {
        let options = (flags.intersection(.system)).rawValue | flags.clientID
        var payload = Data([acknowledgeReserved, command, options])
        payload.append(littleEndian: UInt16(truncatingIfNeeded: self.payload.count))
        payload.append(littleEndian: acknowledgePadding)
        payload.append(littleEndian: acknowledgeBytesRemaining)
        let replyFlags = GipFlags.system.union(GipFlags(rawValue: flags.clientID))
        return GipPacket(command: .acknowledge, flags: replyFlags, sequence: sequence, payload: payload)
    }
}

extension Data {
    fileprivate mutating func append(littleEndian value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }
}
