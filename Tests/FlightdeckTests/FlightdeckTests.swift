import XCTest
@testable import Flightdeck

final class FlightdeckTests: XCTestCase {
    func testInitialization() throws {
        Flightdeck.initialize(projectId: "t1234567890", projectToken: "p1a2b3c4d5e6f7g8h9i0j")
        XCTAssertNotNil(Flightdeck.shared)
    }
    
    func testTrackEvent() throws {
        XCTAssertNotNil(Flightdeck.shared.trackEvent("Test"))
        
        XCTAssertNotNil(Flightdeck.shared.trackEvent("Test", properties: [
            "string": "value1",
            "number": 12,
            "array": ["string", "array", 1234] as [Any]
        ]
        ))
    }
    
    func testSuperProperties() throws {
        XCTAssertNotNil(Flightdeck.shared.setSuperProperties(["super" : "super value"]))
        XCTAssertNotNil(Flightdeck.shared.trackEvent("Test with super props"))
    }
}
