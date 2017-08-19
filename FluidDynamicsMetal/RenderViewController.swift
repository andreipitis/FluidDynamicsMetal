//
//  RenderViewController.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 19/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import UIKit

import UIKit
import MetalKit

class RenderViewController: UIViewController {

    struct StaticData {
        var position: float2
        var impulse: float2

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

    var isPaused: Bool {
        set {
            metalView.isPaused = newValue
        }

        get {
            return metalView.isPaused
        }
    }

    private var applyForceShader: RenderShader!
    private var advectShader: RenderShader!
    private var divergenceShader: RenderShader!
    private var jacobiShader: RenderShader!
    private var vorticityShader: RenderShader!
    private var vorticityConfinementShader: RenderShader!
    private var gradientShader: RenderShader!

    private var renderShader: RenderShader!

    private var staticBuffer: MTLBuffer!

    var initialTouchPosition: CGPoint?
    var touchDirection: CGPoint?

    var velocity: Slab!
    var density: Slab!
    var velocityDivergence: Slab!
    var velocityVorticity: Slab!
    var pressure: Slab!

    private let vertexBuffer = MetalDevice.sharedInstance.buffer(array: vertexData)
    private let textureBuffer = MetalDevice.sharedInstance.buffer(array: TextureRotation.none.rotation())

    private let semaphore = DispatchSemaphore(value: 3)

    private var currentIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60
        metalView.delegate = self

        print("screenSize = \(metalView.bounds.size)")

        velocity = Slab(width: width, height: height)
        density = Slab(width: width, height: height)
        velocityDivergence = Slab(width: width, height: height)
        velocityVorticity = Slab(width: width, height: height)
        pressure = Slab(width: width, height: height)

        applyForceShader = RenderShader(fragmentShader: "applyForce", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        advectShader = RenderShader(fragmentShader: "advect", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        divergenceShader = RenderShader(fragmentShader: "divergence", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        jacobiShader = RenderShader(fragmentShader: "jacobi", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        vorticityShader = RenderShader(fragmentShader: "vorticity", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        vorticityConfinementShader = RenderShader(fragmentShader: "vorticityConfinement", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        gradientShader = RenderShader(fragmentShader: "gradient", vertexShader: "vertexShader", pixelFormat: .rgba16Float)

        renderShader = RenderShader(fragmentShader: "fragmentShader", vertexShader: "vertexShader")

        let bufferSize = MemoryLayout<StaticData>.size

        var staticData = StaticData(position: float2(0.0, 0.0), impulse: float2(0.0, 0.0), screenSize: float2(Float(UIScreen.main.bounds.width), Float(UIScreen.main.bounds.height)))
        staticBuffer = MetalDevice.sharedInstance.device.makeBuffer(bytes: &staticData, length: bufferSize, options: .cpuCacheModeWriteCombined)

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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        print("Got Memory Warning")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = touches.first?.location(in: touches.first?.view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = touches.first?.location(in: touches.first?.view)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = nil

        resetConstantBuffer()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        initialTouchPosition = nil

        resetConstantBuffer()
    }

    private func resetConstantBuffer() {
        let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

        let pos = float2(x: 0.0 , y: 0.0)
        let impulse = float2(x: 0.0, y: 0.0)
        bufferData.pointee.position = pos
        bufferData.pointee.impulse = impulse
        memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
    }

    @objc func changeSource() {
        currentIndex = (currentIndex + 1) % 4
    }

    @objc func doubleTap() {
        isPaused = !isPaused
    }

    @objc func willResignActive() {
        isPaused = true
    }

    @objc func didBecomeActive() {
        isPaused = false
    }

    fileprivate func drawSlab() -> Slab {
        switch currentIndex {
        case 1:
            return velocity
        case 2:
            return velocityVorticity
        case 3:
            return pressure
        default:
            return density
        }
    }

    func advect(commandBuffer: MTLCommandBuffer, velocity: Slab, source: Slab, destination: Slab) {
        advectShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
            commandEncoder.setFragmentTexture(source.ping, index: 1)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func applyForce(commandBuffer: MTLCommandBuffer, destination: Slab) {
        applyForceShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(destination.ping, index: 0)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func computeDivergence(commandBuffer: MTLCommandBuffer, velocity: Slab, destination: Slab) {
        divergenceShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func computePressure(commandBuffer: MTLCommandBuffer, x: Slab, b: Slab, destination: Slab) {
        jacobiShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(x.ping, index: 0)
            commandEncoder.setFragmentTexture(b.ping, index: 1)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func computeVorticity(commandBuffer: MTLCommandBuffer, velocity: Slab, destination: Slab) {
        vorticityShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func computeVorticityConfinement(commandBuffer: MTLCommandBuffer, velocity: Slab, vorticity: Slab, destination: Slab) {
        vorticityConfinementShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
            commandEncoder.setFragmentTexture(vorticity.ping, index: 1)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }

    func subtractGradient(commandBuffer: MTLCommandBuffer, p: Slab, w: Slab, destination: Slab) {
        gradientShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: destination.pong, configureEncoder: { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(p.ping, index: 0)
            commandEncoder.setFragmentTexture(w.ping, index: 1)

            commandEncoder.setFragmentBuffer(self.staticBuffer, offset: 0, index: 0)
        })

        destination.swap()
    }
}

extension RenderViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        semaphore.wait()

        if let initialTouch = initialTouchPosition, let direction = touchDirection {
            let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)

            let pos = float2(x: Float(initialTouch.x) , y: Float(initialTouch.y))
            let impulse = float2(x: Float(initialTouch.x - direction.x), y: Float(initialTouch.y - direction.y))

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

            advect(commandBuffer: commandBuffer, velocity: velocity, source: velocity, destination: velocity)
            advect(commandBuffer: commandBuffer, velocity: velocity, source: density, destination: density)
            applyForce(commandBuffer: commandBuffer, destination: velocity)



            //Only for density
//            if let initialTouch = initialTouchPosition, let direction = touchDirection {
//                let bufferData = staticBuffer.contents().bindMemory(to: StaticData.self, capacity: 1)
//
//                let impulse = float2(x: 0.8, y: 0.0)
//                bufferData.pointee.impulse = impulse
//                memcpy(staticBuffer.contents(), bufferData, MemoryLayout<StaticData>.size)
//            }

            applyForce(commandBuffer: commandBuffer, destination: density)

            computeVorticity(commandBuffer: commandBuffer, velocity: velocity, destination: velocityVorticity)
            computeVorticityConfinement(commandBuffer: commandBuffer, velocity: velocity, vorticity: velocityVorticity, destination: velocity)

            computeDivergence(commandBuffer: commandBuffer, velocity: velocity, destination: velocityDivergence)
            // Maybe useful for smoke
            //        pressure.clear()
            for _ in 0..<30 {
                computePressure(commandBuffer: commandBuffer, x: pressure, b: velocityDivergence, destination: pressure)
            }

            subtractGradient(commandBuffer: commandBuffer, p: pressure, w: velocity, destination: velocity)

            renderShader.calculateWithCommandBuffer(buffer: commandBuffer, texture: nextTexture, configureEncoder: { (commandEncoder) in
                commandEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
                commandEncoder.setVertexBuffer(self.textureBuffer, offset: 0, index: 1)
                commandEncoder.setFragmentTexture(self.drawSlab().ping, index: 0)
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
