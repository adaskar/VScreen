//
//  ViewHelper.swift
//  XScreen
//
//  Created by Gurhan Polat on 25.08.2024.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindowAccess: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        DispatchQueue.main.async {
            onWindowAccess(nsView.window)
        }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func onWindow(_ action: @escaping (NSWindow?) -> Void) -> some View {
        self.background(WindowAccessor(onWindowAccess: action))
    }
}
