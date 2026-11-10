import SwiftUI
import SwiftData

struct LotteryFavoritesView: View {
    var introductory = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var changes: [LotteryFavoriteChange]
    @AppStorage("favorites.introSeen") private var introSeen = false
    @State private var game = LotteryReportGame.lotto
    @State private var drafts: [LotteryReportGame: LotteryFavoriteSelection] = [:]
    @State private var error: String?
    @State private var dirty = Set<LotteryReportGame>()
    private var value: LotteryFavoriteSelection { drafts[game] ?? LotteryFavoriteSelection() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Denne appen øker ikke vinnersjansene dine.", systemImage: "info.circle")
                        .font(.headline)
                    Text("Appen viser statistikk, historiske resultater og oversikt over egne rekker. Historiske mønstre kan ikke forutsi neste trekning.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text(introductory ? "Velg dine favoritttall" : "Favoritttall")
                        .font(.title2.bold())
                    Text("Valgfritt: Velg så mange favoritter du ønsker, opp til antall tall i en rekke. Favorittene blir faste i forslagene når de er slått på. Resten av tallene velges av forslagsfunksjonen.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("Spill", selection: $game) {
                        ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Toggle("Bruk favoritttall i forslag", isOn: Binding(get: { value.enabled }, set: { enabled in
                        var selection = value; selection.enabled = enabled; drafts[game] = selection; dirty.insert(game)
                    }))
                }
                Section("Hovedtall: \(value.mainNumbers.count) av maksimalt \(game.mainCount)") {
                    grid(maximum: game.mainMaximum, limit: game.mainCount, extra: false)
                }
                if game.extraCount > 0 {
                    Section("\(game.extraTitle): \(value.extraNumbers.count) av maksimalt \(game.extraCount)") {
                        grid(maximum: game.extraMaximum, limit: game.extraCount, extra: true)
                    }
                }
                Section {
                    Button("Fjern favoritter for \(game.title)", role: .destructive) {
                        drafts[game] = LotteryFavoriteSelection(enabled: value.enabled); dirty.insert(game)
                    }
                    if value.enabled && value.combinations(for: game) == 1 {
                        Text("Du har fylt alle plassene med favoritter. Da finnes bare én unik rekke for dette spillet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Valgene lagres per spill og kan synkroniseres med din private iCloud. Du kan endre dem fra Favoritter øverst i appen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(introductory ? "Velkommen" : "Favoritttall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(introductory ? "Hopp over" : "Avbryt") {
                        if introductory { introSeen = true }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        do {
                            try LotteryFavorites.save(drafts.filter { dirty.contains($0.key) }, context: context)
                            introSeen = true
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onChange(of: changes.map(\.record)) { _, records in
                for game in LotteryReportGame.allCases where !dirty.contains(game) {
                    drafts[game] = LotteryFavorites.selection(for: game, records: records)
                }
            }
            .onAppear {
                for game in LotteryReportGame.allCases {
                    drafts[game] = LotteryFavorites.selection(for: game, records: changes.map(\.record))
                }
            }
        }
        .interactiveDismissDisabled(introductory)
    }
    private func grid(maximum: Int, limit: Int, extra: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(1...maximum, id: \.self) { number in
                let selected = (extra ? value.extraNumbers : value.mainNumbers).contains(number)
                Button {
                    var selection = value
                    var values = extra ? selection.extraNumbers : selection.mainNumbers
                    if let index = values.firstIndex(of: number) { values.remove(at: index) }
                    else if values.count < limit { values.append(number) }
                    if extra { selection.extraNumbers = values.sorted() } else { selection.mainNumbers = values.sorted() }
                    drafts[game] = selection; dirty.insert(game)
                } label: {
                    Text("\(number)").font(.body.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(extra ? game.extraTitle : "Hovedtall") \(number)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
