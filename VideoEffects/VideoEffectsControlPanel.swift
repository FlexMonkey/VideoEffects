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
    static let PlayPauseControlEvent =    UIControl.Event(rawValue: 0b0001 << 24)
    static let LoadControlEvent =         UIControl.Event(rawValue: 0b0010 << 24)
    static let SaveControlEvent =         UIControl.Event(rawValue: 0b0100 << 24)
    static let ScrubControlEvent =        UIControl.Event(rawValue: 0b1000 << 24)
    static let FilterChangeControlEvent = UIControl.Event.valueChanged
    
    lazy var toolbar: UIToolbar = {
        [unowned self] in
        
        let toolbar = UIToolbar()
        
        let flexibleSpacer = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil)
        
        let playButton = UIBarButtonItem(
            barButtonSystemItem: .play,
            target: self,
            action: #selector(play))
        
        let pauseButton = UIBarButtonItem(
            barButtonSystemItem: .pause,
            target: nil,
            action: #selector(pause))
        
        let loadButton = UIBarButtonItem(
            title: "Load",
            style: .plain,
            target: nil,
            action: #selector(load))
        
        let saveButton = UIBarButtonItem(
            title: "Save",
            style: .plain,
            target: nil,
            action: #selector(save))
        
        saveButton.isEnabled = false
        playButton.isEnabled = false
        pauseButton.isEnabled = false
        
        var items = [playButton, pauseButton, flexibleSpacer] + self.filterButtons + [flexibleSpacer, loadButton, saveButton]
        
        self.filterButtons.forEach{
            $0.isEnabled = false
        }
        
        self.filterButtons[0].style = .done
        
        toolbar.setItems(
            items,
            animated: false)
        
        return toolbar
        }()
    
    lazy var scrubber: UISlider = {
        [unowned self] in
        
        let slider = UISlider()
        
        slider.maximumTrackTintColor = UIColor.lightGray
        slider.minimumTrackTintColor = UIColor.lightGray
        
        slider.addTarget(
            self,
            action: #selector(VideoEffectsControlPanel.scrubberHandler),
            for: .valueChanged)
        
        slider.isEnabled = false
        
        return slider
        }()
    
    lazy var controlsStackView: UIStackView = {
        [unowned self] in
        
        let stackview = UIStackView()
        
        stackview.axis = .vertical
        stackview.addArrangedSubview(self.scrubber)
        stackview.addArrangedSubview(self.toolbar)
        
        return stackview
        }()
    
    lazy var filterButtons: [UIBarButtonItem] = {
        [unowned self] in
        
        return self.filterDisplayNames.map {
            UIBarButtonItem(
                title: $0,
                style: .plain,
                target: self,
                action: #selector(setFilter(barButtonItem:)))
        }
        }()
    
    lazy var imagePicker: UIImagePickerController = {
        [unowned self] in
        
        let imagePicker = UIImagePickerController()
        
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        imagePicker.isModalInPopover = true
        imagePicker.sourceType = .photoLibrary
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
        return UIApplication.shared.keyWindow!.rootViewController!
    }
    
    private (set) var url: URL?
    private (set) var filterDisplayName = "None"
    
    var paused = true {
        didSet {
            playButton.isEnabled = paused
            pauseButton.isEnabled = !paused
        }
    }
    
    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.2
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(controlsStackView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func play() {
        paused = false
        sendActions(for: VideoEffectsControlPanel.PlayPauseControlEvent)
    }
    
    @objc func pause() {
        paused = true
        sendActions(for: VideoEffectsControlPanel.PlayPauseControlEvent)
    }
    
    @objc func load() {
        paused = true
        sendActions(for: VideoEffectsControlPanel.PlayPauseControlEvent)
        
        rootViewController.present(imagePicker, animated: true, completion: nil)
    }
    
    @objc func save() {
        sendActions(for: VideoEffectsControlPanel.SaveControlEvent)
    }
    
    @objc func scrubberHandler() {
        paused = true
        sendActions(for: VideoEffectsControlPanel.ScrubControlEvent)
    }
    
    @objc func setFilter(barButtonItem: UIBarButtonItem)
    {
        guard let
            filterDisplayName = barButtonItem.title,
            let filterIndex = filterDisplayNames.firstIndex(of: filterDisplayName) else {
                return
        }
        
        filterButtons.forEach{
            $0.style = .plain
        }
        filterButtons[filterIndex].style = .done
        
        self.filterDisplayName = filterDisplayName
        
        sendActions(for: VideoEffectsControlPanel.FilterChangeControlEvent)
    }
    
    override func layoutSubviews() {
        controlsStackView.frame = bounds
        
        controlsStackView.spacing = 20
    }
}

// MARK: UIImagePickerControllerDelegate, UINavigationControllerDelegate

extension VideoEffectsControlPanel: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    private func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]){
        defer {
            rootViewController.dismiss(animated: true, completion: nil)
        }
        
        guard let url = info[UIImagePickerController.InfoKey.mediaURL.rawValue] as? URL else {
            return
        }
        
        self.url = url
        
        sendActions(for: VideoEffectsControlPanel.LoadControlEvent)
    }
}

