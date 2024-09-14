import SwiftUI
import ScreenCaptureKit
import OSLog
import Combine

struct ContentView: View {
    
    @State private var window: NSWindow?
    
    @State var isUnauthorized = false
    @AppStorage("isWindowFloating") private var isWindowFloating: Bool = false
    @AppStorage("opacity") private var opacity: Double = 1.0
    
    @StateObject var screenRecorder = ScreenRecorder()
    
    var body: some View {
        screenRecorder.capturePreview
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(screenRecorder.contentSize, contentMode: .fit)
            .overlay {
                if isUnauthorized {
                    VStack() {
                        Spacer()
                        VStack {
                            Text("No screen recording permission.")
                                .font(.largeTitle)
                                .padding(.top)
                            Text("Open System Settings and go to Privacy & Security > Screen Recording to grant permission.")
                                .font(.title2)
                                .padding(.bottom)
                        }
                        .frame(maxWidth: .infinity)
                        .background(.red)
                        
                    }
                }
            }
            .navigationTitle("XScreen")
            .onAppear {
                Task {
                    if await screenRecorder.canRecord {
                        await screenRecorder.start()
                    } else {
                        isUnauthorized = true
                    }
                }
            }
            .onWindow { window in
                self.window = window
                window?.level = isWindowFloating ? .floating : .normal
                window?.alphaValue = opacity
            }
            .toolbar {
                VStack {
                    Picker("captureType", selection: $screenRecorder.captureType) {
                        Text("Display")
                            .tag(ScreenRecorder.CaptureType.display)
                        Text("Window")
                            .tag(ScreenRecorder.CaptureType.window)
                    }.labelsHidden()
                }
                VStack {
                    switch screenRecorder.captureType {
                    case .display:
                        Picker("display", selection: $screenRecorder.selectedDisplay) {
                            ForEach(screenRecorder.availableDisplays, id: \.self) { display in
                                Text(display.displayName)
                                    .tag(SCDisplay?.some(display))
                            }
                        }.labelsHidden()
                        
                    case .window:
                        Picker("window", selection: $screenRecorder.selectedWindow) {
                            ForEach(screenRecorder.availableWindows, id: \.self) { window in
                                Text(window.displayName)
                                    .tag(SCWindow?.some(window))
                            }
                        }.labelsHidden()
                    }
                }
                
                Button(action: {
                    Task {
                        if await screenRecorder.canRecord {
                            if (screenRecorder.isRunning) {
                                await screenRecorder.stop()
                            }
                            else {
                                await screenRecorder.start()
                            }
                        } else {
                            isUnauthorized = true
                        }
                    }
                }) {
                    Image(systemName: screenRecorder.isRunning ? "stop.circle" : "play.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                
                Slider(value: $opacity, in: 0.3...1.0)
                    .frame(width: 100)
                    .onChange(of: opacity) {
                        window?.alphaValue = opacity
                    }
                
                Button(action: {
                    screenRecorder.isAppExcluded.toggle()
                }) {
                    Image(systemName: screenRecorder.isAppExcluded ? "eye.slash" : "eye")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    isWindowFloating.toggle()
                    if let window = window {
                        window.level = isWindowFloating ? .floating : .normal
                    }
                }) {
                    Image(systemName: isWindowFloating ? "rectangle.on.rectangle" : "rectangle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                                
                Button(action: createNewWindow) {
                    Image(systemName: "plus.square.on.square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
            }
    }
    
    
    private func createNewWindow() {
        if let window = window {
            let newWindow = NSWindow(
                contentRect: NSRect(x: window.frame.origin.x + 20, y: window.frame.origin.y - 20, width: window.frame.width, height: window.frame.height),
                styleMask: window.styleMask,
                backing: .buffered, defer: false)
            
            newWindow.contentView = NSHostingView(rootView: ContentView())
            newWindow.makeKeyAndOrderFront(self)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
