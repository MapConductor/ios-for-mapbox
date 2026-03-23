import Foundation
import MapConductorCore

final class MapboxGroundImageHandle {
    let routeId: String
    let version: Int64
    let sourceId: String
    let layerId: String
    let tileProvider: GroundImageTileProvider

    init(
        routeId: String,
        version: Int64,
        sourceId: String,
        layerId: String,
        tileProvider: GroundImageTileProvider
    ) {
        self.routeId = routeId
        self.version = version
        self.sourceId = sourceId
        self.layerId = layerId
        self.tileProvider = tileProvider
    }
}
