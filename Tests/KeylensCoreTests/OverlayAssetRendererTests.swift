import Foundation
import Testing
@testable import KeylensCore

@Suite
struct OverlayAssetRendererTests {
    @Test
    func safeSVGReturnsCompleteProtectedRenderDocument() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let svg = directory.appendingPathComponent("safe.svg")
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>"#.utf8)
            .write(to: svg)

        guard case .success(.svg(let asset)) = OverlayAssetRenderer.loadAsset(at: svg.path) else {
            Issue.record("Safe SVG should load")
            return
        }

        #expect(asset.document.contains("Content-Security-Policy"))
        #expect(asset.document.contains("data:image/svg+xml;base64,"))
        #expect(!asset.document.contains("<rect"))
    }

    @Test @MainActor
    func rendererWebViewDisablesJavaScriptAndPersistentStorage() {
        let webView = OverlayAssetRenderer.makeWebView()

        #expect(!webView.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(!webView.configuration.websiteDataStore.isPersistent)
    }

    @Test
    func malformedWrongRootDoctypeAndNonUTF8SVGsFailClosed() throws {
        let malformed = Data("<svg><rect></svg>".utf8)
        let wrongRoot = Data("<html></html>".utf8)
        let doctype = Data(#"<!DOCTYPE svg [<!ENTITY x SYSTEM "file:///etc/passwd">]><svg>&x;</svg>"#.utf8)
        let nonUTF8 = Data([0xff, 0xfe, 0xfd])

        #expect(try load(malformed) == .failure(.unsafeSVGContent))
        #expect(try load(wrongRoot) == .failure(.unsafeSVGContent))
        #expect(try load(doctype) == .failure(.unsafeSVGContent))
        #expect(try load(nonUTF8) == .failure(.missingOrUnreadable))
    }

    @Test
    func activeElementsEventHandlersAndProcessingInstructionsFailClosed() throws {
        let fixtures = [
            #"<svg><ScRiPt>alert(1)</ScRiPt></svg>"#,
            #"<svg><foreignObject><html/></foreignObject></svg>"#,
            #"<svg><iframe/></svg>"#,
            #"<svg><object/></svg>"#,
            #"<svg><embed/></svg>"#,
            #"<svg><audio/></svg>"#,
            #"<svg><video/></svg>"#,
            #"<svg><canvas/></svg>"#,
            #"<svg><image/></svg>"#,
            #"<svg OnMouseOver = "doThing()"><rect/></svg>"#,
            #"<?xml-stylesheet href="evil.css"?><svg/>"#
        ]

        for fixture in fixtures {
            #expect(try load(Data(fixture.utf8)) == .failure(.unsafeSVGContent), "Accepted: \(fixture)")
        }
    }

    @Test
    func externalReferencesAndImportedCSSFailClosed() throws {
        let fixtures = [
            #"<svg><use href="https://example.com/key.svg#key"/></svg>"#,
            #"<svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="../key.svg#key"/></svg>"#,
            #"<svg><a href="file:///etc/passwd"><path/></a></svg>"#,
            #"<svg><use href="data:image/svg+xml;base64,PHN2Zy8+"/></svg>"#,
            #"<svg><feImage src="/tmp/key.png"/></svg>"#,
            #"<svg xml:base="https://example.com/"><path/></svg>"#,
            #"<svg><rect fill="url(https://example.com/paint.svg#gradient)"/></svg>"#,
            #"<svg><rect style="filter: URL( '../filters.svg#blur' )"/></svg>"#,
            #"<svg><style>@import 'https://example.com/theme.css';</style><rect/></svg>"#,
            #"<svg><style>.key { fill: url(data:image/svg+xml;base64,PHN2Zy8+); }</style></svg>"#,
            #"<svg><style><![CDATA[@import 'https://example.com/theme.css';]]></style></svg>"#,
            #"<svg><style>@\69mport 'https://example.com/theme.css';</style></svg>"#,
            #"<svg><style>@im/**/port 'https://example.com/theme.css';</style></svg>"#,
            #"<svg><rect style="fill: u\72l(https://example.com/paint.svg)"/></svg>"#,
            #"<svg><style>@import 'https://example.com/a.css';<style>.safe { fill: red }</style></style></svg>"#
        ]

        for fixture in fixtures {
            #expect(try load(Data(fixture.utf8)) == .failure(.unsafeSVGContent), "Accepted: \(fixture)")
        }
    }

    @Test
    func SVGAnimationCannotMutateValidatedReferences() throws {
        let fixtures = [
            ##"<svg><use id="key" href="#safe"><set attributeName="href" to="https://example.com/key.svg"/></use></svg>"##,
            ##"<svg><use href="#safe"><animate attributeName="href" values="#safe;https://example.com/key.svg"/></use></svg>"##,
            #"<svg><animateMotion path="M0 0L10 10"/></svg>"#,
            #"<svg><animateTransform attributeName="transform" type="rotate"/></svg>"#,
            #"<svg><discard begin="1s"/></svg>"#
        ]

        for fixture in fixtures {
            #expect(try load(Data(fixture.utf8)) == .failure(.unsafeSVGContent), "Accepted: \(fixture)")
        }
    }

    @Test
    func fragmentReferencesAndInlineKeymapStylesRemainSupported() throws {
        let fixture = #"""
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
          <defs>
            <linearGradient id="gradient"><stop offset="100%" stop-color="#fff"/></linearGradient>
            <filter id="shadow"><feDropShadow dx="1" dy="1"/></filter>
            <path id="key" d="M0 0h10v10H0z"/>
          </defs>
          <style>
            .key { fill: url(#gradient); stroke: #222; stroke-width: 0.5; }
            .label { font-family: system-ui, sans-serif; font-size: 3px; }
          </style>
          <use href="#key" class="key"/>
          <use xlink:href="#key" transform="translate(12 0)"/>
          <rect filter="url( '#shadow' )" width="10" height="10"/>
        </svg>
        """#

        guard case .success(.svg(let asset)) = try load(Data(fixture.utf8)) else {
            Issue.record("Self-contained SVG should load")
            return
        }
        #expect(asset.document.contains("data:image/svg+xml;base64,"))
    }

    @Test
    func missingAndOrdinaryImageFilesKeepExistingBehavior() throws {
        #expect(
            OverlayAssetRenderer.loadAsset(at: "/tmp/definitely-missing-\(UUID().uuidString).svg")
                == .failure(.missingOrUnreadable)
        )

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("key.png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
        #expect(OverlayAssetRenderer.loadAsset(at: image.path) == .success(.imageFile(image)))
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("keylens-renderer-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func load(_ data: Data) throws -> Result<OverlayAsset, OverlayAssetLoadError> {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("asset.svg")
    try data.write(to: file)
    return OverlayAssetRenderer.loadAsset(at: file.path)
}
