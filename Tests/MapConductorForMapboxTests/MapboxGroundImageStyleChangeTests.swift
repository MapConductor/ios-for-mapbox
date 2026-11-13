import MapConductorCore
import MapboxMaps
import UIKit
import XCTest

@testable import MapConductorForMapbox

/**
 A ground image survives the map design changing under it.

 Changing the design calls `loadStyle`, which throws away every source and
 layer added at runtime, so the controller has to put its images back into the
 new style. It used to keep the handle it made for the old style and, seeing an
 unchanged state, skip the image — which then vanished with the old style.

 Checked against a real `MapView` loading real (local, empty) styles: the
 failure is in how the controller meets a reloaded style, and a stub map
 would agree with whatever the controller assumed. Local file styles need no
 network, so a placeholder access token is enough.
 */
@MainActor
final class MapboxGroundImageStyleChangeTests: XCTestCase {
    private var mapView: MapView!
    private var styleURLs: [URL] = []
    private var styleLoaded: AnyCancelable?
    private var loadedExpectation: XCTestExpectation?

    override func setUp() async throws {
        MapboxOptions.accessToken = "pk.placeholder"
        styleURLs = try ["first", "second"].map { name in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mc-groundimage-\(name)-\(UUID().uuidString).json")
            let json = """
            {"version": 8, "name": "\(name)", "sources": {},
             "layers": [{"id": "background", "type": "background"}]}
            """
            try json.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        mapView = MapView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), mapInitOptions: MapInitOptions())
        styleLoaded = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            self?.loadedExpectation?.fulfill()
        }
    }

    override func tearDown() async throws {
        styleLoaded?.cancel()
        styleLoaded = nil
        mapView = nil
        for url in styleURLs { try? FileManager.default.removeItem(at: url) }
    }

    private func load(_ url: URL) async {
        let loaded = expectation(description: "style \(url.lastPathComponent) loaded")
        loadedExpectation = loaded
        mapView.mapboxMap.loadStyle(StyleURI(url: url)!)
        await fulfillment(of: [loaded], timeout: 15)
        loadedExpectation = nil
    }

    private func groundImage(id: String = "tokyo") -> GroundImage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let bounds = GeoRectBounds(
            southWest: GeoPoint(latitude: 35.6, longitude: 139.6, altitude: 0),
            northEast: GeoPoint(latitude: 35.8, longitude: 139.9, altitude: 0)
        )
        return GroundImage(state: GroundImageState(bounds: bounds, image: image, id: id))
    }

    private func hasGroundImage(id: String = "tokyo") -> Bool {
        mapView.mapboxMap.sourceExists(withId: "mc-gimg-src-\(id)")
            && mapView.mapboxMap.layerExists(withId: "mc-gimg-lyr-\(id)")
    }

    func testAnUnchangedGroundImageIsRecreatedInTheNewStyle() async {
        let controller = MapboxGroundImageController(mapView: mapView)
        await load(styleURLs[0])
        controller.onStyleLoaded(mapView.mapboxMap)
        controller.syncGroundImages([groundImage()])
        XCTAssertTrue(hasGroundImage(), "drawn in the first style")

        await load(styleURLs[1])
        XCTAssertFalse(hasGroundImage(), "the design change dropped the runtime layers")
        controller.onStyleLoaded(mapView.mapboxMap)
        XCTAssertTrue(hasGroundImage(), "drawn again in the new style, with nothing about it changed")

        // The host hands the same overlays over again after a reload; that has to
        // leave the image in place rather than treat it as already handled.
        controller.syncGroundImages([groundImage()])
        XCTAssertTrue(hasGroundImage())
        controller.unbind()
    }

    func testTheSameStyleReportedAgainKeepsTheImage() async {
        let controller = MapboxGroundImageController(mapView: mapView)
        await load(styleURLs[0])
        controller.onStyleLoaded(mapView.mapboxMap)
        controller.syncGroundImages([groundImage()])

        controller.onStyleLoaded(mapView.mapboxMap)
        XCTAssertTrue(hasGroundImage(), "a second notice for the same style leaves the image drawn")
        controller.unbind()
    }

    func testAGroundImageRemovedAfterTheChangeLeavesTheNewStyle() async {
        let controller = MapboxGroundImageController(mapView: mapView)
        await load(styleURLs[0])
        controller.onStyleLoaded(mapView.mapboxMap)
        controller.syncGroundImages([groundImage()])

        await load(styleURLs[1])
        controller.onStyleLoaded(mapView.mapboxMap)
        controller.syncGroundImages([])
        XCTAssertFalse(hasGroundImage(), "the recreated image is the one that gets removed")
        controller.unbind()
    }
}
