import Foundation
import ScreenCaptureKit
import OSLog
import Combine

struct CapturedFrame {
    static var invalid: CapturedFrame {
        CapturedFrame(surface: nil, contentRect: .zero, contentScale: 0, scaleFactor: 0)
    }
    
    let surface: IOSurface?
    let contentRect: CGRect
    let contentScale: CGFloat
    let scaleFactor: CGFloat
    var size: CGSize { contentRect.size }
}

class CaptureEngine: NSObject, @unchecked Sendable {
    
    private let logger = Logger()
    
    private(set) var stream: SCStream?
    private var streamOutput: CaptureEngineStreamOutput?
    private let videoSampleBufferQueue = DispatchQueue(label: "com.adaskar.VScreen.VideoSampleBufferQueue")
    
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    
    func startCapture(configuration: SCStreamConfiguration, filter: SCContentFilter) -> AsyncThrowingStream<CapturedFrame, Error> {
        return AsyncThrowingStream { continuation in
            let streamOutput = CaptureEngineStreamOutput(continuation: continuation)
            self.streamOutput = streamOutput
            streamOutput.capturedFrameHandler = { continuation.yield($0) }
            
            do {
                self.stream = SCStream(filter: filter, configuration: configuration, delegate: streamOutput)
                
                try self.stream?.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: self.videoSampleBufferQueue)
                self.stream?.startCapture()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
    
    func stopCapture() async {
        do {
            try await stream?.stopCapture()
            continuation?.finish()
        } catch {
            continuation?.finish(throwing: error)
        }
    }
    
    func update(configuration: SCStreamConfiguration, filter: SCContentFilter) async {
        do {
            try await stream?.updateConfiguration(configuration)
            try await stream?.updateContentFilter(filter)
        } catch {
            logger.error("Failed to update the stream session: \(String(describing: error))")
        }
    }
}

private class CaptureEngineStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    
    var capturedFrameHandler: ((CapturedFrame) -> Void)?
    
    private var continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?
    
    init(continuation: AsyncThrowingStream<CapturedFrame, Error>.Continuation?) {
        self.continuation = continuation
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        
        guard sampleBuffer.isValid && outputType == .screen else { return }
        guard let frame = createFrame(for: sampleBuffer) else { return }
		
        capturedFrameHandler?(frame)
    }
    
    private func createFrame(for sampleBuffer: CMSampleBuffer) -> CapturedFrame? {
        
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                             createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else { return nil }
        
        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else { return nil }
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }
        guard let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        
        guard let contentRectDict = attachments[.contentRect],
              let contentRect = CGRect(dictionaryRepresentation: contentRectDict as! CFDictionary),
              let contentScale = attachments[.contentScale] as? CGFloat,
              let scaleFactor = attachments[.scaleFactor] as? CGFloat else { return nil }
        
        let frame = CapturedFrame(surface: surface,
                                  contentRect: contentRect,
                                  contentScale: contentScale,
                                  scaleFactor: scaleFactor)
        return frame
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        continuation?.finish(throwing: error)
    }
}
