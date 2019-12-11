//
//  PoseMatchingViewController.swift
//  PoseEstimation-CoreML
//
//  Created by Doyoung Gwak on 13/08/2019.
//  Copyright © 2019 tucan9389. All rights reserved.
//

import UIKit
import CoreMedia
import Vision

class PoseMatchingViewController: UIViewController, StreamDelegate {

    // MARK: - UI Property
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var jointView: DrawingJointView!
    @IBOutlet var capturedJointViews: [DrawingJointView]!
    @IBOutlet var capturedJointConfidenceLabels: [UILabel]!
    @IBOutlet var capturedJointBGViews: [UIView]!
    var capturedPointsArray: [[CapturedPoint?]?] = []
    
    var capturedIndex = 0
    var matchCounter = 0
    var lastMatch = -1
    // MARK: - AV Property
    var videoCapture: VideoCapture!
    
    // MARK: - ML Properties
    // Core ML model
    typealias EstimationModel = model_cpm
    
    // Preprocess and Inference
    var request: VNCoreMLRequest?
    var visionModel: VNCoreMLModel?
    
    // Postprocess
    var postProcessor: HeatmapPostProcessor = HeatmapPostProcessor()
    var mvfilters: [MovingAverageFilter] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup the drawing views
        setUpCapturedJointView()

        // setup the model
        setUpModel()
        
        // setup camera
        setUpCamera()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.videoCapture.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.videoCapture.stop()
    }
    
    // MARK: - Setup Captured Joint View
    func setUpCapturedJointView() {
        postProcessor.onlyBust = true
        
        for capturedJointView in capturedJointViews {
            capturedJointView.layer.borderWidth = 2
            capturedJointView.layer.borderColor = UIColor.gray.cgColor
        }
        
        capturedPointsArray = capturedJointViews.map { _ in return nil }
        
        for currentIndex in 0..<capturedPointsArray.count {
            // retrieving a value for a key
            if let data = UserDefaults.standard.data(forKey: "points-\(currentIndex)"),
                let capturedPoints = NSKeyedUnarchiver.unarchiveObject(with: data) as? [CapturedPoint?] {
                capturedPointsArray[currentIndex] = capturedPoints
                capturedJointViews[currentIndex].bodyPoints = capturedPoints.map { capturedPoint in
                    if let capturedPoint = capturedPoint { return PredictedPoint(capturedPoint: capturedPoint) }
                    else { return nil }
                }
            }
        }
    }
    
    // MARK: - Setup Core ML
    func setUpModel() {
        if let visionModel = try? VNCoreMLModel(for: EstimationModel().model) {
            self.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .centerCrop
        } else {
            fatalError("cannot load the ml model")
        }
    }
    
    // MARK: - SetUp Video
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 30
        videoCapture.setUp(sessionPreset: .vga640x480, cameraPosition: .back) { success in
            
            if success {
                // add preview view on the layer
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                // start video preview when setup is done
                self.videoCapture.start()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizePreviewLayer()
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    // CAPTURE THE CURRENT POSE
    @IBAction func tapCapture(_ sender: Any) {
        let currentIndex = capturedIndex % capturedJointViews.count
        let capturedJointView = capturedJointViews[currentIndex]
        
        let predictedPoints = jointView.bodyPoints
        capturedJointView.bodyPoints = predictedPoints
        let capturedPoints: [CapturedPoint?] = predictedPoints.map { predictedPoint in
            guard let predictedPoint = predictedPoint else { return nil }
            return CapturedPoint(predictedPoint: predictedPoint)
        }
        capturedPointsArray[currentIndex] = capturedPoints
        
        let encodedData = NSKeyedArchiver.archivedData(withRootObject: capturedPoints)
        UserDefaults.standard.set(encodedData, forKey: "points-\(currentIndex)")
        print(UserDefaults.standard.synchronize())
        
        capturedIndex += 1
    }
    
    @IBOutlet weak var addr_input: UITextField!
//    @IBOutlet weak var page_up_button: UIButton!
//    @IBOutlet weak var page_down_button: UIButton!
    
    func page_up() {
            print("page up")
            outputStream?.write("u",maxLength: 1)
        }
    func page_down() {
            print("page down")
            outputStream?.write("d",maxLength: 1)
        }
        
        var addr = "127.0.0.1"
        let port = 7673
        var inputStream: InputStream?
        var outputStream: OutputStream?
        
        @IBAction func connect(_ sender: Any) {
            view.endEditing(true)
            addr = addr_input.text!;
            print("Connecting to server @ " + addr)
            Stream.getStreamsToHost(withName: addr, port: port, inputStream: &inputStream, outputStream: &outputStream)
            
            outputStream?.delegate = self
            outputStream?.schedule(in: .current, forMode: .common)
            outputStream?.open()
        }
        
        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            if (eventCode == Stream.Event.hasSpaceAvailable) {
                print("Server connected")
//                page_down_button.isEnabled = true
//                page_up_button.isEnabled = true
            }else{
//                page_up_button.isEnabled = false
//                page_down_button.isEnabled = false
            }
        }
}

