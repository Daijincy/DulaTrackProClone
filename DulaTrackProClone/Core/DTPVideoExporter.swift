//
//  DTPVideoExporter.swift
//  DulaTrackPro Clone
//
//  用 AVMutableVideoComposition 的图层变换实现"跟随主体的动态裁切"，
//  音轨原样保留；导出使用最高质量预设（优先 HEVC）。
//

import Foundation
import AVFoundation
import Photos
import UIKit

enum DTPAspect: String, Codable, CaseIterable {
    case original
    case vertical
    case square
    case landscape

    var title: String {
        switch self {
        case .original: return "原画"
        case .vertical: return "9:16"
        case .square: return "1:1"
        case .landscape: return "16:9"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .vertical: return 9.0 / 16.0
        case .square: return 1
        case .landscape: return 16.0 / 9.0
        }
    }
}

struct DTPExportOptions {
    var aspect: DTPAspect = .vertical
    var zoom: CGFloat = 1
    var autoFrame: Bool = true
    var stabilize: Bool = true
    var saveToPhotos: Bool = true
}

enum DTPMediaError: LocalizedError {
    case noVideoTrack
    case detectorUnavailable
    case exportFailed
    case cancelled
    case photoAccessDenied

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "视频里没有找到可用的画面轨道。"
        case .detectorUnavailable: return "AI 模型未能加载，已回退为居中裁切。"
        case .exportFailed: return "导出失败，请换一段素材再试。"
        case .cancelled: return "已取消。"
        case .photoAccessDenied: return "没有相册写入权限，可以改用分享保存。"
        }
    }
}

final class DTPVideoExporter {

    private var session: AVAssetExportSession?
    private var progressTimer: Timer?
    private(set) var isExporting = false

    func cancel() {
        session?.cancelExport()
        stopTimer()
        isExporting = false
    }

