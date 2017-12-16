//
//  MetalDevice.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 06/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal

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
        commandQueue = device.makeCommandQueue()!
        
        activeCommandBuffer = commandQueue.makeCommandBuffer()!
        
        defaultLibrary = device.makeDefaultLibrary()!
    }
    
    //Convenience methods
    
    final class func createRenderPipeline(vertexFunctionName: String = "basicVertexFunction", fragmentFunctionName: String, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        return try self.sharedInstance.createRenderPipeline(vertexFunctionName: vertexFunctionName, fragmentFunctionName: fragmentFunctionName, pixelFormat: pixelFormat)
    }
    
    final class func createComputePipeline(computeFunctionName: String) throws -> MTLComputePipelineState {
        return try self.sharedInstance.createComputePipeline(computeFunctionName: computeFunctionName)
    }
    
    final class func createTexture(descriptor: MTLTextureDescriptor) -> MTLTexture {
        return self.sharedInstance.device.makeTexture(descriptor: descriptor)!
    }
    
    final func swapBuffers() {
        let texture = inputTexture
        inputTexture = outputTexture
        outputTexture = texture
    }
    
    final func buffer<T>(array: Array<T>, storageMode: MTLResourceOptions = []) -> MTLBuffer {
        let size = array.count * MemoryLayout.size(ofValue: array[0])
        return device.makeBuffer(bytes: array, length: size, options: storageMode)!
    }
    
    final func newCommandBuffer() -> MTLCommandBuffer {
        return commandQueue.makeCommandBuffer()!
    }
    
    final func createRenderPipeline(vertexFunctionName: String = "basicVertexFunction", fragmentFunctionName: String, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
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
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        pipelineStateDescriptor.label = fragmentFunctionName
        
        let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        pipelineCache.setObject(pipelineState, forKey: cacheKey)
        
        return pipelineState
    }
    
    final func createComputePipeline(computeFunctionName: String) throws -> MTLComputePipelineState {
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
