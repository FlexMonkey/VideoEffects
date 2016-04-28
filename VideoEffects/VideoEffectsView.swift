//  VideoEffectsView.swift
//  VideoEffects
//
//  Created by Simon Gladman on 17/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit
import AVFoundation

class VideoEffectsView: UIView
{
  
  // MARK: Video filtering components
  
  lazy var filteredVideoVendor: FilteredVideoVendor = {
    [unowned self] in
    
    let vendor = FilteredVideoVendor()
    vendor.delegate = self
    
    return vendor
    }()
  
  lazy var filteredVideoWriter: FilteredVideoWriter = {
    [unowned self] in
    
    let writer = FilteredVideoWriter()
    writer.delegate = self
    
    return writer
    }()
  
  // MARK: User Interface components
  
  let progressBar = UIProgressView(progressViewStyle: .Default)
  let imageView = UIImageView()
  
  lazy var controlPanel: VideoEffectsControlPanel = {
    [unowned self] in
    
    let controlPanel = VideoEffectsControlPanel()
    
    controlPanel.addTarget(
      self,
      action: #selector(VideoEffectsView.openMovie),
      forControlEvents: VideoEffectsControlPanel.LoadControlEvent)
    
    controlPanel.addTarget(
      self,
      action: #selector(VideoEffectsView.playPauseToggle),
      forControlEvents: VideoEffectsControlPanel.PlayPauseControlEvent)
    
    controlPanel.addTarget(
      self,
      action: #selector(VideoEffectsView.save),
      forControlEvents: VideoEffectsControlPanel.SaveControlEvent)
    
    controlPanel.addTarget(
      self,
      action: #selector(VideoEffectsView.filterChange),
      forControlEvents: VideoEffectsControlPanel.FilterChangeControlEvent)
    
    controlPanel.addTarget(
      self,
      action: #selector(VideoEffectsView.scrub),
      forControlEvents: VideoEffectsControlPanel.ScrubControlEvent)
    
    return controlPanel
    }()
  
  // MARK: CIFilter
  
  var ciFilter: CIFilter? {
    didSet {
      controlPanel.saveButton.enabled = ciFilter != nil
      
      filteredVideoVendor.ciFilter = ciFilter
    }
  }
  
  // MARK: State variables
  
  var saving = false {
    didSet {
      backgroundColor = saving ? UIColor.darkGrayColor() : UIColor.whiteColor()
      
      imageView.alpha = saving ? 0.2 : 1
      
      controlPanel.enabled = !saving
      
      progressBar.hidden = !saving
      
      if let player = filteredVideoVendor.player,
        ciFilter = filteredVideoVendor.ciFilter,
        videoTransform = filteredVideoVendor.videoTransform where saving
      {
        paused = true
        filteredVideoWriter.beginSaving(
          player: player,
          ciFilter: ciFilter,
          videoTransform: videoTransform,
          videoOutput: filteredVideoVendor.videoOutput)
      }
    }
  }
  
  var paused = true {
    didSet {
      controlPanel.paused = paused
      filteredVideoVendor.paused = paused
    }
  }
  
  // MARK: Control panel event handlers
  
  func playPauseToggle() {
    paused = controlPanel.paused
  }
  
  func save() {
    saving = true
  }
  
  func filterChange() {
    ciFilter = CIFilter(name: "CIPhotoEffect" + controlPanel.filterDisplayName)
  }
  
  func scrub() {
    paused = true
    
    filteredVideoVendor.gotoNormalisedTime(controlPanel.normalisedTime)
  }
  
  func openMovie(){
    guard let url = controlPanel.url else {
      return
    }
    
    filteredVideoVendor.openMovie(url)
    
    controlPanel.filterButtons.forEach{
      $0.enabled = true
    }
    
    controlPanel.scrubber.enabled = true
    controlPanel.saveButton.enabled = ciFilter != nil
    
    self.paused = false
  }
  
  // MARK: Overridden UI methods

  override func didMoveToWindow() {
    super.didMoveToWindow()
    
    imageView.contentMode = .ScaleAspectFit
    progressBar.hidden = true
    
    addSubview(imageView)
    addSubview(controlPanel)
    addSubview(progressBar)
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    let controlsStackViewHeight: CGFloat = 90
    
    imageView.frame = CGRect(
      x: 0,
      y: 0,
      width: frame.width,
      height: frame.height - controlsStackViewHeight).insetBy(dx: 10, dy: 10)
    
    controlPanel.frame = CGRect(
      x: 0,
      y: frame.height - controlsStackViewHeight,
      width: frame.width,
      height: controlsStackViewHeight)
    
    progressBar.frame = CGRect(
      x: 0,
      y: frame.midY,
      width: frame.width, height: 20).insetBy(dx: 20, dy: 0)
  }
  
}

// MARK: FilteredVideoVendorDelegate

extension VideoEffectsView: FilteredVideoVendorDelegate {
  
  func finalOutputUpdated(image: UIImage) {
    imageView.image = image
  }
  
  func vendorNormalisedTimeUpdated(normalisedTime: Float) {
    controlPanel.normalisedTime = Double(normalisedTime)
  }
}

// MARK: FilteredVideoWriterDelegate

extension VideoEffectsView: FilteredVideoWriterDelegate {
  
  func updateSaveProgress(progress: Float) {
    progressBar.setProgress(progress, animated: true)
  }
  
  func saveComplete() {
    progressBar.setProgress(0, animated: false)
    saving = false
    controlPanel.normalisedTime = 0
    paused = false
  }
}
