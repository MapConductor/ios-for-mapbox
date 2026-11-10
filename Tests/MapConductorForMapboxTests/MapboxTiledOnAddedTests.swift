@_spi(MapConductorDriver) import MapConductorCore
import MapboxMaps
import UIKit
import XCTest

@testable import MapConductorForMapbox

/**
 Overlays drawn as raster tiles report `onAdded` only once their tile layer is
 in the style the map shows.

 Without a loaded style (the first one still loading, or a new map design
 replacing it) a layer added now does not stay: it goes on in
 `onStyleLoaded`. Markers tiled and polygon tiles upserted in that window used
 to report `onAdded` right away, so an app hiding its loading screen on
 `onAdded` showed an empty map.

 Checked against a real `MapView` loading real (local, empty) styles, since
 the question is when `MapboxMap.isStyleLoaded` holds.
 */
@MainActor
final class MapboxTiledOnAddedTests: XCTestCase {
    private var mapView: MapView!
    private var styleURLs: [URL] = []
    private var styleLoaded: AnyCancelable?
    private var loads = 0
    /// Hands the style over inside the style-loaded event, as `MapboxMapHost` does.
    private var onLoad: ((MapboxMap) -> Void)?
    /// Tells the controller a new design is loading, as `MapboxMapHost` does
    /// right before `loadStyle`.
    private var onLoading: (() -> Void)?

