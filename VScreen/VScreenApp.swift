//
//  VScreenApp.swift
//  VScreen
//
//  Created by Gurhan Polat on 22.08.2024.
//

import SwiftUI
import SwiftData

@main
struct VScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1920 / 3, minHeight: 1080 / 3)
                .background(.black)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(self)
        }
        return true
    }
}
