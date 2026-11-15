import SwiftUI
import SwiftData

struct LotteryWinningsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var deliveries: [LotteryDeliveryChange]
    @State private var cache = LotteryPrizeCache.shared
    @State private var from = LotteryCalendar.calendar.dateInterval(of: .month, for: .now)!.start
    @State private var through = Date()
    @State private var gameID = "all"
    private var rows: [LotteryReportRow] {
        let end = LotteryCalendar.calendar.date(byAdding: .day, value: 1, to: LotteryCalendar.day(through))!
        return AutomaticLotteryLedger.deliveredRows(deliveries.map(\.record)).filter {
            $0.date >= LotteryCalendar.day(from) && $0.date < end && (gameID == "all" || $0.game.rawValue == gameID)
        }
    }
    private var items: [AutomaticLotteryLedgerItem] { AutomaticLotteryLedger.items(rows: rows, tables: cache.tables) }
    private var winners: [AutomaticLotteryLedgerItem] { items.filter { ($0.prizeOre ?? 0) > 0 }.sorted { $0.row.date > $1.row.date } }
    var body: some View {
        NavigationStack {
            List {
                Section("Periode") {
                    DatePicker("Fra", selection: $from, displayedComponents: .date)
                    DatePicker("Til og med", selection: $through, in: from..., displayedComponents: .date)
                    Picker("Spill", selection: $gameID) {
                        Text("Alle spill").tag("all")
                        ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button { Task { await cache.refresh(rows: rows) } } label: { Text(cache.updating ? "Henter premier …" : "Oppdater premier") }.disabled(cache.updating || rows.isEmpty)
                    if let error = cache.error { Text(error).foregroundStyle(.orange) }
                }
                Section("Mine gevinster") {
                    LabeledContent("Sum kjente gevinster", value: LotteryLedger.money(winners.reduce(0) { $0 + ($1.prizeOre ?? 0) }))
                    LabeledContent("Rekker med gevinst", value: "\(winners.count)")
                    LabeledContent("Venter på resultat / premie", value: "\(items.filter { $0.prizeOre == nil }.count)")
                    Text("Bare unike rekker merket Levert / registrert hos Norsk Tipping tas med. Manglende premier regnes ikke som null. Tilleggstrekninger, Joker og manuelle beløp er ikke med her. Kontroller alltid gevinst hos Norsk Tipping.").font(.footnote).foregroundStyle(.secondary)
                    if winners.isEmpty { Text("Ingen kjente gevinster i valgt periode.") }
                    ForEach(winners) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.row.game.title) · \(LotteryCalendar.text(item.row.date))").font(.headline)
                            Text(item.row.mainText + (item.row.extraNumbers.isEmpty ? "" : " + " + item.row.extraText)).monospacedDigit()
                            Text(LotteryLedger.money(item.prizeOre ?? 0)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("Mine gevinster")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .onChange(of: from) { _, value in if through < value { through = value } }
            .task(id: rows.map(\.id)) { await cache.refresh(rows: rows) }
        }
    }
}
