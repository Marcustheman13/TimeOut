import Foundation
import Observation

/// Which leagues the user follows (PRD could-have: pick which sports to focus on).
@Observable
final class SportsPreferences {
    private static let followedKey = "followedLeagues"
    private static let onboardedKey = "hasPickedSports"

    private(set) var followed: Set<League>
    private(set) var hasPicked: Bool

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: Self.followedKey) as? [String] {
            let leagues = Set(saved.compactMap(League.init(rawValue:)))
            followed = leagues.isEmpty ? Set(League.allCases) : leagues
        } else {
            followed = Set(League.allCases)
        }
        hasPicked = defaults.bool(forKey: Self.onboardedKey)
    }

    /// Followed leagues in display order.
    var ordered: [League] { League.allCases.filter(followed.contains) }

    func isFollowing(_ league: League) -> Bool { followed.contains(league) }

    /// Replaces the followed set. At least one league must stay followed.
    func save(_ leagues: Set<League>) {
        guard !leagues.isEmpty else { return }
        followed = leagues
        hasPicked = true
        UserDefaults.standard.set(League.allCases.filter(leagues.contains).map(\.rawValue), forKey: Self.followedKey)
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
    }
}
