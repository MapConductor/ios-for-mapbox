import Combine
import CoreLocation
import MapboxMaps
import MapConductorCore
import SwiftUI
import UIKit

/// A container view that only intercepts touches on its subviews (InfoBubbles),
/// allowing touches elsewhere to pass through to the map view below.
private class PassthroughContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView == self ? nil : hitView
    }
}

public struct MapboxMapView: View {
    @ObservedObject private var state: MapboxViewState

    private let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let sdkInitialize: (() -> Void)?
    private let content: () -> MapViewContent

    public init(
        state: MapboxViewState,
        onMapLoaded: OnMapLoadedHandler<MapboxViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        return ZStack {
            MapboxMapViewRepresentable(
                state: state,
                onMapLoaded: onMapLoaded,
                onMapClick: onMapClick,
                onCameraMoveStart: onCameraMoveStart,
                onCameraMove: onCameraMove,
                onCameraMoveEnd: onCameraMoveEnd,
                sdkInitialize: sdkInitialize,
                content: mapContent
            )
            ForEach(0..<mapContent.views.count, id: \.self) { index in
                mapContent.views[index]
            }
        }
    }
}

// MARK: - UIViewRepresentable

private struct MapboxMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: MapboxViewState

    let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
    let onMapClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let sdkInitialize: (() -> Void)?
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd
        )
    }

    func makeUIView(context: Context) -> MapView {
        if let sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }
        let initOptions = MapInitOptions(
            cameraOptions: state.cameraPosition.toMapboxCameraOptions(),
            styleURI: StyleURI(rawValue: state.mapDesignType.styleURI)
        )
        let mapView = MapView(frame: .zero, mapInitOptions: initOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapTap(_:))
        )
        tapGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMarkerLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.2
        mapView.addGestureRecognizer(longPressGesture)

        context.coordinator.attachInfoBubbleContainer(to: mapView)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        context.coordinator.updateContent(content)
        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        let newStyleURI = StyleURI(rawValue: state.mapDesignType.styleURI)
        if let newStyleURI, uiView.mapboxMap.style.uri != newStyleURI {
            uiView.mapboxMap.loadStyle(newStyleURI)
        }
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: MapView, coordinator: Coordinator) {
        coordinator.unbind()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let state: MapboxViewState
        private let onMapLoaded: OnMapLoadedHandler<MapboxViewState>?
        private let onMapClick: OnMapEventHandler?
        private let onCameraMoveStart: OnCameraMoveHandler?
        private let onCameraMove: OnCameraMoveHandler?
        private let onCameraMoveEnd: OnCameraMoveHandler?

        weak var mapView: MapView?
        private var controller: MapboxViewController?
        private var markerController: MapboxMarkerController?
        private var polylineController: MapboxPolylineController?
        private var polygonController: MapboxPolygonController?
        private var circleController: MapboxCircleController?
        private var groundImageController: MapboxGroundImageController?
        private var rasterController: MapboxRasterLayerController?
        private var infoBubbleController: InfoBubbleController?
        private var strategyMarkerController: StrategyMarkerController<
            Feature,
            AnyMarkerRenderingStrategy<Feature>,
            MapboxMarkerRenderer
        >?
        private var strategyMarkerRenderer: MapboxMarkerRenderer?
        private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
        private var strategyMarkerStatesById: [String: MarkerState] = [:]
        private var latestStrategyStates: [MarkerState] = []

        // MapboxMaps Cancelable observers
        private var styleLoadedObserver: (any Cancelable)?
        private var cameraChangedObserver: (any Cancelable)?
        private var cameraIdleObserver: (any Cancelable)?

        private var isStyleLoaded = false
        private var didCallMapLoaded = false
        private let infoBubbleContainer = PassthroughContainerView()

        private static var hasInitializedSdk = false

        static func runOnce(_ initializer: () -> Void) {
            if hasInitializedSdk { return }
            hasInitializedSdk = true
            initializer()
        }

        init(
            state: MapboxViewState,
            onMapLoaded: OnMapLoadedHandler<MapboxViewState>?,
            onMapClick: OnMapEventHandler?,
            onCameraMoveStart: OnCameraMoveHandler?,
            onCameraMove: OnCameraMoveHandler?,
            onCameraMoveEnd: OnCameraMoveHandler?
        ) {
            self.state = state
            self.onMapLoaded = onMapLoaded
            self.onMapClick = onMapClick
            self.onCameraMoveStart = onCameraMoveStart
            self.onCameraMove = onCameraMove
            self.onCameraMoveEnd = onCameraMoveEnd
        }

        func bind(state: MapboxViewState, mapView: MapView) {
            let controller = MapboxViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            state.setMapViewHolder(controller.holder)

            let markerController = MapboxMarkerController(mapView: mapView) { [weak self] id in
                self?.infoBubbleController?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            self.polylineController = MapboxPolylineController(mapView: mapView)
            self.polygonController = MapboxPolygonController(mapView: mapView)
            self.circleController = MapboxCircleController(mapView: mapView)
            self.groundImageController = MapboxGroundImageController(mapView: mapView)
            self.rasterController = MapboxRasterLayerController(mapView: mapView)

            let infoBubbleController = InfoBubbleController(
                mapView: mapView,
                container: infoBubbleContainer,
                markerController: markerController
            )
            self.infoBubbleController = infoBubbleController

            // Subscribe to style loaded
            styleLoadedObserver = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
                self?.handleStyleLoaded(mapView: mapView)
            }

            // Subscribe to camera events
            var isCameraMoving = false
            cameraChangedObserver = mapView.mapboxMap.onCameraChanged.observe { [weak self] event in
                guard let self else { return }
                let camera = event.cameraState.toMapCameraPosition(
                    visibleRegion: self.visibleRegion(mapView: mapView)
                )
                self.state.updateCameraPosition(camera)
                if !isCameraMoving {
                    isCameraMoving = true
                    self.controller?.notifyCameraMoveStart(camera)
                    self.onCameraMoveStart?(camera)
                }
                self.controller?.notifyCameraMove(camera)
                self.onCameraMove?(camera)
                Task { [weak self] in
                    await self?.circleController?.onCameraChanged(mapCameraPosition: camera)
                    await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: camera)
                }
                self.updateInfoBubbleLayouts()
            }

            cameraIdleObserver = mapView.mapboxMap.onMapIdle.observe { [weak self] _ in
                guard let self else { return }
                let camera = mapView.mapboxMap.cameraState.toMapCameraPosition(
                    visibleRegion: self.visibleRegion(mapView: mapView)
                )
                isCameraMoving = false
                self.controller?.notifyCameraMoveEnd(camera)
                self.onCameraMoveEnd?(camera)
                self.updateInfoBubbleLayouts()
            }
        }

        func unbind() {
            state.setController(nil)
            state.setMapViewHolder(nil)
            styleLoadedObserver?.cancel()
            styleLoadedObserver = nil
            cameraChangedObserver?.cancel()
            cameraChangedObserver = nil
            cameraIdleObserver?.cancel()
            cameraIdleObserver = nil
            controller = nil
            markerController?.unbind()
            markerController = nil
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            circleController?.unbind()
            circleController = nil
            groundImageController?.unbind()
            groundImageController = nil
            rasterController?.unbind()
            rasterController = nil
            infoBubbleController?.unbind()
            infoBubbleController = nil
            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            latestStrategyStates.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
            isStyleLoaded = false
        }

        func updateContent(_ content: MapViewContent) {
            infoBubbleController?.syncInfoBubbles(content.infoBubbles)
            markerController?.syncMarkers(content.markers)
            updateStrategyRendering(content)
            groundImageController?.syncGroundImages(content.groundImages)
            rasterController?.syncRasterLayers(content.rasterLayers)
            circleController?.syncCircles(content.circles)
            polylineController?.syncPolylines(content.polylines)
            polygonController?.syncPolygons(content.polygons)
            infoBubbleController?.updateAllLayouts()
        }

        // MARK: - Style loaded

        private func handleStyleLoaded(mapView: MapView) {
            isStyleLoaded = true
            let mapboxMap: MapboxMap = mapView.mapboxMap
            groundImageController?.onStyleLoaded(mapboxMap)
            rasterController?.onStyleLoaded(mapboxMap)
            polygonController?.onStyleLoaded(mapboxMap)
            polylineController?.onStyleLoaded(mapboxMap)
            circleController?.onStyleLoaded(mapboxMap)
            markerController?.onStyleLoaded(mapboxMap)
            strategyMarkerRenderer?.onStyleLoaded(mapboxMap)
            if let strategyMarkerController, !latestStrategyStates.isEmpty {
                Task { [weak self] in
                    guard let self else { return }
                    await strategyMarkerController.onCameraChanged(
                        mapCameraPosition: mapView.mapboxMap.cameraState.toMapCameraPosition()
                    )
                    await strategyMarkerController.add(data: self.latestStrategyStates)
                }
            }
            if !didCallMapLoaded {
                didCallMapLoaded = true
                onMapLoaded?(state)
            }
            updateInfoBubbleLayouts()
        }

        // MARK: - Gestures

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView, recognizer.state == .ended else { return }
            let point = recognizer.location(in: mapView)

            if markerController?.handleTap(at: point) == true {
                updateInfoBubbleLayouts()
                return
            }
            if handleStrategyTap(at: point) {
                updateInfoBubbleLayouts()
                return
            }

            let coordinate = mapView.mapboxMap.coordinate(for: point)
            if circleController?.handleTap(at: coordinate) == true { updateInfoBubbleLayouts(); return }
            if polylineController?.handleTap(at: coordinate) == true { updateInfoBubbleLayouts(); return }
            if polygonController?.handleTap(at: coordinate) == true { updateInfoBubbleLayouts(); return }
            if groundImageController?.handleTap(at: coordinate) == true { updateInfoBubbleLayouts(); return }

            let geoPoint = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(geoPoint)
            onMapClick?(geoPoint)
        }

        @objc func handleMarkerLongPress(_ recognizer: UILongPressGestureRecognizer) {
            markerController?.handleLongPress(recognizer)
            updateInfoBubbleLayouts()
        }

        // MARK: - Helpers

        fileprivate func attachInfoBubbleContainer(to mapView: MapView) {
            guard infoBubbleContainer.superview !== mapView else { return }
            infoBubbleContainer.backgroundColor = .clear
            infoBubbleContainer.isUserInteractionEnabled = true
            infoBubbleContainer.frame = mapView.bounds
            infoBubbleContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            mapView.addSubview(infoBubbleContainer)
        }

        fileprivate func updateInfoBubbleLayouts() {
            infoBubbleController?.updateAllLayouts()
        }

        private func visibleRegion(mapView: MapView) -> VisibleRegion? {
            let bounds = mapView.bounds
            guard !bounds.isEmpty else { return nil }
            let mapboxMap: MapboxMap = mapView.mapboxMap
            let sw = mapboxMap.coordinate(for: CGPoint(x: 0, y: bounds.height))
            let ne = mapboxMap.coordinate(for: CGPoint(x: bounds.width, y: 0))
            let nw = mapboxMap.coordinate(for: CGPoint(x: 0, y: 0))
            let se = mapboxMap.coordinate(for: CGPoint(x: bounds.width, y: bounds.height))
            let geoBounds = GeoRectBounds(
                southWest: GeoPoint(latitude: sw.latitude, longitude: sw.longitude, altitude: 0),
                northEast: GeoPoint(latitude: ne.latitude, longitude: ne.longitude, altitude: 0)
            )
            return VisibleRegion(
                bounds: geoBounds,
                nearLeft: GeoPoint(latitude: se.latitude, longitude: se.longitude, altitude: 0),
                nearRight: GeoPoint(latitude: sw.latitude, longitude: sw.longitude, altitude: 0),
                farLeft: GeoPoint(latitude: ne.latitude, longitude: ne.longitude, altitude: 0),
                farRight: GeoPoint(latitude: nw.latitude, longitude: nw.longitude, altitude: 0)
            )
        }

        // MARK: - Strategy marker rendering

        private func updateStrategyRendering(_ content: MapViewContent) {
            guard let mapView else { return }
            if let strategy = content.markerRenderingStrategy as? AnyMarkerRenderingStrategy<Feature> {
                if strategyMarkerController == nil ||
                    strategyMarkerController?.markerManager !== strategy.markerManager {
                    strategyMarkerRenderer?.unbind()
                    let layer = MarkerLayer(
                        sourceId: "mapconductor-cluster-source-\(UUID().uuidString)",
                        layerId: "mapconductor-cluster-layer-\(UUID().uuidString)"
                    )
                    let renderer = MapboxMarkerRenderer(
                        mapView: mapView,
                        markerManager: strategy.markerManager,
                        markerLayer: layer
                    )
                    strategyMarkerRenderer = renderer
                    let controller = StrategyMarkerController(strategy: strategy, renderer: renderer)
                    strategyMarkerController = controller
                    if isStyleLoaded {
                        renderer.onStyleLoaded(mapView.mapboxMap)
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        await controller.onCameraChanged(
                            mapCameraPosition: mapView.mapboxMap.cameraState.toMapCameraPosition()
                        )
                    }
                }
                syncStrategyMarkers(content.markerRenderingMarkers)
            } else {
                strategyMarkerSubscriptions.values.forEach { $0.cancel() }
                strategyMarkerSubscriptions.removeAll()
                strategyMarkerStatesById.removeAll()
                latestStrategyStates.removeAll()
                strategyMarkerRenderer?.unbind()
                strategyMarkerRenderer = nil
                strategyMarkerController?.destroy()
                strategyMarkerController = nil
            }
        }

        private func syncStrategyMarkers(_ markers: [MarkerState]) {
            guard let controller = strategyMarkerController else { return }
            let newIds = Set(markers.map { $0.id })
            let oldIds = Set(strategyMarkerStatesById.keys)
            var shouldSyncList = newIds != oldIds

            var newStatesById: [String: MarkerState] = [:]
            for state in markers {
                if let existing = strategyMarkerStatesById[state.id], existing !== state {
                    strategyMarkerSubscriptions[state.id]?.cancel()
                    strategyMarkerSubscriptions.removeValue(forKey: state.id)
                    shouldSyncList = true
                }
                newStatesById[state.id] = state
            }
            strategyMarkerStatesById = newStatesById
            latestStrategyStates = markers

            for id in oldIds.subtracting(newIds) {
                strategyMarkerSubscriptions[id]?.cancel()
                strategyMarkerSubscriptions.removeValue(forKey: id)
            }

            if shouldSyncList && isStyleLoaded {
                Task { [weak self] in
                    guard let self else { return }
                    await controller.add(data: markers)
                }
            }

            for state in markers {
                guard strategyMarkerSubscriptions[state.id] == nil else { continue }
                strategyMarkerSubscriptions[state.id] = state.asFlow()
                    .dropFirst()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self, self.strategyMarkerStatesById[state.id] != nil else { return }
                        Task { [weak self] in
                            guard let self else { return }
                            await self.strategyMarkerController?.update(state: state)
                        }
                    }
            }
        }

        private func handleStrategyTap(at point: CGPoint) -> Bool {
            guard let markerId = strategyMarkerRenderer?.markerId(at: point),
                  let state = strategyMarkerController?.markerManager.getEntity(markerId)?.state,
                  state.clickable else { return false }
            strategyMarkerController?.dispatchClick(state)
            return true
        }
    }
}
