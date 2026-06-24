import Foundation

struct OverlaySVGAsset: Equatable {
    let body: String
    let baseURL: URL
}

enum OverlayAsset: Equatable {
    case imageFile(URL)
    case svg(OverlaySVGAsset)
}

enum OverlayAssetLoadError: Error, Equatable {
    case missingOrUnreadable
    case unsafeSVGContent
}

enum OverlayAssetRenderer {
    static func loadAsset(at localPath: String) -> Result<OverlayAsset, OverlayAssetLoadError> {
        let url = URL(fileURLWithPath: localPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.missingOrUnreadable)
        }

        if localPath.lowercased().hasSuffix(".svg") {
            return loadSVG(at: url)
        }

        return .success(.imageFile(url))
    }

    private static func loadSVG(at url: URL) -> Result<OverlayAsset, OverlayAssetLoadError> {
        guard let svgData = try? Data(contentsOf: url),
              let svgBody = String(data: svgData, encoding: .utf8) else {
            return .failure(.missingOrUnreadable)
        }

        guard isSafeSVG(svgBody) else {
            return .failure(.unsafeSVGContent)
        }

        return .success(
            .svg(
                OverlaySVGAsset(
                    body: svgBody,
                    baseURL: url.deletingLastPathComponent()
                )
            )
        )
    }

    private static func isSafeSVG(_ body: String) -> Bool {
        let lowercased = body.lowercased()
        let blockedFragments = [
            "<script",
            "javascript:",
            "onload=",
            "onclick=",
            "onerror=",
            "<foreignobject"
        ]

        return !blockedFragments.contains { lowercased.contains($0) }
    }
}