    override func setUp() async throws {
        MapboxOptions.accessToken = "pk.placeholder"
        styleURLs = try ["first", "second"].map { name in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mc-onadded-\(name)-\(UUID().uuidString).json")
            let json = """
            {"version": 8, "name": "\(name)", "sources": {},
             "layers": [{"id": "background", "type": "background"}]}
            """
            try json.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        loads = 0
        onLoad = nil
        mapView = MapView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), mapInitOptions: MapInitOptions())
        styleLoaded = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            guard let self else { return }
            self.loads += 1
            self.onLoad?(self.mapView.mapboxMap)
        }
    }

    override func tearDown() async throws {
        styleLoaded?.cancel()
        styleLoaded = nil
        onLoad = nil
        onLoading = nil
        mapView = nil
        for url in styleURLs { try? FileManager.default.removeItem(at: url) }
    }

    private func load(_ url: URL) async {
        let loadsBefore = loads
        mapView.mapboxMap.loadStyle(StyleURI(url: url)!)
        for _ in 0..<1500 where loads == loadsBefore {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(loads, loadsBefore, "style loaded")
    }

    /// Puts the map in the state it is in while a new design loads and keeps
    /// it there: the address never answers.
    private func startLoadingANewDesignThatHangs() {
        onLoading?()
        mapView.mapboxMap.loadStyle(StyleURI(rawValue: "http://127.0.0.1:1/never.json")!)
        XCTAssertFalse(mapView.mapboxMap.isStyleLoaded, "no style while the new design loads")
    }

    /// Lets queued main-actor tasks run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func hasLayer(prefix: String) -> Bool {
        mapView.mapboxMap.allLayerIdentifiers.contains { $0.id.hasPrefix(prefix) }
    }

    private func markers(_ count: Int, onAdded: @escaping OnMarkerEventHandler) -> [MarkerState] {
        (0..<count).map { i in
            MarkerState(
                position: GeoPoint(latitude: 35.6 + Double(i) * 0.001, longitude: 139.7, altitude: 0),
                id: "m\(i)",
                onAdded: onAdded
            )
        }
    }

    func testMarkersTiledWhileANewDesignLoadsWaitForTheirTileLayer() async {
        let controller = MapboxMarkerController(mapView: mapView) { _ in }
        controller.tilingOptions = MarkerTilingOptions(minMarkerCount: 1)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        await load(styleURLs[0])

        var added: [String] = []
        startLoadingANewDesignThatHangs()

        await controller.add(data: markers(3, onAdded: { added.append($0.id) }))
        await settle()
        XCTAssertEqual(added, [], "the tile layer is not on the map yet")

        await load(styleURLs[1])
        await settle()
        XCTAssertTrue(hasLayer(prefix: "mapconductor-tile-markers-layer-"), "tile layer in the new style")
        XCTAssertEqual(added.sorted(), ["m0", "m1", "m2"], "reported once the layer went on")

        // Another style load does not report them again.
        await load(styleURLs[0])
        await settle()
        XCTAssertEqual(added.count, 3)
        controller.unbind()
    }

    func testMarkersTiledBeforeTheFirstStyleWaitForTheirTileLayer() async {
        let controller = MapboxMarkerController(mapView: mapView) { _ in }
        controller.tilingOptions = MarkerTilingOptions(minMarkerCount: 1)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }

        var added: [String] = []
        await controller.add(data: markers(3, onAdded: { added.append($0.id) }))
        await settle()
        XCTAssertEqual(added, [], "no style, so no tile layer yet")

        await load(styleURLs[0])
        await settle()
        XCTAssertTrue(hasLayer(prefix: "mapconductor-tile-markers-layer-"))
        XCTAssertEqual(added.sorted(), ["m0", "m1", "m2"])
        controller.unbind()
    }

    func testMarkersRemovedBeforeTheStyleLoadsAreNotReported() async {
        let controller = MapboxMarkerController(mapView: mapView) { _ in }
        controller.tilingOptions = MarkerTilingOptions(minMarkerCount: 1)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        await load(styleURLs[0])

        var added: [String] = []
        startLoadingANewDesignThatHangs()
        await controller.add(data: markers(3, onAdded: { added.append($0.id) }))
        // The app emptied the list while the style loaded.
        await controller.add(data: [])

        await load(styleURLs[1])
        await settle()
        XCTAssertEqual(added, [])
        controller.unbind()
    }

    func testMarkersTiledWithTheStyleShowingAreReportedRightAway() async {
        let controller = MapboxMarkerController(mapView: mapView) { _ in }
        controller.tilingOptions = MarkerTilingOptions(minMarkerCount: 1)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        await load(styleURLs[0])

        var added: [String] = []
        await controller.add(data: markers(2, onAdded: { added.append($0.id) }))
        await settle()
        XCTAssertTrue(hasLayer(prefix: "mapconductor-tile-markers-layer-"))
        XCTAssertEqual(added.sorted(), ["m0", "m1"])
        controller.unbind()
    }

    func testPolygonTilesUpsertedBeforeTheFirstStyleReturnOnceTheLayerIsOn() async {
        let controller = MapboxRasterLayerController(mapView: mapView)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        var returned = false
        Task {
            await controller.upsert(state: PolygonTiler.rasterLayerState(template: "http://127.0.0.1:1/{z}/{x}/{y}.png"))
            returned = true
        }
        await settle()
        XCTAssertFalse(returned, "no style to put the layer in yet")

        await load(styleURLs[0])
        await settle()
        XCTAssertTrue(returned)
        XCTAssertTrue(hasLayer(prefix: "mapconductor-raster-layer-\(PolygonTiler.layerId)"))
        controller.unbind()
    }

    func testPolygonTilesUpsertedWhileANewDesignLoadsReturnOnceTheLayerIsOn() async {
        let controller = MapboxRasterLayerController(mapView: mapView)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        await load(styleURLs[0])

        startLoadingANewDesignThatHangs()
        var returned = false
        Task {
            await controller.upsert(state: PolygonTiler.rasterLayerState(template: "http://127.0.0.1:1/{z}/{x}/{y}.png"))
            returned = true
        }
        await settle()
        XCTAssertFalse(returned, "the layer was dropped with the outgoing style")

        await load(styleURLs[1])
        await settle()
        XCTAssertTrue(returned)
        XCTAssertTrue(hasLayer(prefix: "mapconductor-raster-layer-\(PolygonTiler.layerId)"))

        // With the style showing, an upsert returns straight away.
        await controller.upsert(state: PolygonTiler.rasterLayerState(template: "http://127.0.0.1:1/v2/{z}/{x}/{y}.png"))
        controller.unbind()
    }

    func testUnbindReleasesAWaitingUpsert() async {
        let controller = MapboxRasterLayerController(mapView: mapView)
        onLoad = { controller.onStyleLoaded($0) }
        onLoading = { controller.onStyleLoading() }
        var returned = false
        Task {
            await controller.upsert(state: PolygonTiler.rasterLayerState(template: "http://127.0.0.1:1/{z}/{x}/{y}.png"))
            returned = true
        }
        await settle()
        controller.unbind()
        await settle()
        XCTAssertTrue(returned)
    }
}
