//
//  Nothing_X_MacOSTests.swift
//  Nothing X MacOSTests
//
//  Unit tests for model detection (SKUUtil) and the packet checksum (CRC16).
//

import XCTest
@testable import Nothing_X_MacOS

final class ModelDetectionTests: XCTestCase {

    func testCodenameFromDeviceName() {
        let cases: [(String, Codenames)] = [
            ("Nothing ear (1)", .ONE),
            // "buds 2 plus" and "buds 2a" must be checked before "buds 2"
            ("CMF Buds 2 Plus", .GLIGAR),
            ("CMF Buds 2a", .HOOTHOOT),
            ("CMF Buds 2", .GIRAFARIG),
            // "buds pro 2" must be checked before "buds pro"
            ("CMF Buds Pro 2", .ESPEON),
            ("CMF Buds Pro", .CORSOLA),
            ("Nothing Headphone (1)", .ELEKID),
            ("Nothing Ear", .TWOS),
            ("AirPods", .UNKNOWN),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(codenameFromDeviceName(name: name), expected, "device name: \(name)")
        }
    }

    func testSkuFromSerialEmptyIsUnknown() {
        XCTAssertEqual(skuFromSerial(serial: ""), .UNKNOWN)
    }

    func testSkuFromSerialPlaceholderIsUnknown() {
        // The old hardcoded mapping of this fake serial to Ear (1) was removed
        XCTAssertEqual(skuFromSerial(serial: "12345678901234567"), .UNKNOWN)
    }

    func testSkuFromSerialMAUsesYear() {
        // Characters 7-8 are the year: 22 or 23 means Ear (stick), otherwise Ear (open)
        XCTAssertEqual(skuFromSerial(serial: "MA00002212345"), .EAR_STICK_1)
        XCTAssertEqual(skuFromSerial(serial: "MA00002412345"), .FLAFFY_WHITE)
    }

    func testSkuFromSerialSHUsesSkuDigits() {
        // Characters 5-6 are the SKU raw value
        XCTAssertEqual(skuFromSerial(serial: "SH0014ABCDEF"), .EAR_STICK_1)
    }

    func testCodenameFromSKU() {
        XCTAssertEqual(codenameFromSKU(sku: .EAR_1_WHITE), .ONE)
        XCTAssertEqual(codenameFromSKU(sku: .EAR_STICK_1), .STICKS)
        XCTAssertEqual(codenameFromSKU(sku: .GLIGAR_WHITE), .GLIGAR)
        XCTAssertEqual(codenameFromSKU(sku: .UNKNOWN), .UNKNOWN)
    }
}

final class CRC16Tests: XCTestCase {

    func testModbusCheckValue() {
        // Standard CRC-16/MODBUS check value for ASCII "123456789"
        XCTAssertEqual(CRC16.crc16(buffer: Array("123456789".utf8)), 0x4B37)
    }

    func testEmptyBufferReturnsInitialValue() {
        XCTAssertEqual(CRC16.crc16(buffer: []), 0xFFFF)
    }
}
