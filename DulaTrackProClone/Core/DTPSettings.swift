//
//  DTPSettings.swift
//  DulaTrackPro Clone
//

import Foundation

struct DTPSettings: Codable {

    private static let storageKey = "dtp.settings.v2"

    var aspect: DTPAspect = .vertical
    var saveToPhotos: Bool = true
    var autoFrame: Bool = true
    var stabilize: Bool = true
    var preferredLabels: [String] = ["人物", "汽车"]

    static func load() -> DTPSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(DTPSettings.self, from: data) else {
            return DTPSettings()
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
