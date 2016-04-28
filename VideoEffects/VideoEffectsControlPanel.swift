//  VideoEffectsControlPanel.swift
//  VideoEffects
//
//  Created by Simon Gladman on 17/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit
import MobileCoreServices

class VideoEffectsControlPanel: UIControl
{
  static let PlayPauseControlEvent =    UIControlEvents(rawValue: 0b0001 << 24)
  static let LoadControlEvent =         UIControlEvents(rawValue: 0b0010 << 24)
  static let SaveControlEvent =         UIControlEvents(rawValue: 0b0100 << 24)
  static let ScrubControlEvent =        UIControlEvents(rawValue: 0b1000 << 24)
  static let FilterChangeControlEvent = UIControlEvents.ValueChanged
  
  lazy var toolbar: UIToolbar = {
    [unowned self] in
    
    let toolbar = UIToolbar()
    
    let flexibleSpacer = UIBarButtonItem(
      barButtonSystemItem: .FlexibleSpace,
      target: nil,
      action: nil)
    
    let playButton = UIBarButtonItem(
      barButtonSystemItem: .Play,
      target: self,
      action: #selector(VideoEffectsControlPanel.play))
    
    let pauseButton = UIBarButtonItem(
      barButtonSystemItem: .Pause,
      target: nil,
      action: #selector(VideoEffectsControlPanel.pause))
    
    let loadButton = UIBarButtonItem(
      title: "Load",
      style: .Plain,
      target: nil,
      action: #selector(VideoEffectsControlPanel.load))
    
    let saveButton = UIBarButtonItem(
      title: "Save",
      style: .Plain,
      target: nil,
      action: #selector(VideoEffectsControlPanel.save))
    
    saveButton.enabled = false
    playButton.enabled = false
    pauseButton.enabled = false
    
    var items = [playButton, pauseButton, flexibleSpacer] + self.filterButtons + [flexibleSpacer, loadButton, saveButton]
    
    self.filterButtons.forEach{
      $0.enabled = false
    }
    
    self.filterButtons[0].style = .Done
    
    toolbar.setItems(
      items,
      animated: false)
    
    return toolbar
    }()
  
  lazy var scrubber: UISlider = {
    [unowned self] in
    
    let slider = UISlider()
    
    slider.maximumTrackTintColor = UIColor.lightGrayColor()
    slider.minimumTrackTintColor = UIColor.lightGrayColor()
    
    slider.addTarget(
      self,
      action: #selector(VideoEffectsControlPanel.scrubberHandler),
      forControlEvents: .ValueChanged)
    
    slider.enabled = false
    
    return slider
  }()
  
  lazy var controlsStackView: UIStackView = {
    [unowned self] in
    
    let stackview = UIStackView()
    
    stackview.axis = .Vertical
    stackview.addArrangedSubview(self.scrubber)
    stackview.addArrangedSubview(self.toolbar)
    
    return stackview
    }()
  
  lazy var filterButtons: [UIBarButtonItem] = {
    [unowned self] in
    
    return self.filterDisplayNames.map {
      UIBarButtonItem(
        title: $0,
        style: .Plain,
        target: self,
        action: #selector(VideoEffectsControlPanel.setFilter(_:)))
    }
    }()
  
  lazy var imagePicker: UIImagePickerController = {
    [unowned self] in
    
    let imagePicker = UIImagePickerController()
    
    imagePicker.delegate = self
    imagePicker.allowsEditing = false
    imagePicker.modalInPopover = true
    imagePicker.sourceType = .PhotoLibrary
    imagePicker.mediaTypes = [kUTTypeMovie as String]
    
    return imagePicker
    }()
  
  let filterDisplayNames = [
    "None", "Chrome", "Fade", "Instant", "Mono", "Noir", "Process", "Tonal", "Transfer"]
  
  var playButton: UIBarButtonItem {
    return toolbar.items!.first! as UIBarButtonItem
  }
  
  var pauseButton: UIBarButtonItem {
    return toolbar.items![1] as UIBarButtonItem
  }
  
  var saveButton: UIBarButtonItem {
    return toolbar.items!.last! as UIBarButtonItem
  }
  
  var normalisedTime: Double
  {
    set {
      scrubber.value = Float(newValue)
    }
    get {
      return Double(scrubber.value)
    }
  }
  
  var rootViewController: UIViewController {
    return UIApplication.sharedApplication().keyWindow!.rootViewController!
  }
  
  private (set) var url: NSURL?
  private (set) var filterDisplayName = "None"
  
  var paused = true {
    didSet {
      playButton.enabled = paused
      pauseButton.enabled = !paused
    }
  }
  
  override var enabled: Bool {
    didSet {
      alpha = enabled ? 1 : 0.2
    }
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    addSubview(controlsStackView)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func play() {
    paused = false
    sendActionsForControlEvents(VideoEffectsControlPanel.PlayPauseControlEvent)
  }
  
  func pause() {
    paused = true
    sendActionsForControlEvents(VideoEffectsControlPanel.PlayPauseControlEvent)
  }
  
  func load() {
    paused = true
    sendActionsForControlEvents(VideoEffectsControlPanel.PlayPauseControlEvent)
    
    rootViewController.presentViewController(imagePicker, animated: true, completion: nil)
  }
  
  func save() {
    sendActionsForControlEvents(VideoEffectsControlPanel.SaveControlEvent)
  }

  func scrubberHandler() {
    paused = true
    sendActionsForControlEvents(VideoEffectsControlPanel.ScrubControlEvent)
  }
  
  func setFilter(barButtonItem: UIBarButtonItem)
  {
    guard let
      filterDisplayName = barButtonItem.title,
      filterIndex = filterDisplayNames.indexOf(filterDisplayName) else {
        return
    }
    
    filterButtons.forEach{
      $0.style = .Plain
    }
    filterButtons[filterIndex].style = .Done
    
    self.filterDisplayName = filterDisplayName
    
    sendActionsForControlEvents(VideoEffectsControlPanel.FilterChangeControlEvent)
  }
  
  override func layoutSubviews() {
    controlsStackView.frame = bounds
    
    controlsStackView.spacing = 20
  }
}

// MARK: UIImagePickerControllerDelegate, UINavigationControllerDelegate

extension VideoEffectsControlPanel: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]){
    defer {
      rootViewController.dismissViewControllerAnimated(true, completion: nil)
    }
    
    guard let url = info[UIImagePickerControllerMediaURL] as? NSURL else {
      return
    }
    
    self.url = url
    
    sendActionsForControlEvents(VideoEffectsControlPanel.LoadControlEvent)
  }
}