    func export(asset: AVAsset,
                plan: DTPTrackPlan?,
                options: DTPExportOptions,
                outputURL: URL,
                progress: @escaping (Double) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {
        isExporting = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw DTPMediaError.noVideoTrack
                }
                let duration = try await asset.load(.duration)
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
                let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))

                let cropSize = Self.cropSize(for: options.aspect, displaySize: displaySize, zoom: options.zoom)
                let scale = min(max(1920 / max(cropSize.width, cropSize.height), 0.6), 2.0)
                let renderSize = Self.evenSize(CGSize(width: cropSize.width * scale,
                                                      height: cropSize.height * scale))

                let composition = AVMutableVideoComposition()
                composition.renderSize = renderSize
                composition.frameDuration = CMTime(value: 1, timescale: 30)
                composition.renderScale = 1

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                layerInstruction.setOpacity(1, at: .zero)

                let keyframes = Self.keyframes(plan: plan,
                                               duration: duration.seconds,
                                               autoFrame: options.autoFrame,
                                               stabilize: options.stabilize)

                for (index, keyframe) in keyframes.enumerated() {
                    let origin = Self.cropOrigin(center: keyframe.center,
                                                 cropSize: cropSize,
                                                 displaySize: displaySize)
                    let transform = Self.layerTransform(preferredTransform: preferredTransform,
                                                        cropOrigin: origin,
                                                        scale: scale)
                    let time = CMTime(seconds: min(keyframe.time, duration.seconds), preferredTimescale: 600)

                    if index == 0 {
                        layerInstruction.setTransform(transform, at: .zero)
                    } else {
                        let previous = keyframes[index - 1]
                        let previousOrigin = Self.cropOrigin(center: previous.center,
                                                             cropSize: cropSize,
                                                             displaySize: displaySize)
                        let previousTransform = Self.layerTransform(preferredTransform: preferredTransform,
                                                                    cropOrigin: previousOrigin,
                                                                    scale: scale)
                        let start = CMTime(seconds: previous.time, preferredTimescale: 600)
                        if time.seconds > start.seconds + 0.001 {
                            layerInstruction.setTransformRamp(fromStart: previousTransform,
                                                              toEnd: transform,
                                                              timeRange: CMTimeRange(start: start, end: time))
                        } else {
                            layerInstruction.setTransform(transform, at: time)
                        }
                    }
                }

                instruction.layerInstructions = [layerInstruction]
                composition.instructions = [instruction]

                guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality)
                    ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                    throw DTPMediaError.exportFailed
                }

                session.videoComposition = composition
                session.outputURL = outputURL
                session.outputFileType = session.supportedFileTypes.contains(.mov) ? .mov : .mp4
                session.shouldOptimizeForNetworkUse = true

                await MainActor.run {
                    self.session = session
                    self.startTimer(progress: progress)
                    session.exportAsynchronously {
                        self.stopTimer()
                        self.session = nil
                        self.isExporting = false
                        DispatchQueue.main.async {
                            switch session.status {
                            case .completed:
                                completion(.success(outputURL))
                            case .cancelled:
                                completion(.failure(DTPMediaError.cancelled))
                            default:
                                completion(.failure(session.error ?? DTPMediaError.exportFailed))
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - 进度

    private func startTimer(progress: @escaping (Double) -> Void) {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let session = self.session else { return }
            progress(Double(session.progress))
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - 几何

    static func cropSize(for aspect: DTPAspect, displaySize: CGSize, zoom: CGFloat) -> CGSize {
        let safeZoom = max(zoom, 1)
        var width = displaySize.width
        var height = displaySize.height

        if let ratio = aspect.ratio {
            if displaySize.width / displaySize.height > ratio {
                height = displaySize.height
                width = height * ratio
            } else {
                width = displaySize.width
                height = width / ratio
            }
        }
        return CGSize(width: width / safeZoom, height: height / safeZoom)
    }

    static func cropOrigin(center: CGPoint, cropSize: CGSize, displaySize: CGSize) -> CGPoint {
        let rawX = center.x * displaySize.width - cropSize.width / 2
        let rawY = center.y * displaySize.height - cropSize.height / 2
        let maxX = max(displaySize.width - cropSize.width, 0)
        let maxY = max(displaySize.height - cropSize.height, 0)
        return CGPoint(x: min(max(rawX, 0), maxX), y: min(max(rawY, 0), maxY))
    }

    private static func layerTransform(preferredTransform: CGAffineTransform,
                                       cropOrigin: CGPoint,
                                       scale: CGFloat) -> CGAffineTransform {
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let translate = CGAffineTransform(translationX: -cropOrigin.x * scale,
                                          y: -cropOrigin.y * scale)
        return preferredTransform.concatenating(scaleTransform).concatenating(translate)
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        let width = max(2, (size.width / 2).rounded() * 2)
        let height = max(2, (size.height / 2).rounded() * 2)
        return CGSize(width: width, height: height)
    }

    /// 关键帧：时间 + 画面中心（归一化，左上角原点）
    private static func keyframes(plan: DTPTrackPlan?,
                                  duration: Double,
                                  autoFrame: Bool,
                                  stabilize: Bool) -> [(time: Double, center: CGPoint)] {
        let fallback: [(time: Double, center: CGPoint)] = [(0, CGPoint(x: 0.5, y: 0.5))]
        guard autoFrame || stabilize, let plan, !plan.samples.isEmpty else { return fallback }

        var points: [(time: Double, center: CGPoint)] = []
        for sample in plan.samples {
            let time = min(max(sample.time, 0), max(duration, 0.05))
            if let last = points.last, time - last.time < 0.02 {
                points[points.count - 1] = (last.time, sample.center)
                continue
            }
            points.append((time, sample.center))
        }

        guard !points.isEmpty else { return fallback }
        if points[0].time > 0.001 {
            points.insert((0, points[0].center), at: 0)
        }
        if let last = points.last, last.time < duration - 0.001 {
            points.append((duration, last.center))
        }
        return points
    }

    // MARK: - 保存到相册

    static func saveToPhotos(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(DTPMediaError.photoAccessDenied)) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? DTPMediaError.exportFailed))
                    }
                }
            }
        }
    }
}
