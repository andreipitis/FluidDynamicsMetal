//
//  MetalDevice.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 06/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal

enum TextureRotation {
    case none
    case left
    case right
    case flipVertical
    case flipHorizontal

    func rotation() -> [Float] {
        switch self {
        case .none:
            return [
                0.0, 1.0,
                1.0, 1.0,
                0.0, 0.0,

                1.0, 1.0,
                0.0, 0.0,
                1.0, 0.0
            ]
        case .left:
            return [
                1.0, 0.0,
                1.0, 1.0,
                0.0, 0.0,

                1.0, 1.0,
                0.0, 0.0,
                0.0, 1.0
            ]
        case .right:
            return [
                0.0, 1.0,
                0.0, 0.0,
                1.0, 1.0,

                0.0, 0.0,
                1.0, 1.0,
                1.0, 0.0
            ]
        case .flipVertical:
            return [
                0.0, 0.0,
                1.0, 0.0,
                0.0, 1.0,

                1.0, 0.0,
                0.0, 1.0,
                1.0, 1.0
            ]
        case .flipHorizontal:
            return [
                1.0, 0.0,
                0.0, 0.0,
                1.0, 1.0,

                0.0, 0.0,
                1.0, 1.0,
                0.0, 1.0
            ]
        }
    }
}

enum MetalDeviceError: Error {
    case failedToCreateFunction(name: String)
}

class MetalDevice {
    static let sharedInstance = MetalDevice()
    
    private let pipelineCache = NSCache<AnyObject, AnyObject>()
    
    let queue = DispatchQueue.global(qos: .background)
    
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    var activeCommandBuffer: MTLCommandBuffer
    var defaultLibrary: MTLLibrary
    
    internal var inputTexture: MTLTexture?
    internal var outputTexture: MTLTexture?
    
    private init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()
        
        activeCommandBuffer = commandQueue.makeCommandBuffer()
        
        defaultLibrary = device.newDefaultLibrary()!
    }
    
    //Convenience methods
    
    class func createRenderPipeline(vertexFunctionName: String = "basicVertexFunction", fragmentFunctionName: String) throws -> MTLRenderPipelineState {
        return try self.sharedInstance.createRenderPipeline(vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName)
    }
    
    class func createComputePipeline(computeFunctionName: String) throws -> MTLComputePipelineState {
        return try self.sharedInstance.createComputePipeline(computeFunctionName: computeFunctionName)
    }
    
    class func createTexture(descriptor: MTLTextureDescriptor) -> MTLTexture {
        return self.sharedInstance.device.makeTexture(descriptor: descriptor)
    }
    
    func swapBuffers() {
        let texture = inputTexture
        inputTexture = outputTexture
        outputTexture = texture
    }
    
    func buffer<T>(array: Array<T>) -> MTLBuffer {
        let size = array.count * MemoryLayout.size(ofValue: array[0])
        return device.makeBuffer(bytes: array, length: size, options: [])
    }
    
    func newCommandBuffer() -> MTLCommandBuffer {
        return commandQueue.makeCommandBuffer()
    }
    
    func createRenderPipeline(vertexFunctionName: String = "basicVertexFunction", fragmentFunctionName: String) throws -> MTLRenderPipelineState {
        let cacheKey = NSString(string: vertexFunctionName + fragmentFunctionName)
        
        if let pipelineState = pipelineCache.object(forKey: cacheKey) as? MTLRenderPipelineState {
            return pipelineState
        }
        
        guard let vertexFunction = defaultLibrary.makeFunction(name: vertexFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: vertexFunctionName)
        }
        
        guard let fragmentFunction = defaultLibrary.makeFunction(name: fragmentFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: fragmentFunctionName)
        }
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        
        let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        pipelineCache.setObject(pipelineState, forKey: cacheKey)
        
        return pipelineState
    }
    
    func createComputePipeline(computeFunctionName: String) throws -> MTLComputePipelineState {
        let cacheKey = NSString(string: computeFunctionName)
        
        if let pipelineState = pipelineCache.object(forKey: cacheKey) as? MTLComputePipelineState {
            return pipelineState
        }
        
        guard let computeFunction = defaultLibrary.makeFunction(name: computeFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: computeFunctionName)
        }
        
        let pipelineState =  try device.makeComputePipelineState(function: computeFunction)
        
        pipelineCache.setObject(pipelineState, forKey: cacheKey)
        
        return pipelineState
    }
}
