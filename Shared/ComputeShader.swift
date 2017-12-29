//
//  BasicFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 19/05/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import CoreMedia
import Metal

class ComputeShader {
    var outputTexture: MTLTexture?
    var inputTexture: MTLTexture?

    private var pipelineState: PipelineStateConfiguration

    private var computePipelineState: MTLComputePipelineState?

    init(computeShader: String) {
        pipelineState = PipelineStateConfiguration(pixelFormat: .bgra8Unorm, vertexShader: "", fragmentShader: "", computeShader: computeShader)

        commonInit()
    }

    deinit {
        print("Deinit Filter")
    }

    func calculateWithCommandBuffer(buffer: MTLCommandBuffer, configureEncoder: ((_ commandEncoder: MTLComputeCommandEncoder) -> Void)?) {
        if let computePipelineState = computePipelineState, let computeCommandEncoder = buffer.makeComputeCommandEncoder() {
            computeCommandEncoder.pushDebugGroup("Base Filter Compute Encoder")
            computeCommandEncoder.setComputePipelineState(computePipelineState)

            configureEncoder?(computeCommandEncoder)

            computeCommandEncoder.endEncoding()
            computeCommandEncoder.popDebugGroup()
        }
    }

    private func configurePipeline() {
        if pipelineState.computeShader.count > 0 {
            if computePipelineState != nil {
                return
            }
            do {
                computePipelineState = try MetalDevice.createComputePipeline(computeFunctionName: pipelineState.computeShader)
            } catch {
                print("Could not create compute pipeline state.")
            }
        }
    }

    private func commonInit() {
        configurePipeline()
    }
}


