import SwiftUI
import SwiftData

struct InternationalSuggestionsView: View {
    let game: InternationalGame
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var favoriteChanges: [LotteryFavoriteChange]
    @Query private var entries: [InternationalLotteryEntry]
    @AppStorage(LottoAppPreferences.toleranceKey) private var tolerance = 3.0
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGap = false
    @State private var date = Date()
    @State private var mode = InternationalSuggestionMode.mixed
    @State private var count = 5
    @State private var batch: InternationalSuggestionBatch?
    @State private var editingRow: InternationalSuggestedRow?
    @State private var message: String?
    @State private var errorMessage: String?

    private var favorites: LotteryFavoriteSelection {
        LotteryFavorites.selection(for: LotteryReportGame(rawValue: game.rawValue)!, records: favoriteChanges.map(\.record))
            .effective(for: LotteryReportGame(rawValue: game.rawValue)!)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Trekningsdato") {
                    DatePicker("For dato", selection: $date, displayedComponents: .date)
                    Text("Trekning \(game.schedule). Andre datoer flyttes til neste trekningsdag.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Lag forslag") {
                    Picker("Modus", selection: $mode) {
                        ForEach(InternationalSuggestionMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(mode.description).font(.footnote).foregroundStyle(.secondary)
                    if !favorites.mainNumbers.isEmpty || !favorites.extraNumbers.isEmpty {
                        Text("Faste favoritter: \(favorites.mainNumbers.map(String.init).joined(separator: ", "))" + (favorites.extraNumbers.isEmpty ? "" : " + " + favorites.extraNumbers.map(String.init).joined(separator: ", ")))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Stepper("Antall rekker: \(count)", value: $count, in: 1...20)
                    if mode != .random {
                        LabeledContent("Intervalltoleranse", value: "±\(tolerance.formatted(.number.precision(.fractionLength(1)))) dager")
                        Text("Toleranse og utelatelse av lengste intervall følger innstillingene for Lotto.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Lag nye forslag", systemImage: "shuffle") { generate() }
                    Text("Dette er måter å velge tall på. Historiske mønstre gir ikke høyere vinnersjanse. Rekker lagres her; levering skjer hos Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let batch {
                    if batch.mode != .random { historySection(batch) }
                    if batch.rows.count < count {
                        Text("Favorittene begrenser antall unike rekker til \(batch.rows.count).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let message { Section { Text(message).foregroundStyle(.secondary) } }
                    if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                    Section {
                        Button("Lagre alle \(batch.rows.count) rekker") { save(batch.rows, date: batch.date) }
                            .disabled(batch.rows.allSatisfy { isSaved($0, date: batch.date) })
                        ForEach(Array(batch.rows.enumerated()), id: \.element.id) { index, row in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rekke \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                Text(row.text).font(.headline).monospacedDigit()
                                if batch.mode != .random {
                                    Text(candidateText(row, batch: batch)).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Button(isSaved(row, date: batch.date) ? "Lagret" : "Lagre", systemImage: "square.and.arrow.down") {
                                        save([row], date: batch.date)
                                    }.disabled(isSaved(row, date: batch.date))
                                    Spacer()
                                    Button("Kontroller / endre", systemImage: "pencil") { editingRow = row }
                                }.buttonStyle(.bordered)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("\(batch.rows.count) forslag · \(LotteryCalendar.text(batch.date))") }
                }
            }
            .navigationTitle("\(game.title) forslag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Ferdig") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let batch {
                        ShareLink(item: shareText(batch)) { Label("Del forslag", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(item: $editingRow) { row in
                if let batch { LotteryEntryEditor(game: game, mode: .row, initialRow: row, initialDate: batch.date) }
            }
            .onAppear { generate() }
            .onChange(of: date) { _, _ in generate() }
            .onChange(of: mode) { _, _ in generate() }
            .onChange(of: count) { _, _ in generate() }
            .onChange(of: favoriteChanges.map(\.record)) { _, _ in generate() }
            .onChange(of: tolerance) { _, _ in generate() }
            .onChange(of: excludeHighestGap) { _, _ in generate() }
        }
    }

    private func historySection(_ batch: InternationalSuggestionBatch) -> some View {
        Section {
            LabeledContent("Tidligere trekninger", value: "\(batch.historyDrawCount)")
            LabeledContent("Samme ukenummer i tidligere år", value: "\(batch.sameWeekDrawCount)")
            if batch.historyDrawCount == 0 {
                Text("Ingen tidligere trekninger for denne datoen. Forslagene trekkes med lik vekt.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Hovedtall: \(numbers(batch.mainCandidates))")
                Text("\(game.extraTitle): \(numbers(batch.extraCandidates))")
                Text("Tallene over følger en beregnet historisk intervallrytme nær valgt dato. Dette er ikke en prognose. Bare resultater før valgt trekning og fram til i dag brukes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Historisk grunnlag") }
    }
    private func candidateText(_ row: InternationalSuggestedRow, batch: InternationalSuggestionBatch) -> String {
        let main = row.mainNumbers.filter { batch.mainCandidates.contains($0) }
        let extra = row.extraNumbers.filter { batch.extraCandidates.contains($0) }
        return "Intervalltreff: \(main.count) hovedtall + \(extra.count) \(game.extraTitle.lowercased())"
    }
    private func numbers(_ values: [Int]) -> String { values.isEmpty ? "Ingen intervalltreff" : values.map(String.init).joined(separator: ", ") }
    private func isSaved(_ row: InternationalSuggestedRow, date: Date) -> Bool {
        entries.contains {
            !$0.isDraw && $0.gameID == game.rawValue && LotteryCalendar.day($0.date) == LotteryCalendar.day(date) &&
            $0.mainNumbers.sorted() == row.mainNumbers && $0.extraNumbers.sorted() == row.extraNumbers
        }
    }
    private func generate() {
        let normalized = game.nextDraw(onOrAfter: date)
        if date != normalized { date = normalized; return }
        batch = InternationalSuggestionEngine.makeRows(game: game, date: normalized,
            records: entries.map(\.archiveRecord), mode: mode, count: count,
            toleranceDays: tolerance, excludeHighestGap: excludeHighestGap, favorites: favorites)
        message = nil
        errorMessage = nil
    }
    private func save(_ rows: [InternationalSuggestedRow], date: Date) {
        do {
            let added = try InternationalSuggestedRowSaver.save(rows, game: game, date: date, context: context)
            message = added == 0 ? "Rekkene er allerede lagret på denne datoen." : "Lagret \(added) nye rekker på \(LotteryCalendar.text(date))."
            errorMessage = nil
        } catch { errorMessage = "Kunne ikke lagre: \(error.localizedDescription)" }
    }
    private func shareText(_ batch: InternationalSuggestionBatch) -> String {
        (["\(game.title) · \(LotteryCalendar.text(batch.date)) · \(batch.mode.title)"] +
         batch.rows.enumerated().map { "\($0.offset + 1). \($0.element.text)" } +
         ["Forslagene gir ikke høyere vinnersjanse. Levering skjer hos Norsk Tipping."]).joined(separator: "\n")
    }
}
