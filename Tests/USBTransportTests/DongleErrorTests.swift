import Foundation
import IOKit
import Testing

@testable import USBTransport

@Suite("Dongle errors")
struct DongleErrorTests {
    @Test("exclusive access maps to the busy error with the Steam hint")
    func exclusiveAccess() {
        let error = DongleError.from(kIOReturnExclusiveAccess, operation: "open")
        #expect(error == .exclusiveAccess)
        #expect(error.errorDescription?.contains("Steam") == true)
    }

    @Test(
        "device-gone statuses map to disconnected",
        arguments: [kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotResponding, kIOReturnAborted]
    )
    func goneStatuses(status: IOReturn) {
        #expect(DongleError.from(status, operation: "read") == .disconnected)
    }

    @Test("other statuses keep the operation and the code")
    func otherStatus() {
        let error = DongleError.from(kIOReturnBadArgument, operation: "write")
        #expect(error == .ioFailure(operation: "write", code: kIOReturnBadArgument))
        #expect(error.errorDescription?.contains("write") == true)
        #expect(error.errorDescription?.contains("e00002c2") == true)
    }

    @Test("an NSError is mapped through its IOReturn code")
    func nsErrorMapping() {
        let error = NSError(domain: NSMachErrorDomain, code: Int(kIOReturnExclusiveAccess))
        #expect(DongleError.from(error, operation: "open") == .exclusiveAccess)
    }

    @Test("a DongleError passes through unchanged")
    func passthrough() {
        #expect(DongleError.from(DongleError.noGipInterface, operation: "open") == .noGipInterface)
    }

    @Test("every error has a readable description")
    func descriptions() {
        #expect(DongleError.notFound.errorDescription?.contains("plugged in") == true)
        #expect(DongleError.noGipInterface.errorDescription?.contains("GIP") == true)
        #expect(DongleError.disconnected.errorDescription?.contains("disconnected") == true)
    }
}

@Suite("Dongle identity")
struct DongleIdentityTests {
    @Test("the matching dictionary targets the dongle's USB host device")
    func matchingDictionary() {
        let matching = DongleIdentity.matchingDictionary()
        #expect(matching["IOProviderClass"] as? String == "IOUSBHostDevice")
        #expect(matching["idVendor"] as? Int == 0x1430)
        #expect(matching["idProduct"] as? Int == 0x079B)
    }
}
