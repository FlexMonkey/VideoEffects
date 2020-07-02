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
    
    let progressBar = UIProgressView(progressViewStyle: .default)
    let imageView = UIImageView()
    
    lazy var controlPanel: VideoEffectsControlPanel = {
        [unowned self] in
        
        let controlPanel = VideoEffectsControlPanel()
        
        controlPanel.addTarget(
            self,
            action: #selector(openMovie),
            for: VideoEffectsControlPanel.LoadControlEvent)
        
        controlPanel.addTarget(
            self,
            action: #selector(playPauseToggle),
            for: VideoEffectsControlPanel.PlayPauseControlEvent)
        
        controlPanel.addTarget(
            self,
            action: #selector(save),
            for: VideoEffectsControlPanel.SaveControlEvent)
        
        controlPanel.addTarget(
            self,
            action: #selector(filterChange),
            for: VideoEffectsControlPanel.FilterChangeControlEvent)
        
        controlPanel.addTarget(
            self,
            action: #selector(scrub),
            for: VideoEffectsControlPanel.ScrubControlEvent)
        
        return controlPanel
        }()
    
    // MARK: CIFilter
    
    var ciFilter: CIFilter? {
        didSet {
            controlPanel.saveButton.isEnabled = ciFilter != nil
            
            filteredVideoVendor.ciFilter = ciFilter
        }
    }
    
    // MARK: State variables
    
    var saving = false {
        didSet {
            backgroundColor = saving ? UIColor.darkGray : UIColor.white
            
            imageView.alpha = saving ? 0.2 : 1
            
            controlPanel.isEnabled = !saving
            
            progressBar.isHidden = !saving
            
            if let player = filteredVideoVendor.player,
                let ciFilter = filteredVideoVendor.ciFilter,
                let videoTransform = filteredVideoVendor.videoTransform, saving
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
    
    @objc func playPauseToggle() {
        paused = controlPanel.paused
    }
    
    @objc func save() {
        saving = true
    }
    
    @objc func filterChange() {
        ciFilter = CIFilter(name: "CIPhotoEffect" + controlPanel.filterDisplayName)
    }
    
    @objc func scrub() {
        paused = true
        
        filteredVideoVendor.gotoNormalisedTime(normalisedTime: controlPanel.normalisedTime)
    }
    
    @objc func openMovie(){
        
        guard let url = controlPanel.url else {
            return
        }
        
        filteredVideoVendor.openMovie(url: url)
        
        controlPanel.filterButtons.forEach{
            $0.isEnabled = true
        }
        
        controlPanel.scrubber.isEnabled = true
        controlPanel.saveButton.isEnabled = ciFilter != nil
        
        self.paused = false
    }
    
    // MARK: Overridden UI methods
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        imageView.contentMode = .scaleAspectFit
        progressBar.isHidden = true
        
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
