//
//  ViewController.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 01/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import UIKit
import MetalKit

struct StaticData {
    var position: float2
    var impulse: float2
}

class ViewController: UIViewController {

    var metalView: MTKView {
        return view as! MTKView
    }

    var isPaused: Bool = false

    private var basicFilter: ComputeShader!

    private var staticBuffer: MTLBuffer!

    var initialTouchPosition: CGPoint?
    var touchDirection: CGPoint?

    override func viewDidLoad() {
        super.viewDidLoad()

        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60
        metalView.delegate = self

        basicFilter = ComputeShader(computeShader: "visualize")

        let bufferSize = MemoryLayout<StaticData>.size
        staticBuffer = MetalDevice.sharedInstance.device.makeBuffer(length: bufferSize, options: .cpuCacheModeWriteCombined)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = touches.first?.location(in: touches.first?.view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = touches.first?.location(in: touches.first?.view)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = nil
    }
}

extension ViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        if let initialTouch = initialTouchPosition, let direction = touchDirection {
            let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

            let pos = float2(x: Float(initialTouch.x * UIScreen.main.scale), y: Float(initialTouch.y * UIScreen.main.scale))
            let impulse = float2(x: Float(initialTouch.x - direction.x), y: Float(initialTouch.y - direction.y))

            bufferData.pointee.position = pos
            bufferData.pointee.impulse = impulse

            memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
        }

        if let drawable = view.currentDrawable {
            let nextTexture = drawable.texture
            let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()

            basicFilter.calculateWithCommandBuffer(buffer: commandBuffer, configureEncoder: { commandEncoder in
                commandEncoder.setTexture(nextTexture, index: 1)

                commandEncoder.setBuffer(self.staticBuffer, offset: 0, index: 0)

                let threadGroupCouts = MTLSize(width: 8, height: 8, depth: 1)
                let threadGroups = MTLSize(width: nextTexture.width / threadGroupCouts.width, height: nextTexture.height / threadGroupCouts.height, depth: 1)
                commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCouts)
            })

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        touchDirection = initialTouchPosition
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}

