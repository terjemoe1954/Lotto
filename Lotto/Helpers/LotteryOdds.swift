import Foundation

/// Probabilities for one draw under the current ordinary prize rules.
/// Full-system constituent rows overlap: count hypergeometric pool hits,
/// rather than assuming independent tickets or adding prize probabilities.
enum LotteryOdds {
    struct Chances {
        let first: Double
        let any: Double
        let rows: Int
    }
    static func choose(_ n: Int, _ k: Int) -> Double {
        guard n >= 0, k >= 0, k <= n else { return 0 }
        let k = min(k, n - k)
        if k == 0 { return 1 }
        return (1...k).reduce(1.0) { $0 * Double(n - k + $1) / Double($1) }
    }
    static func chances(game: LotteryReportGame, main: Int? = nil, extra: Int? = nil) -> Chances {
        let k = LotterySystem.mainCount(game), e = LotterySystem.extraCount(game)
        let n = game == .lotto ? 34 : (game == .vikinglotto ? 48 : 50)
        let x = game == .lotto ? 0 : (game == .vikinglotto ? 5 : 12)
        let m = main ?? k, a = extra ?? e
        guard (k...n).contains(m), (e...x).contains(a) else { return Chances(first: 0, any: 0, rows: 0) }
        let mainTotal = choose(n, k), extraTotal = choose(x, e)
        let rows = choose(m, k) * choose(a, e)
        var any = 0.0
        for h in 0...k {
            let pMain = choose(m, h) * choose(n - m, k - h) / mainTotal
            for t in 0...e {
                let pExtra = choose(a, t) * choose(x - a, e - t) / extraTotal
                if AutomaticLotteryLedger.tier(game: game, main: h, extra: t) != nil {
                    any += pMain * pExtra
                }
            }
        }
        return Chances(first: rows / (mainTotal * extraTotal), any: min(1, any), rows: Int(rows))
    }
    static func text(_ probability: Double) -> String {
        guard probability > 0, probability <= 1 else { return "Ikke tilgjengelig" }
        let inverse = NumberFormatter()
        inverse.locale = Locale(identifier: "nb_NO"); inverse.numberStyle = .decimal
        inverse.maximumFractionDigits = probability > 0.1 ? 1 : 0
        let percent = NumberFormatter()
        percent.locale = Locale(identifier: "nb_NO"); percent.numberStyle = .decimal
        percent.minimumFractionDigits = 2; percent.maximumFractionDigits = 8
        return "ca. 1 av \(inverse.string(from: NSNumber(value: 1 / probability)) ?? "–") (\(percent.string(from: NSNumber(value: probability * 100)) ?? "–") %)"
    }
}
