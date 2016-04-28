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
  lazy var media_queue: dispatch_queue_t = {
    return dispatch_queue_create("mediaInputQueue", nil)
  }()
  
  /// `timeDateFormatter` is used when generating a file name for the
  /// temporary file when creating the final output
  let timeDateFormatter: NSDateFormatter = {
    let formatter = NSDateFormatter()
    
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    
    return formatter
  }()
  
  let ciContext = CIContext()
  
  weak var delegate: FilteredVideoWriterDelegate?
  
  let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
  var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
  var videoWriterInput: AVAssetWriterInput?
  var videoWriter: AVAssetWriter?
  var videoOutputURL: NSURL?
  var player: AVPlayer?
  var ciFilter: CIFilter?
  var videoTransform: CGAffineTransform?
  var videoOutput: AVPlayerItemVideoOutput?
  
  /// Initialises the objects required to save the final video output and begins writing
  func beginSaving(player player: AVPlayer, ciFilter: CIFilter, videoTransform: CGAffineTransform, videoOutput: AVPlayerItemVideoOutput) {
    
    self.player = player
    self.ciFilter = ciFilter
    self.videoTransform = videoTransform
    self.videoOutput = videoOutput
    
    guard let currentItem = player.currentItem else {
        return
    }
    
    guard let documentDirectory: NSURL = urls.first else {
      fatalError("** unable to access document directory **")
    }
    
    videoOutputURL = documentDirectory.URLByAppendingPathComponent("Output_\(timeDateFormatter.stringFromDate(NSDate())).mp4")

    do {
      videoWriter = try AVAssetWriter(URL: videoOutputURL!, fileType: AVFileTypeMPEG4)
    }
    catch {
      fatalError("** unable to create asset writer **")
    }
    
    let outputSettings: [String : AnyObject] = [
      AVVideoCodecKey: AVVideoCodecH264,
      AVVideoWidthKey: currentItem.presentationSize.width,
      AVVideoHeightKey: currentItem.presentationSize.height]
    
    guard videoWriter!.canApplyOutputSettings(outputSettings, forMediaType: AVMediaTypeVideo) else {
      fatalError("** unable to apply video settings ** ")
    }
    
    videoWriterInput = AVAssetWriterInput(
      mediaType: AVMediaTypeVideo,
      outputSettings: outputSettings)
    
    if videoWriter!.canAddInput(videoWriterInput!) {
      videoWriter!.addInput(videoWriterInput!)
    }
    else {
      fatalError ("** unable to add input **")
    }
    
    let sourcePixelBufferAttributesDictionary = [
      String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA),
      String(kCVPixelBufferWidthKey) : currentItem.presentationSize.width,
      String(kCVPixelBufferHeightKey) : currentItem.presentationSize.height,
      String(kCVPixelFormatOpenGLESCompatibility) : kCFBooleanTrue
    ]
    
    assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoWriterInput!,
      sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
    
    if videoWriter!.startWriting() {
      videoWriter!.startSessionAtSourceTime(kCMTimeZero)
    }

    player.seekToTime(
      CMTimeMakeWithSeconds(0, 600),
      toleranceBefore: kCMTimeZero,
      toleranceAfter: kCMTimeZero)
    {
      _ in self.writeVideoFrames()
    }
  }
  
  /// Writes video frames to videoOutputURL
  func writeVideoFrames() {
    
    guard let player = player,
      assetWriterPixelBufferInput = assetWriterPixelBufferInput,
      pixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool,
      currentItem = player.currentItem,
      duration = player.currentItem?.asset.duration,
      ciFilter = ciFilter,
      videoWriter = videoWriter,
      videoWriterInput = videoWriterInput,
      videoOutputURL = videoOutputURL,
      videoTransform = videoTransform,
      videoOutput = videoOutput,
      frameRate = currentItem.asset.tracksWithMediaType(AVMediaTypeVideo).first?.nominalFrameRate else {
        return
    }
    
    assetWriterPixelBufferInput.assetWriterInput.requestMediaDataWhenReadyOnQueue(media_queue) {
      
      let numberOfFrames = Int(duration.seconds * Double(frameRate))
      
      for frameNumber in 0 ..< numberOfFrames {
        
        NSThread.sleepForTimeInterval(0.05)
        
        dispatch_async(dispatch_get_main_queue()) {
          self.delegate?.updateSaveProgress(Float(frameNumber) / Float(numberOfFrames))
        }
        
        if videoOutput.hasNewPixelBufferForItemTime(currentItem.currentTime()) {
          var presentationItemTime = kCMTimeZero
          
          if let pixelBuffer = videoOutput.copyPixelBufferForItemTime(
            currentItem.currentTime(),
            itemTimeForDisplay: &presentationItemTime) {
            
            let ciImage = CIImage(CVImageBuffer: pixelBuffer).imageByApplyingTransform(videoTransform)
            let positionTransform = CGAffineTransformMakeTranslation(-ciImage.extent.origin.x, -ciImage.extent.origin.y)
            let transformedImage = ciImage.imageByApplyingTransform(positionTransform)
            
            ciFilter.setValue(transformedImage, forKey: kCIInputImageKey)
            
            var newPixelBuffer: CVPixelBuffer? = nil
            
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &newPixelBuffer)
            
            self.ciContext.render(
              ciFilter.outputImage!,
              toCVPixelBuffer: newPixelBuffer!,
              bounds: ciFilter.outputImage!.extent,
              colorSpace: nil)
            
            assetWriterPixelBufferInput.appendPixelBuffer(
              newPixelBuffer!,
              withPresentationTime: presentationItemTime)
          }
        }
        
        currentItem.stepByCount(1)
      }
      
      videoWriterInput.markAsFinished()
      
      videoWriter.finishWritingWithCompletionHandler {
        player.seekToTime(
          CMTimeMakeWithSeconds(0, 600),
          toleranceBefore: kCMTimeZero,
          toleranceAfter: kCMTimeZero)
        
        dispatch_async(dispatch_get_main_queue()) {
          UISaveVideoAtPathToSavedPhotosAlbum(
            videoOutputURL.relativePath!,
            self,
            #selector(FilteredVideoWriter.video(_:didFinishSavingWithError:contextInfo:)),
            nil)
        }
      }
    }
    
  }
  
  // UISaveVideoAtPathToSavedPhotosAlbum completion
  func video(videoPath: NSString, didFinishSavingWithError error: NSError?, contextInfo info: AnyObject)
  {
    if let videoOutputURL = videoOutputURL where NSFileManager.defaultManager().isDeletableFileAtPath(videoOutputURL.relativePath!)
    {
      try! NSFileManager.defaultManager().removeItemAtURL(videoOutputURL)
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


