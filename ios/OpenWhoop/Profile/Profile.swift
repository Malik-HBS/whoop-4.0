import Foundation

/// Body-stat profile sent to / received from the server's /v1/profile endpoint.
/// All values stored in SI units (cm, kg); nil = not yet set.
struct Profile: Codable, Equatable {
    var heightCm: Double?
    var weightKg: Double?
    var age: Int?
    var sex: String?          // "male" | "female" | "nonbinary"

    private enum CodingKeys: String, CodingKey {
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case age
        case sex
    }
}

enum ProfileStorage {
    static let key = "com.openwhoop.profile.v1"

    static func load() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(Profile.self, from: data) else {
            return nil
        }
        return profile
    }

    static func save(_ profile: Profile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
