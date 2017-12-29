//
//  RenderViewController.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 19/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import UIKit
import MetalKit

let MaxBuffers = 3

class RenderViewController: UIViewController {

    var renderer: Renderer!
    var metalView: MTKView {
        return view as! MTKView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        renderer = Renderer(metalView: metalView)
        metalView.delegate = renderer

        metalView.isExclusiveTouch = true

        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(doubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.numberOfTouchesRequired = 1
        view.addGestureRecognizer(doubleTapGesture)

        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(changeSource))
        gestureRecognizer.numberOfTapsRequired = 2
        gestureRecognizer.numberOfTouchesRequired = 2
        view.addGestureRecognizer(gestureRecognizer)

        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: .UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .UIApplicationDidBecomeActive, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        print("Got Memory Warning")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let positions = touches.map { (touch) -> float2 in
            let position = touch.location(in: touch.view)
            return float2(Float(position.x), Float(position.y))
        }

        let tupleSize = MemoryLayout<FloatTuple>.size
        let arraySize = MemoryLayout<float2>.size * positions.count

        let tuple = malloc(tupleSize).assumingMemoryBound(to: FloatTuple.self)

        memset(tuple, 0, tupleSize)
        memcpy(tuple, positions, arraySize)

        renderer.updateInteraction(points: tuple.pointee, in: metalView)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let positions = touches.map { (touch) -> float2 in
            let position = touch.location(in: touch.view)
            return float2(Float(position.x), Float(position.y))
        }

        let tupleSize = MemoryLayout<FloatTuple>.size
        let arraySize = MemoryLayout<float2>.size * positions.count

        let tuple = malloc(tupleSize).assumingMemoryBound(to: FloatTuple.self)

        memset(tuple, 0, tupleSize)
        memcpy(tuple, positions, arraySize)

        renderer.updateInteraction(points: tuple.pointee, in: metalView)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.updateInteraction(points: nil, in: metalView)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        renderer.updateInteraction(points: nil, in: metalView)
    }

    @objc func changeSource() {
        renderer.nextSlab()
    }

    @objc final func doubleTap() {
        metalView.isPaused = !metalView.isPaused
    }

    @objc final func willResignActive() {
        metalView.isPaused = true
    }

    @objc final func didBecomeActive() {
        metalView.isPaused = false
    }
}
