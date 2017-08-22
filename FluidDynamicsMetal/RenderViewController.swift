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
        var impulseScalar: float2
        var offsets: float2

        var screenSize: float2
    }

    struct VertexData {
        let position: float2
        let texCoord: float2
    }

    static let vertexData: [VertexData] = [
        VertexData(position: float2(x: -1.0, y: -1.0), texCoord: float2(x: 0.0, y: 1.0)),
        VertexData(position: float2(x: 1.0, y: -1.0), texCoord: float2(x: 1.0, y: 1.0)),
        VertexData(position: float2(x: -1.0, y: 1.0), texCoord: float2(x: 0.0, y: 0.0)),
        VertexData(position: float2(x: 1.0, y: 1.0), texCoord: float2(x: 1.0, y: 0.0)),
        ]

    static let indices: [UInt16] = [0, 1, 2, 1, 2, 3]


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

    var applyForceVectorShader: RenderShader!
    var applyForceScalarShader: RenderShader!
    var advectShader: RenderShader!
    var divergenceShader: RenderShader!
    var jacobiShader: RenderShader!
    var vorticityShader: RenderShader!
    var vorticityConfinementShader: RenderShader!
    var gradientShader: RenderShader!

    var renderVector: RenderShader!
    var renderScalar: RenderShader!

    var initialTouchPosition: CGPoint?
    var touchDirection: CGPoint?

    var velocity: Slab!
    var density: Slab!
    var velocityDivergence: Slab!
    var velocityVorticity: Slab!
    var pressure: Slab!

    let vertData = MetalDevice.sharedInstance.buffer(array: RenderViewController.vertexData, storageMode: [MTLResourceOptions.storageModeShared])
    let indexData = MetalDevice.sharedInstance.buffer(array: indices, storageMode: [MTLResourceOptions.storageModeShared])

    let inflightBuffersCount: Int = 3
    var uniformsBuffers: [MTLBuffer] = []
    var avaliableBufferIndex: Int = 0

    let semaphore = DispatchSemaphore(value: 3)

    var currentIndex = 0

    var interactive: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let currentTime = CACurrentMediaTime()

        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60
        metalView.delegate = self

        print("screenSize = \(metalView.bounds.size)")

        velocity = Slab(width: width, height: height, name: "Velocity")
        density = Slab(width: width, height: height, name: "Density")
        velocityDivergence = Slab(width: width, height: height, name: "Divergence")
        velocityVorticity = Slab(width: width, height: height, name: "Vorticity")
        pressure = Slab(width: width, height: height, name: "Pressure")

        applyForceVectorShader = RenderShader(fragmentShader: "applyForceVector", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        applyForceScalarShader = RenderShader(fragmentShader: "applyForceScalar", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        advectShader = RenderShader(fragmentShader: "advect", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        divergenceShader = RenderShader(fragmentShader: "divergence", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        jacobiShader = RenderShader(fragmentShader: "jacobi", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        vorticityShader = RenderShader(fragmentShader: "vorticity", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        vorticityConfinementShader = RenderShader(fragmentShader: "vorticityConfinement", vertexShader: "vertexShader", pixelFormat: .rgba16Float)
        gradientShader = RenderShader(fragmentShader: "gradient", vertexShader: "vertexShader", pixelFormat: .rgba16Float)

        renderVector = RenderShader(fragmentShader: "visualizeVector", vertexShader: "vertexShader")
        renderScalar = RenderShader(fragmentShader: "visualizeScalar", vertexShader: "vertexShader")

        let bufferSize = MemoryLayout<StaticData>.size

        var staticData = StaticData(position: float2(0.0, 0.0), impulse: float2(0.0, 0.0), impulseScalar: float2(0.0, 0.0), offsets: float2(1.0/Float(UIScreen.main.bounds.width), 1.0/Float(UIScreen.main.bounds.height)), screenSize: float2(Float(UIScreen.main.bounds.width), Float(UIScreen.main.bounds.height)))

        for _ in 0..<inflightBuffersCount {
            let buffer = MetalDevice.sharedInstance.device.makeBuffer(bytes: &staticData, length: bufferSize, options: .storageModeShared)

            uniformsBuffers.append(buffer)
        }

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

        print("Time to start = \(CACurrentMediaTime() - currentTime)")

        initialTouchPosition = CGPoint(x: CGFloat(width / 2), y: CGFloat(height - 50))
        touchDirection = CGPoint(x: CGFloat(width / 2), y: CGFloat(height - 50 + 1))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        print("Got Memory Warning")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        interactive = true
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

    func drawSlab() -> Slab {
        switch currentIndex {
        case 1:
            return pressure
        case 2:
            return velocity
        case 3:
            return velocityVorticity
        default:
            return density
        }
    }

    func advect(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, source: Slab, destination: Slab) {
        advectShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(velocity.ping, at: 0)
            commandEncoder.setFragmentTexture(source.ping, at: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func applyForceVector(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: Slab) {
        applyForceVectorShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(destination.ping, at: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func applyForceScalar(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: Slab) {
        applyForceScalarShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(destination.ping, at: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func computeDivergence(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, destination: Slab) {
        divergenceShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(velocity.ping, at: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func computePressure(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, x: Slab, b: Slab, destination: Slab) {
        jacobiShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(x.ping, at: 0)
            commandEncoder.setFragmentTexture(b.ping, at: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func computeVorticity(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, destination: Slab) {
        vorticityShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(velocity.ping, at: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func computeVorticityConfinement(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, vorticity: Slab, destination: Slab) {
        vorticityConfinementShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(velocity.ping, at: 0)
            commandEncoder.setFragmentTexture(vorticity.ping, at: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func subtractGradient(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, p: Slab, w: Slab, destination: Slab) {
        gradientShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
            commandEncoder.setFragmentTexture(p.ping, at: 0)
            commandEncoder.setFragmentTexture(w.ping, at: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, at: 0)
        }

        destination.swap()
    }

    func render(commandBuffer: MTLCommandBuffer, destination: MTLTexture) {
        if currentIndex >= 2 {
            renderVector.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination) { (commandEncoder) in
                commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
                commandEncoder.setFragmentTexture(self.drawSlab().ping, at: 0)
            }
        } else {
            renderScalar.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: RenderViewController.indices.count, texture: destination) { (commandEncoder) in
                commandEncoder.setVertexBuffer(self.vertData, offset: 0, at: 0)
                commandEncoder.setFragmentTexture(self.drawSlab().ping, at: 0)
            }
        }
    }

    func nextBuffer(position: CGPoint, direction: CGPoint) -> MTLBuffer {
        let buffer = uniformsBuffers[avaliableBufferIndex]


        let bufferData = buffer.contents().bindMemory(to: StaticData.self, capacity: 1)

        let pos = float2(x: Float(position.x) , y: Float(position.y))
        let impulse = float2(x: Float(position.x - direction.x), y: Float(position.y - direction.y))

        if pos.x.isNaN == false && pos.y.isNaN == false && impulse.x.isNaN == false && impulse.y.isNaN == false {

            bufferData.pointee.position = pos
            bufferData.pointee.impulse = impulse
            bufferData.pointee.impulseScalar = float2(0.8, 0.0)
        }

        avaliableBufferIndex = (avaliableBufferIndex + 1) % inflightBuffersCount
        return buffer
    }
}

extension RenderViewController: MTKViewDelegate {
    func draw(in view: MTKView) {
        semaphore.wait()
        let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()

        let dataBuffer = nextBuffer(position: initialTouchPosition ?? .zero, direction: touchDirection ?? .zero)

        commandBuffer.addCompletedHandler({ (commandBuffer) in
            self.semaphore.signal()
        })

        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: velocity, destination: velocity)
        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: density, destination: density)

        if let _ = initialTouchPosition, let _ = touchDirection {
            applyForceVector(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: velocity)
            applyForceScalar(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: density)
        }

        computeVorticity(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityVorticity)
        computeVorticityConfinement(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, vorticity: velocityVorticity, destination: velocity)

        computeDivergence(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityDivergence)

        for _ in 0..<60 {
            computePressure(commandBuffer: commandBuffer, dataBuffer: dataBuffer, x: pressure, b: velocityDivergence, destination: pressure)
        }

        subtractGradient(commandBuffer: commandBuffer, dataBuffer: dataBuffer, p: pressure, w: velocity, destination: velocity)
        
        
        if let drawable = view.currentDrawable {
            
            let nextTexture = drawable.texture
            render(commandBuffer: commandBuffer, destination: nextTexture)
            
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
        
        if interactive == true {
            touchDirection = initialTouchPosition
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
}
