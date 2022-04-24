//
//  Slab.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 15/08/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal

class Slab {
    var ping: MTLTexture!
    var pong: MTLTexture!

    init(width: Int, height: Int, format: MTLPixelFormat = .rgba16Float, usage: MTLTextureUsage = .unknown, name: String? = nil) {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = format
        textureDescriptor.usage = MTLTextureUsage(rawValue: MTLTextureUsage.shaderRead.rawValue | MTLTextureUsage.renderTarget.rawValue)
        textureDescriptor.width = width
        textureDescriptor.height = height

        ping = MetalDevice.createTexture(descriptor: textureDescriptor)
        pong = MetalDevice.createTexture(descriptor: textureDescriptor)

        ping.label = name
        pong.label = name
    }

    func swap() {
        let temp = ping
        ping = pong
        pong = temp
    }
}
