import Foundation
import Testing
@testable import Lotto

@MainActor struct LotteryOddsTests {
    @Test func firstPrizeMatchesOfficialGameSpaces() {
        #expect(LotteryOdds.choose(34, 7) == 5_379_616)
        #expect(LotteryOdds.choose(48, 6) * 5 == 61_357_560)
        #expect(LotteryOdds.choose(50, 5) * 66 == 139_838_160)
        for (game, denominator) in [(LotteryReportGame.lotto,5_379_616.0),(.vikinglotto,61_357_560),(.eurojackpot,139_838_160)] {
            let odds = LotteryOdds.chances(game: game)
            #expect(abs(odds.first - 1 / denominator) < 1e-15)
            #expect(odds.any > odds.first && odds.any < 1)
            #expect(odds.rows == 1)
        }
    }
    @Test func fullSystemsDoNotTreatConstituentRowsAsIndependent() {
        let lotto = LotteryOdds.chances(game: .lotto, main: 9, extra: 0)
        let expected = (4...7).reduce(0.0) { $0 + LotteryOdds.choose(9,$1) * LotteryOdds.choose(25,7-$1) } / LotteryOdds.choose(34,7)
        #expect(lotto.rows == 36)
        #expect(abs(lotto.any - expected) < 1e-12)
        #expect(abs(lotto.first - 36 / 5_379_616.0) < 1e-15)
        #expect(lotto.any < 36 * LotteryOdds.chances(game: .lotto).any)
        let viking = LotteryOdds.chances(game: .vikinglotto, main: 8, extra: 3)
        #expect(viking.rows == 84)
        #expect(abs(viking.first - 84 / 61_357_560.0) < 1e-15)
        // Any ordinary Vikinglotto prize starts at 3 main numbers, regardless of Viking number.
        #expect(abs(viking.any - LotteryOdds.chances(game: .vikinglotto, main: 8, extra: 1).any) < 1e-12)
        let euro = LotteryOdds.chances(game: .eurojackpot, main: 7, extra: 2)
        #expect(euro.rows == 21)
        #expect(abs(euro.first - 21 / 139_838_160.0) < 1e-15)
    }
    @Test func ordinaryPrizeProbabilityAndBounds() {
        let euro = LotteryOdds.chances(game: .eurojackpot)
        // Independent enumeration of the 12 ordinary prize groups for one row.
        let tiers = [(5,2),(5,1),(5,0),(4,2),(4,1),(3,2),(4,0),(2,2),(3,1),(3,0),(1,2),(2,1)]
        let winning = tiers.reduce(0.0) { total, pair in
            total + LotteryOdds.choose(5,pair.0) * LotteryOdds.choose(45,5-pair.0) * LotteryOdds.choose(2,pair.1) * LotteryOdds.choose(10,2-pair.1)
        }
        #expect(abs(euro.any - winning / 139_838_160.0) < 1e-12)
        for game in LotteryReportGame.allCases {
            let main = game == .lotto ? 34 : (game == .vikinglotto ? 48 : 50)
            let extra = game == .lotto ? 0 : (game == .vikinglotto ? 5 : 12)
            let all = LotteryOdds.chances(game: game, main: main, extra: extra)
            #expect(abs(all.first - 1) < 1e-12)
            #expect(abs(all.any - 1) < 1e-12)
            #expect(LotteryOdds.chances(game: game, main: 0).rows == 0)
        }
        #expect(!LotteryOdds.text(euro.first).contains("(0,00 %)"))
    }
}