// MARK: - VideoCaptureDelegate
extension PoseMatchingViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        // the captured image from camera is contained on pixelBuffer
        if let pixelBuffer = pixelBuffer {
            predictUsingVision(pixelBuffer: pixelBuffer)
        }
    }
}

extension PoseMatchingViewController {
    // MARK: - Inferencing
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        guard let request = request else { fatalError() }
        // vision framework configures the input size of image following our model's input configuration automatically
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
    
    // MARK: - Postprocessing
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
            let heatmaps = observations.first?.featureValue.multiArrayValue else { return }
        
        /* =================================================================== */
        /* ========================= post-processing ========================= */
        
        /* ------------------ convert heatmap to point array ----------------- */
        var predictedPoints = postProcessor.convertToPredictedPoints(from: heatmaps, isFlipped: false)
        
        /* --------------------- moving average filter ----------------------- */
        if predictedPoints.count != mvfilters.count {
            mvfilters = predictedPoints.map { _ in MovingAverageFilter(limit: 3) }
        }
        for (predictedPoint, filter) in zip(predictedPoints, mvfilters) {
            filter.add(element: predictedPoint)
        }
        predictedPoints = mvfilters.map { $0.averagedValue() }
        /* =================================================================== */
        
        let matchingRatios = capturedPointsArray
            .map { $0?.matchVector(with: predictedPoints) }
            .compactMap { $0 }
        
        
        
        /* =================================================================== */
        /* ======================= display the results ======================= */
        DispatchQueue.main.sync { [weak self] in
            guard let self = self else { return }
            // draw line
            self.jointView.bodyPoints = predictedPoints
            //let indexArray = [0,1,2,3]
            var topCapturedJointBGView: UIView?
            var maxMatchingRatio: CGFloat = 0
            var matchIndex = -1;
            var index  = -1;
            for (matchingRatio, (capturedJointBGView, capturedJointConfidenceLabel)) in zip(matchingRatios, zip(self.capturedJointBGViews, self.capturedJointConfidenceLabels)) {
                index = index + 1
                let text = String(format: "%.2f%", matchingRatio*100)
                capturedJointConfidenceLabel.text = text
                capturedJointBGView.backgroundColor = .clear
                if matchingRatio > 0.80 && maxMatchingRatio < matchingRatio {
                    matchIndex = index
                    maxMatchingRatio = matchingRatio
                    topCapturedJointBGView = capturedJointBGView
                }
            }
            print(matchIndex)
            
         
            if matchIndex != -1{
                print(matchIndex)
                if matchCounter == 0{
                    if matchIndex == 0 || matchIndex == 2{
                        matchCounter = 1
                        lastMatch = matchIndex
                        print(matchIndex)
                    }
                }
                if matchCounter == 1{
                    if lastMatch==0{
                        if matchIndex != 0{
                            if matchIndex == 1{
                            page_up()
                            print("page up")
                            }
                            lastMatch = -1
                            matchCounter = 0
                        }
                    }else if lastMatch==2 {
                        if matchIndex != 2{
                            if matchIndex == 3{
                            page_down()
                            print("page down")
                            }
                            lastMatch = -1
                            matchCounter = 0
                        }
                    }else{
                       lastMatch = -1
                       matchCounter = 0
                    }
                    
                }
            }

            
            topCapturedJointBGView?.backgroundColor = UIColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 0.4)
//            print(matchingRatios)
        }
        /* =================================================================== */
    }
}
