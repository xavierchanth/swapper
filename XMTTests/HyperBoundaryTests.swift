import Foundation
import XCTest

final class HyperBoundaryTests: XCTestCase {
    func testParsesRealHidutilOpenStepNumbersAndNull() throws {
        let output = """
        RegistryID  Key                   Value
        100000b46   UserKeyMapping   (
            {
                HIDKeyboardModifierMappingDst = 30064771299;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        XCTAssertEqual(try HyperMappingFormat.parse(Data(output.utf8)), [[HyperMappingFormat.source: 30064771129, HyperMappingFormat.destination: 30064771299]])
        XCTAssertEqual(try HyperMappingFormat.parse(Data("RegistryID Key Value\n123 UserKeyMapping (null)\n".utf8)), [])
        XCTAssertThrowsError(try HyperMappingFormat.parse(Data()))
        XCTAssertThrowsError(try HyperMappingFormat.parse(Data((output + output).utf8)))
    }

    func testDiscoveryRequiresUniqueBuiltInServiceNotOnlyDevice() throws {
        let service = #"{"type":"service","Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6,"Product":"Internal","LocationID":230,"IORegistryEntryID":123}"#
        let device = #"{"type":"device","Built-In":true,"PrimaryUsagePage":1,"PrimaryUsage":6}"#
        let external = #"{"type":"service","PrimaryUsagePage":1,"PrimaryUsage":6,"Product":"Voyager"}"#
        let selected = try HyperBuiltInKeyboardDiscovery.parse(Data([service, device, external].joined(separator: "\n").utf8))
        XCTAssertEqual(selected.id, "builtin-123")
        XCTAssertTrue(selected.matchingJSON.contains("PrimaryUsage"))
        XCTAssertThrowsError(try HyperBuiltInKeyboardDiscovery.parse(Data(device.utf8)))
        XCTAssertThrowsError(try HyperBuiltInKeyboardDiscovery.parse(Data([service, service].joined(separator: "\n").utf8)))
    }

    func testGuardianDistinguishesDisarmFromOwnerPipeEOF() throws {
        let graceful = Pipe()
        try graceful.fileHandleForWriting.write(contentsOf: Data([HyperGuardianProtocol.disarmByte]))
        XCTAssertEqual(try HyperGuardianProtocol.readByte(from: graceful.fileHandleForReading.fileDescriptor, timeoutMilliseconds: 100), HyperGuardianProtocol.disarmByte)
        try graceful.fileHandleForWriting.close()
        XCTAssertNil(try HyperGuardianProtocol.readByte(from: graceful.fileHandleForReading.fileDescriptor, timeoutMilliseconds: 100))
        let orphaned = Pipe()
        try orphaned.fileHandleForWriting.close()
        XCTAssertNil(try HyperGuardianProtocol.readByte(from: orphaned.fileHandleForReading.fileDescriptor, timeoutMilliseconds: 100))
        let stalled = Pipe()
        XCTAssertThrowsError(try HyperGuardianProtocol.readByte(from: stalled.fileHandleForReading.fileDescriptor, timeoutMilliseconds: 1))
    }

    func testSubprocessCapturesOutputAndBoundsAStall() throws {
        XCTAssertEqual(try HyperProcess.runSync("/usr/bin/printf", ["hello"]), Data("hello".utf8))
        XCTAssertThrowsError(try HyperProcess.runSync("/bin/sleep", ["5"], timeout: 0.02))
    }
}
