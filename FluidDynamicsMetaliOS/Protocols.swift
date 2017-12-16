//
//  Protocols.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 19/05/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import CoreMedia
import Metal

protocol ImageSource {
    var outputTexture: MTLTexture? {get}
    
    var targets: [ImageConsumer] {get set}
}

protocol ImageConsumer {
    var inputTexture: MTLTexture? {get set}
    
    func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer)
}

infix operator -->: AdditionPrecedence

@discardableResult func --><T: ImageConsumer>(source: ImageSource, destination: T) -> T {
    var actualSource = source
    actualSource.add(target: destination)

    return destination
}


extension ImageSource {
    mutating func add(target: ImageConsumer) {
        targets.append(target)
    }
    
    mutating func removeAllTargets() {
        targets.removeAll()
    }
}

extension ImageConsumer {

}

struct Targets<T: Comparable, ImageConsumer>: Sequence {
    var targets: [T] = []
    
    func makeIterator() -> IndexingIterator<Array<T>> {
        return targets.makeIterator()
    }

    mutating func add(target: T) {
        if targets.contains(where: { (imageConsumer) -> Bool in
            return imageConsumer == target
        }) == false {
            targets.append(target)
        }
    }
    
    mutating func remove(target: T) {
        if let index = targets.index(of: target) {
            targets.remove(at: index)
        }
    }
    
    mutating func removeAll() {
        targets.removeAll()
    }
}
