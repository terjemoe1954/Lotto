import SwiftUI

struct LotteryOddsSummary: View {
    let game: LotteryReportGame
    var main: Int? = nil
    var extra: Int? = nil
    /// For distinct ordinary rows, first-prize events are disjoint. The
    /// at-least-one-any-prize chance of a batch depends on its actual overlap.
    var ordinaryRows = 1
    private var odds: LotteryOdds.Chances { LotteryOdds.chances(game: game, main: main, extra: extra) }
    private var isSystem: Bool { main != nil }
    private var count: Int { isSystem ? odds.rows : max(0, ordinaryRows) }
    var body: some View {
        Section("Pris og vinnersjanse · én trekning") {
            LabeledContent("Antall enkeltrekker", value: "\(count)")
            LabeledContent("Beregnet pris", value: LotteryLedger.money(count * AutomaticLotteryLedger.priceOre(game)))
            VStack(alignment: .leading, spacing: 4) {
                Text("Førstepremie – \(count == 1 ? "én rekke" : (isSystem ? "hele systemet" : "ulike rekker"))").font(.subheadline)
                Text(LotteryOdds.text(odds.first * Double(isSystem ? 1 : count))).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(isSystem ? "Minst én ordinær premie – hele systemet" : "Ordinær premie – per enkeltrekke").font(.subheadline)
                Text(LotteryOdds.text(odds.any)).monospacedDigit()
            }
            if !isSystem && count > 1 {
                Text("Sjansen for minst én ordinær premie på flere rekker avhenger av hvilke tall de deler. Tallet over gjelder én rekke og skal ikke ganges med antall rekker.").font(.footnote)
            }
            Text("Statistikk og favoritttall øker ikke sjansen for at en enkeltrekke vinner. Alle gyldige enkeltrekker i samme spill har lik sjanse. Flere ulike rekker koster mer og gir ingen garanti for gevinst.").font(.footnote)
            Text("Teoretisk sjanse etter dagens regler, per trekning. Ordinær premie betyr ikke nødvendigvis overskudd. Supertrekning, nasjonale tilleggstrekninger og Joker er ikke med. Pris må kontrolleres hos Norsk Tipping.").font(.footnote).foregroundStyle(.secondary)
            Link("Regler og systemtabeller hos Norsk Tipping", destination: URL(string: "https://www.norsk-tipping.no/bli-kunde/no/kundevilkaar-og-spilleregler")!).font(.footnote)
        }
    }
}
