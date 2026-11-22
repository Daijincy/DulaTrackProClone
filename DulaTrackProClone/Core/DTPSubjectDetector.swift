//
//  DTPSubjectDetector.swift
//  DulaTrackPro Clone
//
//  直接复用从原 App 恢复的 CoreML 模型：
//  输入 1×3×768×768 RGB（0...255，内部做 /255 与 mean/std）
//  输出 FCOS 原始头：cls/box/centerness × stride 8/16/32
//

import Foundation
import CoreML
import CoreImage
import CoreVideo
import UIKit

final class DTPSubjectDetector {

    struct Detection {
        let label: String
        let classIndex: Int
        let score: Float
        /// 归一化坐标，原点在左上角（视觉坐标）
        let box: CGRect
    }

    static let shared = DTPSubjectDetector()

    let classNames = ["按钮", "车标", "车牌", "出风口", "多媒体屏幕", "方向盘", "后车灯", "后视镜",
                      "轮胎", "门把手", "排挡杆", "排气管", "品牌LOGO", "汽车", "汽车内部前排",
                      "前车灯", "人物", "头", "雾灯", "字母"]

    private let inputSize = 768
    private let model: MLModel?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()

    private struct Head {
        let stride: Int
        let grid: Int
    }

    private let heads = [Head(stride: 8, grid: 96),
                         Head(stride: 16, grid: 48),
                         Head(stride: 32, grid: 24)]

    private init() {
        guard let url = Bundle.main.url(forResource: "DulaAIContentDetector_CurrentBest_iOS",
                                        withExtension: "mlmodelc") else {
            model = nil
            return
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            model = try MLModel(contentsOf: url, configuration: configuration)
        } catch {
            NSLog("[DTPDetector] failed to load model: \(error)")
            model = nil
        }
    }

    var isReady: Bool { model != nil }

    // MARK: - 推理

    func detect(in image: CIImage) -> [Detection] {
        guard let model,
              let input = makeInput(from: image),
              let provider = try? MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(multiArray: input)
              ]) else {
            return []
        }

        lock.lock()
        let output = try? model.prediction(from: provider)
        lock.unlock()

        guard let output else { return [] }

        var candidates: [Detection] = []
        for head in heads {
            guard let cls = output.featureValue(for: "cls_s\(head.stride)")?.multiArrayValue,
                  let box = output.featureValue(for: "box_s\(head.stride)")?.multiArrayValue,
                  let centerness = output.featureValue(for: "centerness_s\(head.stride)")?.multiArrayValue else {
                continue
            }

            let size = Float(inputSize)
            for y in 0..<head.grid {
                for x in 0..<head.grid {
                    let centerScore = sigmoid(value(centerness, channel: 0, y: y, x: x))
                    if centerScore < 0.12 { continue }

                    var bestClass = -1
                    var bestScore: Float = 0
                    for c in 0..<classNames.count {
                        let score = sigmoid(value(cls, channel: c, y: y, x: x))
                        if score > bestScore {
                            bestScore = score
                            bestClass = c
                        }
                    }
                    guard bestClass >= 0 else { continue }

                    let score = bestScore * centerScore
                    if score < 0.25 { continue }

                    let cx = (Float(x) + 0.5) * Float(head.stride)
                    let cy = (Float(y) + 0.5) * Float(head.stride)
                    let left = expf(min(max(value(box, channel: 0, y: y, x: x), -4), 4)) * Float(head.stride)
                    let top = expf(min(max(value(box, channel: 1, y: y, x: x), -4), 4)) * Float(head.stride)
                    let right = expf(min(max(value(box, channel: 2, y: y, x: x), -4), 4)) * Float(head.stride)
                    let bottom = expf(min(max(value(box, channel: 3, y: y, x: x), -4), 4)) * Float(head.stride)

                    let x0 = max(0, cx - left)
                    let y0 = max(0, cy - top)
                    let x1 = min(size, cx + right)
                    let y1 = min(size, cy + bottom)
                    guard x1 - x0 > 8, y1 - y0 > 8 else { continue }

                    let rect = CGRect(x: CGFloat(x0 / size),
                                      y: CGFloat(y0 / size),
                                      width: CGFloat((x1 - x0) / size),
                                      height: CGFloat((y1 - y0) / size))
                    candidates.append(Detection(label: classNames[bestClass],
                                                classIndex: bestClass,
                                                score: score,
                                                box: rect))
                }
            }
        }

        let selected = nonMaxSuppression(candidates, iouThreshold: 0.45, limit: 30)
        return selected
    }

    // MARK: - 输入预处理

    private func makeInput(from image: CIImage) -> MLMultiArray? {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let scale = CGAffineTransform(scaleX: CGFloat(inputSize) / extent.width,
                                      y: CGFloat(inputSize) / extent.height)
        let resized = normalized.transformed(by: scale)

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         inputSize,
                                         inputSize,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary,
                                         &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        ciContext.render(resized,
                         to: buffer,
                         bounds: CGRect(x: 0, y: 0, width: inputSize, height: inputSize),
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        let shape: [NSNumber] = [1, 3, NSNumber(value: inputSize), NSNumber(value: inputSize)]
        guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let plane = inputSize * inputSize
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: plane * 3)

        for y in 0..<inputSize {
            let row = bytes + y * bytesPerRow
            let rowOffset = y * inputSize
            for x in 0..<inputSize {
                let pixel = row + x * 4
                let offset = rowOffset + x
                pointer[offset] = Float(pixel[2])            // R
                pointer[plane + offset] = Float(pixel[1])    // G
                pointer[plane * 2 + offset] = Float(pixel[0]) // B
            }
        }
        return array
    }

    // MARK: - 工具

    @inline(__always)
    private func value(_ array: MLMultiArray, channel: Int, y: Int, x: Int) -> Float {
        let index = channel * array.strides[1].intValue
            + y * array.strides[2].intValue
            + x * array.strides[3].intValue
        return array[index].floatValue
    }

    @inline(__always)
    private func sigmoid(_ x: Float) -> Float {
        1 / (1 + expf(-x))
    }

    private func nonMaxSuppression(_ detections: [Detection],
                                   iouThreshold: CGFloat,
                                   limit: Int) -> [Detection] {
        let sorted = detections.sorted { $0.score > $1.score }
        var kept: [Detection] = []
        for candidate in sorted {
            var shouldKeep = true
            for existing in kept where existing.classIndex == candidate.classIndex {
                if iou(existing.box, candidate.box) > iouThreshold {
                    shouldKeep = false
                    break
                }
            }
            if shouldKeep {
                kept.append(candidate)
                if kept.count >= limit { break }
            }
        }
        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let interArea = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - interArea
        guard union > 0 else { return 0 }
        return interArea / union
    }
}
