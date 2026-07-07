import Foundation

final class MapboxGroundImageHandle {
    let sourceId: String
    let layerId: String
    let applied: AppliedGroundImage

    init(
        sourceId: String,
        layerId: String,
        applied: AppliedGroundImage
    ) {
        self.sourceId = sourceId
        self.layerId = layerId
        self.applied = applied
    }

    func copy(applied: AppliedGroundImage? = nil) -> MapboxGroundImageHandle {
        MapboxGroundImageHandle(
            sourceId: sourceId,
            layerId: layerId,
            applied: applied ?? self.applied
        )
    }
}

struct AppliedGroundImage: Equatable {
    let bounds: Int
    let image: Int
    let opacity: Int
}
