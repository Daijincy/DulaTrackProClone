//
//  DTPProjectStore.swift
//  DulaTrackPro Clone
//

import UIKit

struct DTPProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var fileName: String
    var createdAt: Date
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var thumbnailFileName: String?

    var durationText: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var resolutionText: String {
        "\(pixelWidth)×\(pixelHeight)"
    }
}

final class DTPProjectStore {

    static let shared = DTPProjectStore()

    private(set) var projects: [DTPProject] = []

    let rootDirectory: URL
    let importsDirectory: URL
    let exportsDirectory: URL
    private let thumbnailsDirectory: URL
    private let indexURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootDirectory = documents.appendingPathComponent("DulaTrackPro", isDirectory: true)
        importsDirectory = rootDirectory.appendingPathComponent("Imports", isDirectory: true)
        exportsDirectory = rootDirectory.appendingPathComponent("Exports", isDirectory: true)
        thumbnailsDirectory = rootDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        indexURL = rootDirectory.appendingPathComponent("projects.json")

        [rootDirectory, importsDirectory, exportsDirectory, thumbnailsDirectory].forEach {
            try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: - 读写

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let value = try? JSONDecoder().decode([DTPProject].self, from: data) else { return }
        projects = value
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - 路径

    func mediaURL(for project: DTPProject) -> URL {
        importsDirectory.appendingPathComponent(project.fileName)
    }

    func thumbnailURL(for project: DTPProject) -> URL? {
        guard let name = project.thumbnailFileName else { return nil }
        let url = thumbnailsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func makeExportURL(basedOn name: String, fileExtension: String = "mov") -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = exportsDirectory.appendingPathComponent("\(safeName)-\(formatter.string(from: Date())).\(fileExtension)")
        try? FileManager.default.removeItem(at: url)
        return url
    }

    // MARK: - 增删

    @discardableResult
    func importVideo(from tempURL: URL,
                     name: String,
                     duration: Double,
                     size: CGSize,
                     thumbnail: UIImage?) -> DTPProject? {
        let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = importsDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: tempURL, to: destination)
        } catch {
            return nil
        }

        var thumbnailName: String?
        if let thumbnail,
           let data = thumbnail.jpegData(compressionQuality: 0.82) {
            let name = "\(UUID().uuidString).jpg"
            let url = thumbnailsDirectory.appendingPathComponent(name)
            if (try? data.write(to: url, options: .atomic)) != nil {
                thumbnailName = name
            }
        }

        let project = DTPProject(id: UUID(),
                                 name: name,
                                 fileName: fileName,
                                 createdAt: Date(),
                                 duration: duration,
                                 pixelWidth: max(Int(size.width.rounded()), 1),
                                 pixelHeight: max(Int(size.height.rounded()), 1),
                                 thumbnailFileName: thumbnailName)
        projects.insert(project, at: 0)
        persist()
        return project
    }

    func delete(_ project: DTPProject) {
        try? FileManager.default.removeItem(at: mediaURL(for: project))
        if let thumbnailURL = thumbnailURL(for: project) {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
        projects.removeAll { $0.id == project.id }
        persist()
    }

    func project(with id: UUID) -> DTPProject? {
        projects.first { $0.id == id }
    }
}
