import Foundation

enum LotteryWeightedSampling {
    static func sample<R: RandomNumberGenerator>(_ weights: [(number: Int, weight: Double)], count: Int, using generator: inout R) -> [Int] {
        var pool = weights
        var result: [Int] = []
        while result.count < count && !pool.isEmpty {
            let total = pool.reduce(0.0) { $0 + max(0.001, $1.weight) }
            var value = Double.random(in: 0..<total, using: &generator)
            var chosen = pool.count - 1
            for i in pool.indices {
                value -= max(0.001, pool[i].weight)
                if value < 0 { chosen = i; break }
            }
            result.append(pool.remove(at: chosen).number)
        }
        return result.sorted()
    }
}
