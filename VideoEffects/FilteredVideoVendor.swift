//  FilteredVideoVendor.swift
//  VideoEffects
//
//  Created by Simon Gladman on 17/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit
import MobileCoreServices
import AVFoundation

class FilteredVideoVendor: NSObject {
  
  static let pixelBufferAttributes: [String:AnyObject] = [
    String(kCVPixelBufferPixelFormatTypeKey): NSNumber(unsignedInt: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
  
  let ciContext = CIContext()
  
  var videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: FilteredVideoVendor.pixelBufferAttributes)
  var player: AVPlayer?
  var videoTransform: CGAffineTransform?
  var unfilteredImage: CIImage?
  var currentURL: NSURL?
  var failedPixelBufferForItemTimeCount = 0
  
  weak var delegate: FilteredVideoVendorDelegate?
  
  var ciFilter: CIFilter? {
    didSet {
      displayFilteredImage()
    }
  }
  
  var paused = true {
    didSet {
      displayLink.paused = paused

      if displayLink.paused {
        player?.pause()
      }
      else {
        player?.play()
      }
    }
  }
  
  lazy var displayLink: CADisplayLink = {
    [unowned self] in
    
    let displayLink = CADisplayLink(
      target: self,
      selector: #selector(FilteredVideoVendor.step(_:)))
    
    displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
    displayLink.paused = true
    
    return displayLink
    }()
 
  func openMovie(url: NSURL){
    player = AVPlayer(URL: url)
    
    guard let player = player,
      currentItem = player.currentItem,
      videoTrack = currentItem.asset.tracksWithMediaType(AVMediaTypeVideo).first else {
        fatalError("** unable to access item **")
    }
    
    currentURL = url
    failedPixelBufferForItemTimeCount = 0

    currentItem.addOutput(videoOutput)
    
    videoTransform = CGAffineTransformInvert(videoTrack.preferredTransform)
    
    player.muted = true
  }
  
  func gotoNormalisedTime(normalisedTime: Double) {
    guard let player = player else {
      return
    }

    let timeSeconds = player.currentItem!.asset.duration.seconds * normalisedTime
    
    let time = CMTimeMakeWithSeconds(timeSeconds, 600)
    
    player.seekToTime(
      time,
      toleranceBefore: kCMTimeZero,
      toleranceAfter: kCMTimeZero)
    
    displayVideoFrame(time)
  }
  
  // MARK: Main playback loop
  func step(link: CADisplayLink) {
    guard let player = player,
      currentItem = player.currentItem else {
        return
    }
    
    let itemTime = videoOutput.itemTimeForHostTime(CACurrentMediaTime())
    
    displayVideoFrame(itemTime)
    
    let normalisedTime = Float(itemTime.seconds / currentItem.asset.duration.seconds)
    
    delegate?.vendorNormalisedTimeUpdated(normalisedTime)
    
    if normalisedTime >= 1.0
    {
      paused = true
    }
  }
  
  func displayVideoFrame(time: CMTime) {
    guard let player = player,
      currentItem = player.currentItem where player.status == .ReadyToPlay && currentItem.status == .ReadyToPlay else {
        return
    }
    
    if videoOutput.hasNewPixelBufferForItemTime(time) {
      failedPixelBufferForItemTimeCount = 0
      
      var presentationItemTime = kCMTimeZero
      
      guard let pixelBuffer = videoOutput.copyPixelBufferForItemTime(
        time,
        itemTimeForDisplay: &presentationItemTime) else {
          return
      }
      
      unfilteredImage = CIImage(CVImageBuffer: pixelBuffer)
      
      displayFilteredImage()
    }
    else if let currentURL = currentURL where !paused {
      failedPixelBufferForItemTimeCount += 1
      
      if failedPixelBufferForItemTimeCount > 12 {
        openMovie(currentURL)
      }
    }
  }
  
  func displayFilteredImage() {
    guard let unfilteredImage = unfilteredImage,
      videoTransform = videoTransform else {
        return
    }
    
    let ciImage: CIImage
    
    if let ciFilter = ciFilter {
      ciFilter.setValue(unfilteredImage, forKey: kCIInputImageKey)
      
      ciImage = ciFilter.outputImage!.imageByApplyingTransform(videoTransform)
    }
    else {
      ciImage = unfilteredImage.imageByApplyingTransform(videoTransform)
    }
    
    let cgImage = ciContext.createCGImage(
      ciImage,
      fromRect: ciImage.extent)
    
    delegate?.finalOutputUpdated(UIImage(CGImage: cgImage))
  }
  
}

protocol FilteredVideoVendorDelegate: class {
  func finalOutputUpdated(image: UIImage)
  func vendorNormalisedTimeUpdated(normalisedTime: Float)
}