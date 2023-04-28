#if os(macOS)

import SwiftConvenience
import SwiftConvenienceTestUtils

import Foundation
import XCTest

class ProcessInfoTests: XCTestCase {
    func test_signingInfo() throws {
        let info = try ProcessInfo.processInfo.signingInfo()
        XCTAssertFalse(info.isEmpty)
        XCTAssertEqual(info[kSecCodeInfoIdentifier as String] as? String, "com.apple.xctest")
    }
}

#endif
