//
//  DTPMediaImporter.swift
//  DulaTrackPro Clone
//

import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
final class DTPMediaImporter: NSObject, PHPickerViewControllerDelegate {

    static let shared = DTPMediaImporter()

    private var completion: (([DTPProject]) -> Void)?

    func present(from presenter: UIViewController, completion: @escaping ([DTPProject]) -> Void) {
        self.completion = completion

        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        let completion = self.completion
        self.completion = nil

        guard !results.isEmpty else {
            completion?([])
            return
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DTPPicker-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let group = DispatchGroup()
        let lock = NSLock()
        var files: [URL] = []

        for provider in results.map({ $0.itemProvider })
        where provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let destination = tempDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                    lock.lock()
                    files.append(destination)
                    lock.unlock()
                } catch {
                    // 跳过失败的素材
                }
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                let projects = await Self.importFiles(files)
                completion?(projects)
            }
        }
    }

    private static func importFiles(_ files: [URL]) async -> [DTPProject] {
        var projects: [DTPProject] = []
        var index = 1

        for url in files {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0

            var size = CGSize(width: 1920, height: 1080)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let natural = (try? await track.load(.naturalSize)) ?? size
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }

            let thumbnail = await makeThumbnail(asset: asset, duration: duration)
            let baseName = "素材 \(Self.timeFormatter.string(from: Date()))"
            let name = index > 1 ? "\(baseName)-\(index)" : baseName

            if let project = DTPProjectStore.shared.importVideo(from: url,
                                                                name: name,
                                                                duration: duration,
                                                                size: size,
                                                                thumbnail: thumbnail) {
                projects.append(project)
            }
            try? FileManager.default.removeItem(at: url)
            index += 1
        }
        return projects
    }

    static func makeThumbnail(asset: AVAsset, duration: Double) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let seconds = max(0.05, min(duration * 0.12, 2.0))
        guard let result = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: result.image)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
