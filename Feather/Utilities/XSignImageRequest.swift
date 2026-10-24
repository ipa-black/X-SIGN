import Foundation
import Nuke

enum XSignImageRequest {
    /// ImageIO decodes a bounded thumbnail instead of first decoding the full bitmap.
    static func thumbnail(_ url: URL?, maximumPixelSize: Float = 1200) -> ImageRequest {
        ImageRequest(
            url: url,
            userInfo: [
                .thumbnailKey: ImageRequest.ThumbnailOptions(
                    maxPixelSize: max(64, min(maximumPixelSize, 1600))
                )
            ]
        )
    }
}
