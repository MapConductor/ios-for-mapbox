import Combine
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxGroundImageController {
    private let renderer: MapboxGroundImageOverlayRenderer
    private let groundImageManager: GroundImageManager<MapboxGroundImageHandle>

    private var groundImageSubscriptions: [String: AnyCancellable] = [:]
    private var groundImageStatesById: [String: GroundImageState] = [:]
    /// スタイル読み込み待ちの取り込み。捨てずに保留し、`onStyleLoaded` で流す。
    /// 「なぜ待つ必要があるか」は `DeferredUntilReady` の説明にある。
    private lazy var styleGate = DeferredUntilReady<[GroundImageState]> { [weak self] states in
        self?.syncDirectly(states)
    }

    init(mapView: MapView?) {
        self.groundImageManager = GroundImageManager<MapboxGroundImageHandle>()
        self.renderer = MapboxGroundImageOverlayRenderer(mapView: mapView)
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        renderer.onStyleLoaded(mapboxMap)
        styleGate.markReady()
    }

    func syncGroundImages(_ groundImages: [GroundImage]) {
        let newIds = Set(groundImages.map { $0.id })
        let oldIds = Set(groundImageStatesById.keys)
        var newStatesById: [String: GroundImageState] = [:]
        var shouldSync = false

        for groundImage in groundImages {
            let state = groundImage.state
            if let existing = groundImageStatesById[state.id], existing !== state {
                groundImageSubscriptions[state.id]?.cancel()
                groundImageSubscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !groundImageManager.hasEntity(state.id) { shouldSync = true }
        }

        groundImageStatesById = newStatesById
        if oldIds != newIds { shouldSync = true }

        for groundImage in groundImages { subscribeToGroundImage(groundImage.state) }

        for id in oldIds.subtracting(newIds) {
            groundImageSubscriptions[id]?.cancel()
            groundImageSubscriptions.removeValue(forKey: id)
        }

        // 準備前は「適用せずに最新を覚える」だけ。準備後は変化があったときだけ流す。
        if !styleGate.isReady || shouldSync {
            styleGate.submit(groundImages.map { $0.state })
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let entity = groundImageManager.find(position: position) else { return false }
        // 配送座標の wrap は GroundImageEvent の生成時に一元化済み。
        let event = GroundImageEvent(state: entity.state, clicked: position)
        entity.state.onClick?(event)
        return true
    }

    private func syncDirectly(_ states: [GroundImageState]) {
        let previous = Set(groundImageManager.allEntities().map { $0.state.id })
        let newIds = Set(states.map { $0.id })

        for id in previous.subtracting(newIds) {
            if let entity = groundImageManager.getEntity(id) {
                renderer.removeGroundImageSync(entity: entity)
                _ = groundImageManager.removeEntity(id)
            }
        }

        for state in states {
            if let prevEntity = groundImageManager.getEntity(state.id) {
                if prevEntity.fingerPrint != state.fingerPrint() {
                    if let handle = renderer.updateGroundImageSync(
                        groundImage: prevEntity.groundImage!,
                        current: GroundImageEntity(groundImage: prevEntity.groundImage, state: state),
                        prev: prevEntity
                    ) {
                        groundImageManager.registerEntity(GroundImageEntity(groundImage: handle, state: state))
                    }
                }
            } else {
                if let handle = renderer.createGroundImageSync(state: state) {
                    groundImageManager.registerEntity(GroundImageEntity(groundImage: handle, state: state))
                }
            }
        }
    }

    private func subscribeToGroundImage(_ state: GroundImageState) {
        guard groundImageSubscriptions[state.id] == nil else { return }
        groundImageSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.groundImageStatesById[state.id] != nil,
                      self.styleGate.isReady, let latest = self.styleGate.latest else { return }
                self.syncDirectly(latest)
            }
    }

    func unbind() {
        groundImageSubscriptions.values.forEach { $0.cancel() }
        groundImageSubscriptions.removeAll()
        groundImageStatesById.removeAll()
        styleGate.reset()
        renderer.unbind()
        groundImageManager.destroy()
    }
}
