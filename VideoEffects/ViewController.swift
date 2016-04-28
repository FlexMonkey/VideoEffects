//
//  ViewController.swift
//  VideoEffects
//
//  Created by Simon Gladman on 28/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    let videoEffectsView = VideoEffectsView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(videoEffectsView)
    }
    
    override func viewDidLayoutSubviews() {
        videoEffectsView.frame = CGRect(
            x: 0,
            y: topLayoutGuide.length,
            width: view.frame.width,
            height: view.frame.height - topLayoutGuide.length)
    }
    
}

