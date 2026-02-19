import AppKit
import WebKit

final class OverlayWindowController: NSWindowController {
    private let imageView = NSImageView()
    private let webView = WKWebView()
    private let dimmingView = NSView()
    private var hideTask: DispatchWorkItem?

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
        dimmingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        rootView.addSubview(dimmingView)

        imageView.frame = rootView.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = 0.85
        rootView.addSubview(imageView)

        webView.frame = rootView.bounds
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.drawsBackground = false
        webView.isHidden = true
        rootView.addSubview(webView)

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

    func showAsset(at localPath: String, for duration: TimeInterval) {
        loadAsset(at: localPath)
        show(for: duration)
    }

    func show(for duration: TimeInterval) {
        hideTask?.cancel()
        updateFrameForCurrentScreen()

        guard let window else { return }
        window.alphaValue = 1.0
        window.orderFrontRegardless()

        let task = DispatchWorkItem { [weak self] in
            self?.hide()
        }

        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, duration), execute: task)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func loadAsset(at localPath: String) {
        if localPath.lowercased().hasSuffix(".svg") {
            loadSVG(at: localPath)
            return
        }

        if let image = NSImage(contentsOfFile: localPath) {
            setImage(image)
        }
    }

    private func loadSVG(at localPath: String) {
        guard let svgData = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
              let svgBody = String(data: svgData, encoding: .utf8) else {
            return
        }

        let html = """
        <!doctype html>
        <html>
          <head>
            <meta charset=\"utf-8\" />
            <style>
              html, body {
                margin: 0;
                width: 100%;
                height: 100%;
                background: transparent;
              }
              body {
                display: flex;
                align-items: center;
                justify-content: center;
                overflow: hidden;
              }
              svg {
                max-width: 95vw;
                max-height: 95vh;
              }
            </style>
          </head>
          <body>
            \(svgBody)
          </body>
        </html>
        """

        imageView.isHidden = true
        webView.isHidden = false
        let baseURL = URL(fileURLWithPath: localPath).deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func updateFrameForCurrentScreen() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let targetScreen {
            window.setFrame(targetScreen.frame, display: true)
        }
    }
}
