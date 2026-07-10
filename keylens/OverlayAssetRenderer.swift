import Foundation
import WebKit

struct OverlaySVGAsset: Equatable {
    let document: String
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
    @MainActor
    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

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

        guard isSafeSVG(svgData, body: svgBody) else {
            return .failure(.unsafeSVGContent)
        }

        return .success(
            .svg(
                OverlaySVGAsset(document: renderDocument(for: svgData))
            )
        )
    }

    private static func renderDocument(for svgData: Data) -> String {
        let source = svgData.base64EncodedString()
        return """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
            <style>
              html, body { margin: 0; width: 100%; height: 100%; background: transparent; }
              body { display: flex; align-items: center; justify-content: center; overflow: hidden; }
              img { max-width: 95vw; max-height: 95vh; }
            </style>
          </head>
          <body><img alt="" src="data:image/svg+xml;base64,\(source)"></body>
        </html>
        """
    }

    private static func isSafeSVG(_ data: Data, body: String) -> Bool {
        let lowercased = body.lowercased()
        guard !lowercased.contains("<!doctype") else {
            return false
        }

        let validator = SVGXMLValidator()
        let parser = XMLParser(data: data)
        parser.delegate = validator
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        return parser.parse() && validator.rootElement == "svg" && validator.isSafe
    }
}

private final class SVGXMLValidator: NSObject, XMLParserDelegate {
    private static let blockedElements: Set<String> = [
        "animate", "animatecolor", "animatemotion", "animatetransform", "audio", "body",
        "canvas", "discard", "embed", "foreignobject", "html", "iframe", "image", "object",
        "script", "set", "video"
    ]
    private static let cssComments = try! NSRegularExpression(pattern: #"/\*[\s\S]*?\*/"#)
    private static let cssURLs = try! NSRegularExpression(
        pattern: #"\burl\s*\(([^)]*)\)"#,
        options: .caseInsensitive
    )

    private(set) var rootElement: String?
    private(set) var isSafe = true
    private var styleDepth = 0
    private var styleContent = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if rootElement == nil {
            rootElement = elementName.lowercased()
        }

        let normalizedElement = elementName.lowercased()
        if Self.blockedElements.contains(normalizedElement) {
            isSafe = false
        }

        if normalizedElement == "style" {
            if styleDepth > 0 { isSafe = false }
            styleDepth += 1
            if styleDepth == 1 { styleContent = "" }
        }

        for (attributeName, value) in attributeDict {
            let normalizedAttribute = String(
                attributeName.lowercased().split(separator: ":").last ?? ""
            )
            if normalizedAttribute.hasPrefix("on") || normalizedAttribute == "base" {
                isSafe = false
            }
            if ["href", "src"].contains(normalizedAttribute), !Self.isFragmentReference(value) {
                isSafe = false
            }
            if Self.hasUnsafeCSSReference(value) {
                isSafe = false
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleDepth > 0 {
            styleContent += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "style", styleDepth > 0 else { return }
        styleDepth -= 1
        if styleDepth == 0, Self.hasUnsafeCSSReference(styleContent) {
            isSafe = false
        }
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        isSafe = false
    }

    private static func isFragmentReference(_ value: String) -> Bool {
        let reference = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return reference.isEmpty || reference.hasPrefix("#")
    }

    private static func hasUnsafeCSSReference(_ value: String) -> Bool {
        guard !value.contains("\\") else { return true }

        let fullRange = NSRange(value.startIndex..., in: value)
        let normalized = cssComments.stringByReplacingMatches(
            in: value,
            range: fullRange,
            withTemplate: ""
        )
        if normalized.range(of: "@import", options: .caseInsensitive) != nil {
            return true
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        return cssURLs.matches(in: normalized, range: range).contains { match in
            guard let matchRange = Range(match.range(at: 1), in: normalized) else { return true }
            let reference = normalized[matchRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return !isFragmentReference(reference)
        }
    }
}
