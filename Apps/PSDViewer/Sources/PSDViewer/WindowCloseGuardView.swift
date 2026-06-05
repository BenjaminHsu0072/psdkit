import AppKit
import SwiftUI

struct WindowCloseGuardView: NSViewRepresentable {
    @ObservedObject var model: DocumentModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.model = model
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: nsView.window)
        }
    }

    final class Coordinator: NSObject {
        weak var model: DocumentModel?
        private weak var attachedWindow: NSWindow?
        private var guardDelegate: WindowCloseGuardDelegate?

        init(model: DocumentModel) {
            self.model = model
        }

        func attachIfNeeded(to window: NSWindow?) {
            guard let window else { return }
            if attachedWindow === window {
                guardDelegate?.model = model
                return
            }
            let downstream = window.delegate
            let delegate = WindowCloseGuardDelegate(model: model, window: window, downstream: downstream)
            window.delegate = delegate
            attachedWindow = window
            guardDelegate = delegate
        }
    }
}

private final class WindowCloseGuardDelegate: NSObject, NSWindowDelegate {
    weak var model: DocumentModel?
    weak var window: NSWindow?
    weak var downstreamDelegate: NSWindowDelegate?

    private var allowsImmediateClose = false

    init(model: DocumentModel?, window: NSWindow, downstream: NSWindowDelegate?) {
        self.model = model
        self.window = window
        self.downstreamDelegate = downstream
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsImmediateClose {
            allowsImmediateClose = false
            return downstreamDelegate?.windowShouldClose?(sender) ?? true
        }
        if let downstreamDelegate, downstreamDelegate !== self {
            let allowed = downstreamDelegate.windowShouldClose?(sender) ?? true
            if !allowed { return false }
        }
        guard let model else { return true }
        model.requestCloseDocument { [weak self, weak sender] in
            guard let self, let sender else { return }
            self.allowsImmediateClose = true
            sender.performClose(nil)
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        downstreamDelegate?.windowWillClose?(notification)
    }
}
