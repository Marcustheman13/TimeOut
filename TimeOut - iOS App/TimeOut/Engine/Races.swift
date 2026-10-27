import Foundation
import Observation

/// Virtual horse racing: the field, race state and grading. A port of the web demo's races.js.
@Observable
final class Races {
    static let shared = Races()

    struct Horse: Hashable {
        var id: Int
        var number: Int
        var name: String
        var americanOdds: Int
        var form: String
        var jockey: String
        var color: String
        var speed: Double
        var variance: Double
    }

    struct Race: Codable, Hashable {
        var number: Int
        var status: String // open | running | final
        var startedAt: Ms?
        var finishAt: Ms?
        var finishedAt: Ms?
        var winnerId: Int?
        var order: [Int]?
        var betId: String?
    }

    private struct Saved: Codable {
        var next: Int
        var current: Race?
        var history: [Race]
    }

    static let horses: [Horse] = [
        Horse(id: 1, number: 1, name: "Midnight Surge", americanOdds: 180, form: "2-1-2", jockey: "R. Vance", color: "#4fb3ff", speed: 1.025, variance: 0.18),
        Horse(id: 2, number: 2, name: "Silicon Sprint", americanOdds: 220, form: "1-3-1", jockey: "K. Chen", color: "#22d66e", speed: 1.018, variance: 0.19),
        Horse(id: 3, number: 3, name: "Digital Blitz", americanOdds: 260, form: "3-2-1", jockey: "T. Hayes", color: "#ffc940", speed: 1.010, variance: 0.20),
        Horse(id: 4, number: 4, name: "Golden Hour", americanOdds: 310, form: "2-1-4", jockey: "L. Moreno", color: "#ff718d", speed: 1.002, variance: 0.21),
        Horse(id: 5, number: 5, name: "Circuit Breaker", americanOdds: 380, form: "1-4-2", jockey: "D. Sterling", color: "#c58cff", speed: 0.995, variance: 0.22),
    ]

    private static let key = "timeout.virtualRaces"
    private var data: Saved
    private(set) var version = 0

    private init() {
        if let raw = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Saved.self, from: raw) {
            data = saved
        } else {
            data = Saved(next: 48, current: nil, history: [])
        }
        if data.current == nil { data.current = Race(number: data.next, status: "open") }
    }

    private func persist() {
        if let raw = try? JSONEncoder().encode(data) { UserDefaults.standard.set(raw, forKey: Self.key) }
        version &+= 1
    }

    var current: Race { data.current ?? Race(number: data.next, status: "open") }

    var latest: Race? { data.history.first }

    func get(_ raceId: String?) -> Race? {
        guard let raceId else { return nil }
        let number = Int(raceId.replacingOccurrences(of: "race-", with: "")) ?? -1
        if current.number == number { return current }
        return data.history.first { $0.number == number }
    }

    func horse(_ id: Int?) -> Horse { Self.horses.first { $0.id == id } ?? Self.horses[0] }

    func selection(_ race: Race, _ runner: Horse) -> Selection {
        Selection(id: "race-\(race.number)|race|\(runner.id)", kind: "race", raceId: "race-\(race.number)", horseId: runner.id,
                  market: "race", side: String(runner.id), line: nil, price: runner.americanOdds)
    }

    func currentSelection(_ selId: String) -> (sel: Selection?, open: Bool)? {
        let parts = selId.split(separator: "|").map(String.init)
        guard parts.count == 3, parts[1] == "race" else { return nil }
        let race = get(parts[0])
        let runner = horse(Int(parts[2]))
        let base = race ?? Race(number: Int(parts[0].replacingOccurrences(of: "race-", with: "")) ?? 0, status: "final")
        return (selection(base, runner), race?.status == "open")
    }

    private static func implied(_ american: Int) -> Double {
        american > 0 ? 100 / Double(american + 100) : Double(abs(american)) / Double(abs(american) + 100)
    }

    private func weightedWinner(_ seed: String) -> Int {
        let rng = TO.RNG(seed)
        let total = Self.horses.reduce(0) { $0 + Self.implied($1.americanOdds) }
        var roll = rng() * total
        for h in Self.horses {
            roll -= Self.implied(h.americanOdds)
            if roll <= 0 { return h.id }
        }
        return Self.horses[0].id
    }

    private func begin(seed: String, now: Ms, betId: String?) {
        var race = current
        let winnerId = weightedWinner("\(race.number)-\(seed)-\(Int64(now))")
        let rest = Self.horses.filter { $0.id != winnerId }.sorted {
            TO.u01("\(seed)-\($0.id)") * $0.speed > TO.u01("\(seed)-\($1.id)") * $1.speed
        }
        race.status = "running"
        race.startedAt = now
        race.finishAt = now + 12_000
        race.winnerId = winnerId
        race.order = [winnerId] + rest.map(\.id)
        race.betId = betId
        data.current = race
        persist()
    }

    func startForBet(_ bet: Bet, now: Ms = TO.now()) throws {
        let race = current
        guard race.status == "open", bet.legs.first?.raceId == "race-\(race.number)" else {
            throw AppError(code: "closed", message: "That race is no longer taking bets.")
        }
        begin(seed: bet.id, now: now, betId: bet.id)
    }

    func startForViewing() {
        guard current.status == "open" else { return }
        begin(seed: "watch-\(TO.uid("race"))", now: TO.now(), betId: nil)
    }

    /// Moves a finished race into history and opens the next one.
    @discardableResult
    func finalizeIfDone(_ now: Ms = TO.now()) -> Bool {
        var race = current
        guard race.status == "running", let finishAt = race.finishAt, now >= finishAt else { return false }
        race.status = "final"
        race.finishedAt = finishAt
        data.history.insert(race, at: 0)
        data.history = Array(data.history.prefix(20))
        data.next = race.number + 1
        data.current = Race(number: data.next, status: "open")
        persist()
        return true
    }

    func grade(_ leg: Leg, _ now: Ms = TO.now()) -> String {
        finalizeIfDone(now)
        guard let race = get(leg.raceId ?? leg.selId.split(separator: "|").first.map(String.init)) else { return "void" }
        if race.status != "final" { return "pending" }
        return race.winnerId == (leg.horseId ?? Int(leg.side ?? "")) ? "won" : "lost"
    }

    static func statusText(_ race: Race) -> String {
        if race.status == "running" { return "Race in progress" }
        return race.status == "final" ? "Race #\(race.number) finished" : "Bets open"
    }
}
