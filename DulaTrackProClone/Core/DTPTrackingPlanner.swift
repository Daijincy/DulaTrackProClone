//
//  DTPTrackingPlanner.swift
//  DulaTrackPro Clone
//
//  两遍处理：先按固定帧率采样做主体检测，再对轨迹做双向平滑。
//

import Foundation
import AVFoundation
import CoreImage

struct DTPTrackSample {
    var time: Double
    /// 归一化中心，原点左上角
    var center: CGPoint
    /// 归一化主体框，原点左上角
    var box: CGRect
    var score: Float
    var label: String
}

struct DTPTrackPlan {
    var samples: [DTPTrackSample]
    var duration: Double
    var displaySize: CGSize
    var subjectLabel: String?

    func sample(at time: Double) -> DTPTrackSample? {
        guard !samples.isEmpty else { return nil }
        if samples.count == 1 { return samples[0] }
        guard let first = samples.first, let last = samples.last else { return nil }
        if time <= first.time { return first }
        if time >= last.time { return last }

        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].time <= time {
                low = mid
            } else {
                high = mid
            }
        }

        let a = samples[low]
        let b = samples[high]
        let span = max(b.time - a.time, 0.0001)
        let t = CGFloat(min(max((time - a.time) / span, 0), 1))

        let center = CGPoint(x: a.center.x + (b.center.x - a.center.x) * t,
                             y: a.center.y + (b.center.y - a.center.y) * t)
        let box = CGRect(x: a.box.minX + (b.box.minX - a.box.minX) * t,
                         y: a.box.minY + (b.box.minY - a.box.minY) * t,
                         width: a.box.width + (b.box.width - a.box.width) * t,
                         height: a.box.height + (b.box.height - a.box.height) * t)
        return DTPTrackSample(time: time,
                              center: center,
                              box: box,
                              score: a.score + (b.score - a.score) * Float(t),
                              label: t < 0.5 ? a.label : b.label)
    }
}

final class DTPTrackingPlanner {

    struct Options {
        var sampleFPS: Double = 6
        var minimumScore: Float = 0.28
        var preferredLabels: [String] = ["人物", "汽车", "汽车内部前排"]
        var maxSamples: Int = 720
    }

    private var cancelled = false

    func cancel() {
        cancelled = true
    }

    func buildPlan(for asset: AVAsset,
                   options: Options = Options(),
                   progress: @escaping (Double) -> Void,
                   completion: @escaping (Result<DTPTrackPlan, Error>) -> Void) {
        cancelled = false

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let plan = try await self.makePlan(asset: asset, options: options, progress: progress)
                await MainActor.run { completion(.success(plan)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - 主流程

    private func makePlan(for asset: AVAsset,
                          options: Options,
                          progress: @escaping (Double) -> Void) async throws -> DTPTrackPlan {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DTPMediaError.noVideoTrack
        }

        let duration = try await asset.load(.duration).seconds
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))

        let detector = DTPSubjectDetector.shared
        var samples: [DTPTrackSample] = []
        var subjectLabel: String?

        if detector.isReady, duration > 0.05 {
            samples = detectSamples(asset: asset,
                                    track: track,
                                    transform: preferredTransform,
                                    duration: duration,
                                    options: options,
                                    progress: progress,
                                    label: &subjectLabel)
        }

        if samples.isEmpty {
            let fallback = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            samples = [
                DTPTrackSample(time: 0,
                               center: CGPoint(x: 0.5, y: 0.5),
                               box: fallback,
                               score: 0,
                               label: "自动构图"),
                DTPTrackSample(time: max(duration, 0.1),
                               center: CGPoint(x: 0.5, y: 0.5),
                               box: fallback,
                               score: 0,
                               label: "自动构图")
            ]
        } else {
            samples = smooth(samples)
            if let first = samples.first, first.time > 0.05 {
                samples.insert(DTPTrackSample(time: 0,
                                              center: first.center,
                                              box: first.box,
                                              score: first.score,
                                              label: first.label), at: 0)
            }
            if let last = samples.last, last.time < duration - 0.05 {
                samples.append(DTPTrackSample(time: duration,
                                              center: last.center,
                                              box: last.box,
                                              score: last.score,
                                              label: last.label))
            }
        }

        return DTPTrackPlan(samples: samples,
                            duration: duration,
                            displaySize: displaySize,
                            subjectLabel: subjectLabel)
    }

