import Foundation
@preconcurrency import ScreenCaptureKit
import Combine
import OSLog
import SwiftUI

@MainActor
class ScreenRecorder: NSObject,
                      ObservableObject,
                      SCContentSharingPickerObserver {
    /// The supported capture types.
    enum CaptureType {
        case display
        case window
    }
        
    private let logger = Logger()
    
    @Published var isRunning = false
    
    // MARK: - Video Properties
    @Published var captureType: CaptureType = .display {
        didSet { updateEngine() }
    }
    
    @Published var selectedDisplay: SCDisplay? {
        didSet { updateEngine() }
    }
    
    @Published var selectedWindow: SCWindow? {
        didSet { updateEngine() }
    }
    
    @Published var isAppExcluded = true {
        didSet { updateEngine() }
    }

    // MARK: - SCContentSharingPicker Properties
    @Published var maximumStreamCount = Int() {
        didSet { updatePickerConfiguration() }
    }
    @Published var excludedWindowIDsSelection = Set<Int>() {
        didSet { updatePickerConfiguration() }
    }

    @Published var excludedBundleIDsList = [String]() {
        didSet { updatePickerConfiguration() }
    }

    @Published var allowsRepicking = true {
        didSet { updatePickerConfiguration() }
    }

    @Published var allowedPickingModes = SCContentSharingPickerMode() {
        didSet { updatePickerConfiguration() }
    }
    
    @Published var contentSize = CGSize(width: 1, height: 1)
    private var scaleFactor: Int { Int(NSScreen.main?.backingScaleFactor ?? 2) }
    
    /// A view that renders the screen content.
    lazy var capturePreview: CapturePreview = {
        CapturePreview()
    }()
    private let screenRecorderPicker = SCContentSharingPicker.shared
    private var availableApps = [SCRunningApplication]()
    @Published private(set) var availableDisplays = [SCDisplay]()
    @Published private(set) var availableWindows = [SCWindow]()
    @Published private(set) var pickerUpdate: Bool = false // Update the running stream immediately with picker selection
    private var pickerContentFilter: SCContentFilter?
    private var shouldUsePickerFilter = false
    /// - Tag: TogglePicker
    @Published var isPickerActive = false {
        didSet {
            if isPickerActive {
                logger.info("Picker is active")
                self.initializePickerConfiguration()
                self.screenRecorderPicker.isActive = true
                self.screenRecorderPicker.add(self)
            } else {
                logger.info("Picker is inactive")
                self.screenRecorderPicker.isActive = false
                self.screenRecorderPicker.remove(self)
            }
        }
    }

    private let captureEngine = CaptureEngine()
    
    private var isSetup = false
    
    // Combine subscribers.
    private var subscriptions = Set<AnyCancellable>()
    
    var canRecord: Bool {
        get async {
            do {
                // If the app doesn't have screen recording permission, this call generates an exception.
                try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                return true
            } catch {
                return false
            }
        }
    }
    
    func monitorAvailableContent() async {
        guard !isSetup || !isPickerActive else { return }
        // Refresh the lists of capturable content.
        await self.refreshAvailableContent()
        Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.refreshAvailableContent()
            }
        }
        .store(in: &subscriptions)
    }
    
    /// Starts capturing screen content.
    func start() async {
        // Exit early if already running.
        guard !isRunning else { return }
        
        if !isSetup {
            // Starting polling for available screen content.
            await monitorAvailableContent()
            isSetup = true
        }
                
        do {
            let config = streamConfiguration
            let filter = contentFilter
            // Update the running state.
            isRunning = true
            setPickerUpdate(false)
            // Start the stream and await new video frames.
            for try await frame in captureEngine.startCapture(configuration: config, filter: filter) {
                capturePreview.updateFrame(frame)
                if contentSize != frame.size {
                    // Update the content size if it changed.
                    contentSize = frame.size
                }
            }
        } catch {
            logger.error("\(error.localizedDescription)")
            // Unable to start the stream. Set the running state to false.
            isRunning = false
        }
    }
    
    /// Stops capturing screen content.
    func stop() async {
        guard isRunning else { return }
        await captureEngine.stopCapture()
        isRunning = false
    }
        
    /// - Tag: UpdateCaptureConfig
    private func updateEngine() {
        guard isRunning else { return }
        Task {
            let filter = contentFilter
            await captureEngine.update(configuration: streamConfiguration, filter: filter)
            setPickerUpdate(false)
        }
    }

    // MARK: - Content-sharing Picker
    private func initializePickerConfiguration() {
        var initialConfiguration = SCContentSharingPickerConfiguration()
        // Set the allowedPickerModes from the app.
        initialConfiguration.allowedPickerModes = [
            .singleWindow,
            .multipleWindows,
            .singleApplication,
            .multipleApplications,
            .singleDisplay
        ]
        self.allowedPickingModes = initialConfiguration.allowedPickerModes
    }

    private func updatePickerConfiguration() {
        self.screenRecorderPicker.maximumStreamCount = maximumStreamCount
        // Update the default picker configuration to pass to Control Center.
        self.screenRecorderPicker.defaultConfiguration = pickerConfiguration
    }

    /// - Tag: HandlePicker
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        logger.info("Picker canceled for stream \(stream)")
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            pickerContentFilter = filter
            shouldUsePickerFilter = true
            setPickerUpdate(true)
            updateEngine()
        }
        logger.info("Picker updated with filter=\(filter) for stream=\(stream)")
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        logger.error("Error starting picker! \(error)")
    }

    func setPickerUpdate(_ update: Bool) {
        Task { @MainActor in
            self.pickerUpdate = update
        }
    }

    func presentPicker() {
        if let stream = captureEngine.stream {
            SCContentSharingPicker.shared.present(for: stream)
        } else {
            SCContentSharingPicker.shared.present()
        }
    }

    private var pickerConfiguration: SCContentSharingPickerConfiguration {
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = allowedPickingModes
        config.excludedWindowIDs = Array(excludedWindowIDsSelection)
        config.excludedBundleIDs = excludedBundleIDsList
        config.allowsChangingSelectedContent = allowsRepicking
        return config
    }

    /// - Tag: UpdateFilter
    private var contentFilter: SCContentFilter {
        var filter: SCContentFilter
        switch captureType {
        case .display:
            guard let display = selectedDisplay else { fatalError("No display selected.") }
            var excludedApps = [SCRunningApplication]()
            // If a user chooses to exclude the app from the stream,
            // exclude it by matching its bundle identifier.
            if isAppExcluded {
                excludedApps = availableApps.filter { app in
                    Bundle.main.bundleIdentifier == app.bundleIdentifier
                }
            }
            // Create a content filter with excluded apps.
            filter = SCContentFilter(display: display,
                                     excludingApplications: excludedApps,
                                     exceptingWindows: [])
        case .window:
            guard let window = selectedWindow else { fatalError("No window selected.") }
            
            // Create a content filter that includes a single window.
            filter = SCContentFilter(desktopIndependentWindow: window)
        }
        // Use filter from content picker, if active.
        if shouldUsePickerFilter {
            guard let pickerFilter = pickerContentFilter else { return filter }
            filter = pickerFilter
            shouldUsePickerFilter = false
        }
        return filter
    }
    
    private var streamConfiguration: SCStreamConfiguration {
        
        let streamConfig = SCStreamConfiguration()
        
        // Configure the display content width and height.
        if captureType == .display, let display = selectedDisplay {
            streamConfig.width = display.width * scaleFactor
            streamConfig.height = display.height * scaleFactor
        }
        
        // Configure the window content width and height.
        if captureType == .window, let window = selectedWindow {
            streamConfig.width = Int(window.frame.width) * 2
            streamConfig.height = Int(window.frame.height) * 2
        }
        
        // Set the capture interval at 60 fps.
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        
        // Increase the depth of the frame queue to ensure high fps at the expense of increasing
        // the memory footprint of WindowServer.
        streamConfig.queueDepth = 5
        
        return streamConfig
    }
    
    /// - Tag: GetAvailableContent
    private func refreshAvailableContent() async {
        do {
            // Retrieve the available screen content to capture.
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                        onScreenWindowsOnly: true)
            availableDisplays = availableContent.displays.reversed()
            
            let windows = filterWindows(availableContent.windows)
            if windows != availableWindows {
                availableWindows = windows
            }
            availableApps = availableContent.applications
            
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            if selectedWindow == nil {
                selectedWindow = availableWindows.first
            }
        } catch {
            logger.error("Failed to get the shareable content: \(error.localizedDescription)")
        }
    }
    
    private func filterWindows(_ windows: [SCWindow]) -> [SCWindow] {
        windows
        // Sort the windows by app name.
            .sorted { $0.owningApplication?.applicationName ?? "" < $1.owningApplication?.applicationName ?? "" }
        // Remove windows that don't have an associated .app bundle.
            .filter { $0.owningApplication != nil && $0.owningApplication?.applicationName != "" }
        // Remove this app's window from the list.
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }
}

extension SCWindow {
    var displayName: String {
        switch (owningApplication, title) {
        case (.some(let application), .some(let title)):
            return "\(application.applicationName): \(title)"
        case (.none, .some(let title)):
            return title
        case (.some(let application), .none):
            return "\(application.applicationName): \(windowID)"
        default:
            return ""
        }
    }
}

extension SCDisplay {
    var displayName: String {
        let s = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }
        let desc = s != nil ? "\(s!.localizedName)" : "N/A"
        return "\(desc) (\(width) x \(height))"
    }
}
