//  FilteredVideoWriter.swift
//  VideoEffects
//
//  Created by Simon Gladman on 17/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import MobileCoreServices
import AVFoundation
import CoreImage
import UIKit

class FilteredVideoWriter: NSObject {
    lazy var media_queue: DispatchQueue = {
        return DispatchQueue.init(label: "mediaInputQueue")
    }()
    
    /// `timeDateFormatter` is used when generating a file name for the
    /// temporary file when creating the final output
    let timeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        
        return formatter
    }()
    
    let ciContext = CIContext()
    
    weak var delegate: FilteredVideoWriterDelegate?
    
    let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
    var videoWriterInput: AVAssetWriterInput?
    var videoWriter: AVAssetWriter?
    var videoOutputURL: URL?
    var player: AVPlayer?
    var ciFilter: CIFilter?
    var videoTransform: CGAffineTransform?
    var videoOutput: AVPlayerItemVideoOutput?
    
    /// Initialises the objects required to save the final video output and begins writing
    func beginSaving(player: AVPlayer, ciFilter: CIFilter, videoTransform: CGAffineTransform, videoOutput: AVPlayerItemVideoOutput) {
        
        self.player = player
        self.ciFilter = ciFilter
        self.videoTransform = videoTransform
        self.videoOutput = videoOutput
        
        guard let currentItem = player.currentItem else {
            return
        }
        
        guard let documentDirectory = urls.first else {
            fatalError("** unable to access document directory **")
        }
        
        videoOutputURL = documentDirectory.appendingPathComponent("Output_\(timeDateFormatter.string(from: Date())).mp4")
        
        do {
            videoWriter = try AVAssetWriter(outputURL: videoOutputURL!, fileType: AVFileType.mp4)
        }
        catch {
            fatalError("** unable to create asset writer **")
        }
        
        let outputSettings: [String : Any] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: currentItem.presentationSize.width,
            AVVideoHeightKey: currentItem.presentationSize.height]
        
        guard videoWriter?.canApply(outputSettings: outputSettings, forMediaType: .video) ?? false else {
            fatalError("** unable to apply video settings ** ")
        }
        
        videoWriterInput = AVAssetWriterInput(
            mediaType: AVMediaType.video,
            outputSettings: outputSettings)
        
        if videoWriter?.canAdd(videoWriterInput!) ?? false {
            videoWriter?.add(videoWriterInput!)
        }
        else {
            fatalError ("** unable to add input **")
        }
        
        let sourcePixelBufferAttributesDictionary: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA),
            String(kCVPixelBufferWidthKey) : currentItem.presentationSize.width,
            String(kCVPixelBufferHeightKey) : currentItem.presentationSize.height,
            String(kCVPixelFormatOpenGLESCompatibility) : true
        ]
        
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
        
        if videoWriter!.startWriting() {
            videoWriter!.startSession(atSourceTime: CMTime.zero)
        }
        
        player.seek(
            to: CMTimeMakeWithSeconds(0, preferredTimescale: 600),
            toleranceBefore: CMTime.zero,
            toleranceAfter: CMTime.zero)
        {
            _ in self.writeVideoFrames()
        }
    }
    
    /// Writes video frames to videoOutputURL
    func writeVideoFrames() {
        
        guard let player = player,
            let assetWriterPixelBufferInput = assetWriterPixelBufferInput,
            let pixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool,
            let currentItem = player.currentItem,
            let duration = player.currentItem?.asset.duration,
            let ciFilter = ciFilter,
            let videoWriter = videoWriter,
            let videoWriterInput = videoWriterInput,
            let videoOutputURL = videoOutputURL,
            let videoTransform = videoTransform,
            let videoOutput = videoOutput,
            let frameRate = currentItem.asset.tracks(withMediaType: AVMediaType.video).first?.nominalFrameRate else {
                return
        }
        
        assetWriterPixelBufferInput.assetWriterInput.requestMediaDataWhenReady(on: media_queue) {
            
            let numberOfFrames = Int(duration.seconds * Double(frameRate))
            
            for frameNumber in 0 ..< numberOfFrames {
                
                Thread.sleep(forTimeInterval: 0.05)
                
                DispatchQueue.main.async {
                    self.delegate?.updateSaveProgress(progress: Float(frameNumber) / Float(numberOfFrames))
                }
                
                if videoOutput.hasNewPixelBuffer(forItemTime: currentItem.currentTime()) {
                    var presentationItemTime = CMTime.zero
                    
                    if let pixelBuffer = videoOutput.copyPixelBuffer(
                        forItemTime: currentItem.currentTime(),
                        itemTimeForDisplay: &presentationItemTime) {
                        
                        let ciImage = CIImage(cvImageBuffer: pixelBuffer).transformed(by: videoTransform)
                        let positionTransform = CGAffineTransform(translationX: -ciImage.extent.origin.x, y: -ciImage.extent.origin.y)
                        let transformedImage = ciImage.transformed(by: positionTransform)
                        
                        ciFilter.setValue(transformedImage, forKey: kCIInputImageKey)
                        
                        var newPixelBuffer: CVPixelBuffer? = nil
                        
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &newPixelBuffer)
                        
                        self.ciContext.render(
                            ciFilter.outputImage!,
                            to: newPixelBuffer!,
                            bounds: ciFilter.outputImage!.extent,
                            colorSpace: nil)
                        
                        assetWriterPixelBufferInput.append(
                            newPixelBuffer!,
                            withPresentationTime: presentationItemTime)
                    }
                }
                
                currentItem.step(byCount: 1)
            }
            
            videoWriterInput.markAsFinished()
            
            videoWriter.finishWriting {
                player.seek(
                    to: CMTimeMakeWithSeconds(0, preferredTimescale: 600),
                    toleranceBefore: CMTime.zero,
                    toleranceAfter: CMTime.zero)
                
                DispatchQueue.main.async {
                    UISaveVideoAtPathToSavedPhotosAlbum(
                        videoOutputURL.relativePath,
                        self,
                        #selector(self.video(videoPath:didFinishSavingWithError:contextInfo:)),
                        nil)
                }
            }
        }
        
    }
    
    // UISaveVideoAtPathToSavedPhotosAlbum completion
    @objc func video(videoPath: NSString, didFinishSavingWithError error: NSError?, contextInfo info: AnyObject)
    {
        if let videoOutputURL = videoOutputURL, FileManager.default.isDeletableFile(atPath: videoOutputURL.relativePath)
        {
            try! FileManager.default.removeItem(at: videoOutputURL)
        }
        
        assetWriterPixelBufferInput = nil
        videoWriterInput = nil
        videoWriter = nil
        videoOutputURL = nil
        
        delegate?.saveComplete()
    }
}

protocol FilteredVideoWriterDelegate: class {
    func updateSaveProgress(progress: Float)
    func saveComplete()
}