    private func detectSamples(asset: AVAsset,
                               track: AVAssetTrack,
                               transform: CGAffineTransform,
                               duration: Double,
                               options: Options,
                               progress: @escaping (Double) -> Void,
                               label: inout String?) -> [DTPTrackSample] {
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        reader.startReading()

        let detector = DTPSubjectDetector.shared
        let interval = 1.0 / max(min(options.sampleFPS, 12), 1)
        var nextSampleTime = 0.0
        var lastReported = -1.0
        var samples: [DTPTrackSample] = []
        var previous: DTPTrackSample?

        while reader.status == .reading && !cancelled && samples.count < options.maxSamples {
            autoreleasepool {
                guard let sampleBuffer = output.copyNextSampleBuffer() else { return }
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                guard time.isFinite, time >= nextSampleTime else { return }
                nextSampleTime = time + interval

                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                var image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: transform)
                let extent = image.extent
                image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))

                let detections = detector.detect(in: image)
                guard let pick = self.pick(from: detections, previous: previous, options: options) else { return }

                let sample = DTPTrackSample(time: time,
                                            center: CGPoint(x: pick.box.midX, y: pick.box.midY),
                                            box: pick.box,
                                            score: pick.score,
                                            label: pick.label)
                samples.append(sample)
                previous = sample
                label = pick.label

                let value = min(max(time / max(duration, 0.1), 0), 1)
                if value - lastReported > 0.02 {
                    lastReported = value
                    DispatchQueue.main.async { progress(value) }
                }
            }
        }

        reader.cancelReading()
        DispatchQueue.main.async { progress(1) }
        return samples
    }

    // MARK: - 选主体

    private func pick(from detections: [DTPSubjectDetector.Detection],
                      previous: DTPTrackSample?,
                      options: Options) -> DTPSubjectDetector.Detection? {
        var best: DTPSubjectDetector.Detection?
        var bestScore: Float = -.greatestFiniteMagnitude

        for detection in detections {
            guard detection.score >= options.minimumScore else { continue }
            let area = Float(detection.box.width * detection.box.height)
            guard area > 0.003 else { continue }

            var score = detection.score * 0.65 + min(area, 0.5) * 0.35

            if let priority = options.preferredLabels.firstIndex(of: detection.label) {
                score += 0.3 - Float(priority) * 0.03
            } else {
                score -= 0.08
            }

            if let previous {
                score += 0.9 * Float(iou(previous.box, detection.box))
                if previous.label == detection.label { score += 0.12 }
            }

            if score > bestScore {
                bestScore = score
                best = detection
            }
        }
        return best
    }

    // MARK: - 平滑

    private func smooth(_ input: [DTPTrackSample]) -> [DTPTrackSample] {
        guard input.count > 2 else { return input }

        var forward = input
        let alpha: CGFloat = 0.3
        var center = input[0].center
        var size = input[0].box.size

        for index in 0..<forward.count {
            let sample = input[index]
            center.x += (sample.center.x - center.x) * alpha
            center.y += (sample.center.y - center.y) * alpha
            size.width += (sample.box.width - size.width) * alpha
            size.height += (sample.box.height - size.height) * alpha
            forward[index].center = center
            forward[index].box = CGRect(x: center.x - size.width / 2,
                                        y: center.y - size.height / 2,
                                        width: size.width,
                                        height: size.height)
        }

        var backward = forward
        center = forward[forward.count - 1].center
        size = forward[forward.count - 1].box.size
        for index in stride(from: forward.count - 1, through: 0, by: -1) {
            let sample = forward[index]
            center.x += (sample.center.x - center.x) * alpha
            center.y += (sample.center.y - center.y) * alpha
            size.width += (sample.box.width - size.width) * alpha
            size.height += (sample.box.height - size.height) * alpha
            backward[index].center = center
            backward[index].box = CGRect(x: center.x - size.width / 2,
                                         y: center.y - size.height / 2,
                                         width: size.width,
                                         height: size.height)
        }

        // 再来一层滑动平均，压掉残余抖动
        let window = 3
        var result = backward
        for index in 0..<result.count {
            let low = max(0, index - window)
            let high = min(result.count - 1, index + window)
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            for j in low...high {
                sumX += backward[j].center.x
                sumY += backward[j].center.y
            }
            let count = CGFloat(high - low + 1)
            result[index].center = CGPoint(x: sumX / count, y: sumY / count)
        }
        return result
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
