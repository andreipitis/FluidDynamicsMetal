//
//  BasicFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 19/05/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import CoreMedia
import Metal

struct PipelineStateConfiguration {
    let pixelFormat: MTLPixelFormat
    let vertexShader: String
    let fragmentShader: String
    let computeShader: String
}

let vertexData: [Float] = [
    -1.0, -1.0,
    1.0, -1.0,
    -1.0, 1.0,

    1.0, -1.0,
    -1.0, 1.0,
    1.0, 1.0
]

class BasicFilter: ImageSource, ImageConsumer {
    var outputTexture: MTLTexture?
    var inputTexture: MTLTexture?
    var targets: [ImageConsumer] = []

    private var pipelineState: PipelineStateConfiguration

    private var computePipelineState: MTLComputePipelineState?
    private var renderPipelineState: MTLRenderPipelineState?

    init(fragmentShader: String, vertexShader: String) {
        pipelineState = PipelineStateConfiguration(pixelFormat: .bgra8Unorm, vertexShader: vertexShader, fragmentShader: fragmentShader, computeShader: "")

        commonInit()
    }

    init(computeShader: String) {
        pipelineState = PipelineStateConfiguration(pixelFormat: .bgra8Unorm, vertexShader: "", fragmentShader: "", computeShader: computeShader)

        commonInit()
    }

    deinit {
        Log("Deinit Filter")
    }

    func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer) {
        autoreleasepool {
            var nextBuffer = buffer
            for var target in targets {
                calculateWithCommandBuffer(buffer: nextBuffer, target: &target, at: time)
                nextBuffer = MetalDevice.sharedInstance.newCommandBuffer()
            }
        }
    }

    private func calculateWithCommandBuffer(buffer: MTLCommandBuffer, target: inout ImageConsumer, at time: CMTime) {
        if outputTexture == nil {
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.pixelFormat = .bgra8Unorm
            textureDescriptor.usage = .unknown
            textureDescriptor.width = inputTexture!.width
            textureDescriptor.height = inputTexture!.height
            outputTexture = MetalDevice.createTexture(descriptor: textureDescriptor)
        }

        if let renderPipelineState = renderPipelineState {
            let renderPassDescriptor = configureRenderPassDescriptor(texture: outputTexture)
            let renderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

            let vertexBuffer = MetalDevice.sharedInstance.buffer(array: vertexData)
            let textureBuffer = MetalDevice.sharedInstance.buffer(array: TextureRotation.none.rotation())

            renderCommandEncoder.pushDebugGroup("Base Filter Render Encoder")
            renderCommandEncoder.setFragmentTexture(inputTexture, at: 0)
            renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, at: 0)
            renderCommandEncoder.setVertexBuffer(textureBuffer, offset: 0, at: 1)

            renderCommandEncoder.setRenderPipelineState(renderPipelineState)

            renderCommandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderCommandEncoder.endEncoding()

            renderCommandEncoder.popDebugGroup()

            target.inputTexture = outputTexture
            target.newFrameReady(at: time, at: 0, using: buffer)

        } else if let computePipelineState = computePipelineState {
            let computeCommandEncoder = buffer.makeComputeCommandEncoder()

            computeCommandEncoder.pushDebugGroup("Base Filter Compute Encoder")
            computeCommandEncoder.setTexture(inputTexture, at: 0)
            computeCommandEncoder.setTexture(outputTexture, at: 1)

            computeCommandEncoder.setComputePipelineState(computePipelineState)

            let threadGroupCouts = MTLSize(width: 8, height: 8, depth: 1)
            let threadGroups = MTLSize(width: inputTexture!.width / threadGroupCouts.width, height: inputTexture!.height / threadGroupCouts.height, depth: 1)
            computeCommandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCouts)

            computeCommandEncoder.endEncoding()
            computeCommandEncoder.popDebugGroup()

            target.inputTexture = outputTexture
            target.newFrameReady(at: time, at: 0, using: buffer)
        }
    }

    private func configureRenderPassDescriptor(texture: MTLTexture?) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        return renderPassDescriptor
    }

    private func configurePipeline() {
        if pipelineState.computeShader.characters.count > 0 {
            if computePipelineState != nil {
                return
            }
            do {
                computePipelineState = try MetalDevice.createComputePipeline(computeFunctionName: pipelineState.computeShader)
            } catch {
                Log("Could not create compute pipeline state.")
            }
        } else {
            if renderPipelineState != nil {
                return
            }

            do {
                renderPipelineState = try MetalDevice.createRenderPipeline(vertexFunctionName: pipelineState.vertexShader, fragmentFunctionName: pipelineState.fragmentShader)
            } catch {
                Log("Could not create render pipeline state.")
            }
        }
    }
    
    private func commonInit() {
        configurePipeline()
    }
}
