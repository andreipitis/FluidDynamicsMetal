//
//  ViewController.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 01/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {

    struct StaticData {
        var position: float2
        var impulse: float2

        var placeholder: float2 = float2(0.0, 0.0)

        var screenSize: float2
    }

    var metalView: MTKView {
        return view as! MTKView
    }

    var width: Int {
        return Int(metalView.bounds.width)
    }

    var height: Int {
        return Int(metalView.bounds.height)
    }

    var isPaused: Bool = false

    fileprivate var computeShader: ComputeShader!
    fileprivate var renderShader: RenderShader!

    fileprivate var staticBuffer: MTLBuffer!

    var initialTouchPosition: CGPoint?
    var touchDirection: CGPoint?

    var velocity: Slab!
    var pressure: Slab!

    fileprivate let vertexBuffer = MetalDevice.sharedInstance.buffer(array: vertexData)
    fileprivate let textureBuffer = MetalDevice.sharedInstance.buffer(array: TextureRotation.none.rotation())

    fileprivate let semaphore = DispatchSemaphore(value: 3)

    override func viewDidLoad() {
        super.viewDidLoad()

        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60
        metalView.delegate = self

        print("screenSize = \(metalView.bounds.size)")

        velocity = Slab(width: width, height: height)
        //        pressure = Slab(width: width, height: height)

        computeShader = ComputeShader(computeShader: "visualize")
        renderShader = RenderShader(fragmentShader: "visualizeVector", vertexShader: "vertexShader")

        let bufferSize = MemoryLayout<StaticData>.size

        var staticData = StaticData(position: float2(0.0, 0.0), impulse: float2(0.0, 0.0), placeholder: float2(0.0, 0.0), screenSize: float2(Float(UIScreen.main.bounds.width), Float(UIScreen.main.bounds.height)))
        staticBuffer = MetalDevice.sharedInstance.device.makeBuffer(bytes: &staticData, length: bufferSize, options: .cpuCacheModeWriteCombined)
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

        let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

        let pos = float2(x: 0.0 , y: 0.0)
        let impulse = float2(x: 0.0, y: 0.0)
        bufferData.pointee.position = pos
        bufferData.pointee.impulse = impulse
        memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = nil

        let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

        let pos = float2(x: 0.0 , y: 0.0)
        let impulse = float2(x: 0.0, y: 0.0)
        bufferData.pointee.position = pos
        bufferData.pointee.impulse = impulse
        memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
    }
}

extension ViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        semaphore.wait()

        if let initialTouch = initialTouchPosition, let direction = touchDirection {
            let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

            let pos = float2(x: Float(initialTouch.x) , y: Float(initialTouch.y))
            let impulse = normalize(float2(x: Float(initialTouch.x - direction.x), y: Float(initialTouch.y - direction.y)))

            if pos.x.isNaN == false && pos.y.isNaN == false && impulse.x.isNaN == false && impulse.y.isNaN == false {

                bufferData.pointee.position = pos
                bufferData.pointee.impulse = impulse

                print("impulse = \(impulse)")

                memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
            }
        }

        if let drawable = view.currentDrawable {
            let nextTexture = drawable.texture
            let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()

            computeShader.calculateWithCommandBuffer(buffer: commandBuffer, configureEncoder: { commandEncoder in
                commandEncoder.setTexture(self.velocity.ping, at: 0)
                commandEncoder.setTexture(self.velocity.ping, at: 1)
                commandEncoder.setTexture(self.velocity.pong, at: 2)

                commandEncoder.setBuffer(self.staticBuffer, offset: 0, at: 0)

                let threadGroupCouts = MTLSize(width: 4, height: 4, depth: 1)
                let threadGroups = MTLSize(width: self.width / threadGroupCouts.width, height: self.height / threadGroupCouts.height, depth: 1)
                commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCouts)
            })

            velocity.swap()
            
            renderShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: nextTexture, configureEncoder: { (commandEncoder) in
                commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, at: 0)
                commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, at: 1)
                commandEncoder.setFragmentTexture(self.velocity.ping, at: 0)
            })

            commandBuffer.addCompletedHandler({ (commandBuffer) in
                self.semaphore.signal()
            })

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        touchDirection = initialTouchPosition
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}

