# VideoEffects
### iPad app to open videos from file system, apply Core Image filters and save result back to Saved Photos Album

If you've ever used an application such as Adobe's After Effects, you'll know how much creative potential there is adding and animating filters to video files. If you've worked with Apple's Core Image framework, you may well have added filters to still images or even live video feeds, but working with video files and saving the results back to a device isn't a trivial coding challenge. 

Well, my VideoEffects app solves that challenge for you: VideoEffects allows a user to open a video file, apply a Core Image Photo Effects filter and write the filtered movie back to the saved photos album. 

## VideoEffects Overview

The VideoEffects project consists of four main files:

* **VideoEffectsView:** this is the main user interface component. It contains an image view and a control bar.
* **VideoEffectsControlPanel:** Contains a scrubber bar, filter selection and play, pause, load and save buttons.
* **FilteredVideoVendor:** Vends filtered image frames
* **FilteredVideoWriter:** Writes frames from the vendor to the file system

The first action a user needs to take is to press "load" in the bottom left of the screen. This opens a standard image picker filtered for the movie media type. Once a movie is opened, it's displayed on the screen where the user can either play/pause or use the slider as a scrub bar. If any of the filters are selected, the save button is enabled which will save a filtered version of the video back to the file system.

Let's look at the vendor and writer code in detail.

## Filtered Video Vendor

The first job of the vendor class is to actually open a movie from a URL supplied by the "load" button in the control panel:

```swift
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
```  

There are a few interesting points here: firstly, I reset a variable named `failedPixelBufferForItemTimeCount` - this is a workaround for what I think is a bug in AVFoundation with videos that would occasionally fail to load with no apparent error. Secondly, to support both landscape and portrait videos, I create an inverted version of the video track's preferred transform.

The vendor contains a `CADisplayLink` which invokes `step(_:)`: 

```swift
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
```

With the `CADisplayLink`, I  calculate the time for the `AVPlayerItem` based on `CACurrentMediaTime`. The normalised time (i.e. between 0 and 1) is calculated by dividing the player item's time by the assets duration, this is used by the UI components to set the scrub bar's position during playback. Creating a `CIImage` from the movie's frame at `itemTime` is done in `displayVideoFrame(_:)`:

```swift
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
```

Before copying a pixel buffer from the video output, I need to ensure one is available. If that's all good, it's a simple step to create a `CIImage` from that pixel buffer. However, if `hasNewPixelBufferForItemTime(_:)` fails too many times (12 seems to work), I assume AVFoundation has silently failed and I reopen the movie.

With the populated `CIImage`, I apply a filter (if there is one) and return the rendered result back to the delegate (which is the main view) to be displayed:

```swift
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
```

The vendor can also jump to a specific normalised time. Here, rather than relying on the `CACurrentMediaTime`, I create a `CMTime` and pass that to `displayVideoFrame(_:)`:

```swift
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
```  

## Filtered Video Writer

Writing the result is not the simplest coding task I've ever done. I'll explain the highlights, the full code is available here.

The writer class exposes a function, `beginSaving(player:ciFilter:videoTransform:videoOutput)` which begins the writing process.

Writing is actually done to a temporary file in the documents directory and given a file name based on the current time:

```swift
  let urls = NSFileManager
    .defaultManager()
    .URLsForDirectory(
        .DocumentDirectory,

        inDomains: .UserDomainMask)

  videoOutputURL = documentDirectory
      .URLByAppendingPathComponent("Output_\(timeDateFormatter.stringFromDate(NSDate())).mp4")

  do {
    videoWriter = try AVAssetWriter(URL: videoOutputURL!, fileType: AVFileTypeMPEG4)
  }
  catch {
    fatalError("** unable to create asset writer **")
  }
```

The next step is to create an asset writer input using H264 and of the correct size:

```swift
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
```      

The video writer input is added to an `AVAssetWriter`:

```swift
    videoWriterInput = AVAssetWriterInput(
      mediaType: AVMediaTypeVideo,
      outputSettings: outputSettings)
    
    if videoWriter!.canAddInput(videoWriterInput!) {
      videoWriter!.addInput(videoWriterInput!)
    }
    else {
      fatalError ("** unable to add input **")
    }
```    

The final set up step for initialising is to create a pixel buffer adaptor:

```swift
    let sourcePixelBufferAttributesDictionary = [
      String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_32BGRA),
      String(kCVPixelBufferWidthKey) : currentItem.presentationSize.width,
      String(kCVPixelBufferHeightKey) : currentItem.presentationSize.height,
      String(kCVPixelFormatOpenGLESCompatibility) : kCFBooleanTrue
    ]
    
    assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoWriterInput!,
      sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary)
```

We're now ready to actually start writing. I'll rewind the player to the beginning of the movie and, since that is asynchronous, call `writeVideoFrames` in the seek completion handler:

```swift
    player.seekToTime(
      CMTimeMakeWithSeconds(0, 600),
      toleranceBefore: kCMTimeZero,
      toleranceAfter: kCMTimeZero)
    {
      _ in self.writeVideoFrames()
    }
```    

`writeVideoFrames` writes the frames to the temporary file. It's basically a loop over each frame, incrementing the frame with each iteration. The number of frames is calculated as:

```swift
    let numberOfFrames = Int(duration.seconds * Double(frameRate))
```

There was an intermittent bug where, again, `hasNewPixelBufferForItemTime(_:)` failed. This is fixed with a slightly ugly sleep:

```swift
    NSThread.sleepForTimeInterval(0.05)
```    

In this loop, I do something very similar to the vendor: convert a pixel buffer from the video output to a `CIImage`, filter and render it. However, I'm not rendering to a `CGImage` for display, I'm rendering back to a `CVPixelBuffer` to append to the asset write pixel buffer. The pixel buffer adaptor has a pixel buffer pool I take pixel buffers from which are passed to the Core Image context as a render target:

```swift
    ciFilter.setValue(transformedImage, forKey: kCIInputImageKey)
    
    var newPixelBuffer: CVPixelBuffer? = nil
    
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &newPixelBuffer)
    
    self.ciContext.render(
      ciFilter.outputImage!,
      toCVPixelBuffer: newPixelBuffer!,
      bounds: ciFilter.outputImage!.extent,
      colorSpace: nil)
```

`transformedImage` is the filtered `CIImage` rotated based on the original assets preferred transform.  

Now that the new pixel buffer contains the rendered filtered image, it's appended to the pixel buffer adaptor:

```swift
    assetWriterPixelBufferInput.appendPixelBuffer(
      newPixelBuffer!,
      withPresentationTime: presentationItemTime)
```      

The final part of the loop kernel is to increment the frame:

```swift
    currentItem.stepByCount(1)
```    

Once I've looped over each frame, the video write input is marked as finished and the video writer's `finishWritingWithCompletionHandler(_:)` is invoked. In the completion handler, I rewind the player back to the beginning and copy the temporary video into the saved photos album:

```swift
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
```      

...and once the video is copied, I can delete the temporary file:

```swift
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
```  

Easy! 

## Conclusion

I've been wanting to write this code for almost two years and it proved a lot more "interesting" than I anticipated. There are two slightly hacky workarounds in there, but the end result is the foundation for a tremendously powerful app. At every frame, the normalised time is available and this can be used to animate the attributes of filters and opens the way for a powerful After Effects style application.
