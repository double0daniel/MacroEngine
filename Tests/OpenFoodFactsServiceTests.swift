import Foundation
import XCTest
@testable import MacroEngine

final class OpenFoodFactsServiceTests: XCTestCase {
    private let query = "macroengine-offline-cache-test"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "macroengine.offline.search.\(query)")
        StubFoodURLProtocol.handler = nil
        super.tearDown()
    }

    func testSearchUsesLiveUKResponseWhenAvailable() async throws {
        StubFoodURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "uk.openfoodfacts.org")
            XCTAssertEqual(request.url?.path, "/cgi/search.pl")
            return (200, Self.productsJSON)
        }
        let result = try await OpenFoodFactsService(session: Self.stubSession()).searchWithStatus(query)

        XCTAssertEqual(result.status, .liveUK)
        XCTAssertEqual(result.foods.first?.name, "Test oats")
    }

    func testSearchUsesCachedResultsWhenBothAPIsAreOffline() async throws {
        StubFoodURLProtocol.handler = { _ in (200, Self.productsJSON) }
        let online = try await OpenFoodFactsService(session: Self.stubSession()).searchWithStatus(query)
        XCTAssertEqual(online.status, .liveUK)

        StubFoodURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = try await OpenFoodFactsService(session: Self.stubSession()).searchWithStatus(query)

        XCTAssertEqual(offline.status, .offlineCache)
        XCTAssertEqual(offline.foods.first?.name, "Test oats")
    }

    private static func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubFoodURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let productsJSON = Data(#"{"products":[{"code":"5000159484695","product_name":"Test oats","nutriments":{"energy-kcal_100g":372,"proteins_100g":13,"carbohydrates_100g":60,"fat_100g":7}}]}"#.utf8)
}

private final class StubFoodURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"] )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
