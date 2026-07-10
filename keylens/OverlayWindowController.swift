import AppKit
import WebKit

final class OverlayWindowController: NSWindowController {
    private let imageView = NSImageView()
    private let webView = OverlayAssetRenderer.makeWebView()
    private let dimmingView = NSView()
    private let assetContainerView = NSView()
    private let dimmingLayer = RadialDimmingLayer()
    private(set) var isVisible = false
    private var currentPlacement: OverlayPlacement = .center

    init() {
        let initialFrame = NSScreen.main?.frame ?? .zero
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.hasShadow = false

        super.init(window: window)

        let rootView = NSView(frame: initialFrame)
        rootView.wantsLayer = true
        window.contentView = rootView

        dimmingView.frame = rootView.bounds
        dimmingView.autoresizingMask = [.width, .height]
        dimmingView.wantsLayer = true
        dimmingView.layer = dimmingLayer
        dimmingLayer.frame = dimmingView.bounds
        dimmingLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootView.addSubview(dimmingView)

        assetContainerView.frame = rootView.bounds
        rootView.addSubview(assetContainerView)

        imageView.frame = assetContainerView.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0.92
        assetContainerView.addSubview(imageView)

        webView.frame = assetContainerView.bounds
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.drawsBackground = false
        webView.isHidden = true
        assetContainerView.addSubview(webView)

        window.orderOut(nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setImage(_ image: NSImage) {
        imageView.image = image
        imageView.isHidden = false
        webView.isHidden = true
    }

    @discardableResult
    func showAsset(at localPath: String, placement: OverlayPlacement) -> Bool {
        guard loadAsset(at: localPath) else {
            hide()
            return false
        }

        show(placement: placement)
        return true
    }

    func show(placement: OverlayPlacement) {
        currentPlacement = placement
        updateFrameForCurrentScreen()

        guard let window else { return }
        window.alphaValue = 1.0
        window.orderFrontRegardless()
        isVisible = true

    }

    func updatePlacement(_ placement: OverlayPlacement) {
        currentPlacement = placement
        guard isVisible else { return }
        updateFrameForCurrentScreen()
    }

    func hide() {
        guard isVisible else { return }

        window?.orderOut(nil)
        isVisible = false
    }

    private func loadAsset(at localPath: String) -> Bool {
        switch OverlayAssetRenderer.loadAsset(at: localPath) {
        case .success(.svg(let asset)):
            loadSVG(asset)
            return true

        case .success(.imageFile(let url)):
            guard let image = NSImage(contentsOf: url) else {
                return false
            }
            setImage(image)
            return true

        case .failure:
            return false
        }
    }

    private func loadSVG(_ asset: OverlaySVGAsset) {
        imageView.isHidden = true
        webView.isHidden = false
        webView.loadHTMLString(asset.document, baseURL: nil)
    }

    private func updateFrameForCurrentScreen() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let targetScreen {
            window.setFrame(targetScreen.frame, display: true)
            layoutOverlay(in: targetScreen.frame.size)
        }
    }

    private func layoutOverlay(in screenSize: NSSize) {
        let overlaySize = overlaySize(for: screenSize)
        let center = currentPlacement.centerPoint(in: screenSize)

        assetContainerView.frame = NSRect(
            x: center.x - (overlaySize.width / 2.0),
            y: center.y - (overlaySize.height / 2.0),
            width: overlaySize.width,
            height: overlaySize.height
        )

        dimmingLayer.frame = dimmingView.bounds
        dimmingLayer.focusPoint = CGPoint(
            x: center.x / max(screenSize.width, 1),
            y: center.y / max(screenSize.height, 1)
        )
    }

    private func overlaySize(for screenSize: NSSize) -> NSSize {
        let width = min(max(screenSize.width * 0.44, 260), screenSize.width * 0.88)
        let height = min(max(screenSize.height * 0.44, 180), screenSize.height * 0.88)
        return NSSize(width: width, height: height)
    }
}

private extension OverlayPlacement {
    func centerPoint(in screenSize: NSSize) -> CGPoint {
        let xFactor: CGFloat
        let yFactor: CGFloat

        switch self {
        case .center:
            xFactor = 0.5
            yFactor = 0.5
        case .topLeft:
            xFactor = 0.25
            yFactor = 0.75
        case .topRight:
            xFactor = 0.75
            yFactor = 0.75
        case .bottomLeft:
            xFactor = 0.25
            yFactor = 0.25
        case .bottomRight:
            xFactor = 0.75
            yFactor = 0.25
        }

        return CGPoint(
            x: screenSize.width * xFactor,
            y: screenSize.height * yFactor
        )
    }
}

private final class RadialDimmingLayer: CALayer {
    var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5) {
        didSet {
            setNeedsDisplay()
        }
    }

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let source = layer as? RadialDimmingLayer {
            focusPoint = source.focusPoint
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        needsDisplayOnBoundsChange = true
    }

    override func draw(in context: CGContext) {
        context.clear(bounds)

        let center = CGPoint(
            x: bounds.minX + (focusPoint.x * bounds.width),
            y: bounds.minY + (focusPoint.y * bounds.height)
        )
        let radius = max(bounds.width, bounds.height) * 0.34

        let colors = [
            NSColor.black.withAlphaComponent(0.42).cgColor,
            NSColor.black.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.32, 1.0]

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else {
            return
        }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
    }
}
