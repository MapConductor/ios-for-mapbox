import Foundation

final class MapboxRasterLayer {
    let sourceId: String
    let layerId: String

    init(sourceId: String, layerId: String) {
        self.sourceId = sourceId
        self.layerId = layerId
    }
}
