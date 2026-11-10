import SwiftUI
import SwiftData

struct LotteryHomeView: View {
    @AppStorage("selectedLottery") private var selection = "lotto"
    @Environment(\.modelContext) private var context
    @Query private var lottoRows: [Result]
    @Query private var internationalRows: [InternationalLotteryEntry]
    @State private var migrationError: String?
    @AppStorage("favorites.introSeen") private var favoritesIntroSeen = false
    @Query private var favoriteChanges: [LotteryFavoriteChange]
    @State private var showFavorites = false
    @State private var favoriteIntro = false
    @State private var showWeeklyReport = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("Spill", selection: $selection) {
                Text("Lotto").tag("lotto")
                ForEach(InternationalGame.allCases) { game in Text(game.title).tag(game.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            HStack {
                Button("Favoritter", systemImage: "star") { favoriteIntro = false; showFavorites = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Ukesrapport", systemImage: "printer") { showWeeklyReport = true }
                    .buttonStyle(.bordered)
            }.padding(.horizontal).padding(.bottom, 4)
            if let game = InternationalGame(rawValue: selection) {
                InternationalLotteryView(game: game).id(game)
            } else {
                FirstView()
            }
        }
        .sheet(isPresented: $showFavorites) { LotteryFavoritesView(introductory: favoriteIntro) }
        .task {
            if !favoritesIntroSeen {
                if favoriteChanges.isEmpty { favoriteIntro = true; showFavorites = true }
                else { favoritesIntroSeen = true }
            }
        }
        .sheet(isPresented: $showWeeklyReport) { WeeklyLotteryReportView() }
        .task(id: WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows).map(\.id)) {
            do {
                try LotteryDeliverySync.migrateLegacy(rows: WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows), context: context)
            } catch { context.rollback(); migrationError = "Kunne ikke flytte registreringsmarkeringer: \(error.localizedDescription)" }
        }
        .alert("Registreringsmarkeringer", isPresented: Binding(get: { migrationError != nil }, set: { if !$0 { migrationError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(migrationError ?? "") }
    }
}

struct InternationalLotteryView: View {
    let game: InternationalGame
    @Environment(\.modelContext) private var context
    @Query(sort: \InternationalLotteryEntry.date, order: .reverse) private var entries: [InternationalLotteryEntry]
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearance = AppearanceMode.system.rawValue
    @State private var editor: LotteryEditorMode?
    @State private var showStatistics = false
    @State private var showSuggestions = false
    @State private var showSettings = false
    @State private var updating = false
    @State private var progress = ""
    @State private var message: String?
    @State private var showingDraws = false
    @State private var showAll = false
    private var draws: [InternationalLotteryEntry] {
        var dates = Set<String>()
        return entries.filter { $0.gameID == game.rawValue && $0.isDraw && dates.insert(LotteryCalendar.text($0.date)).inserted }
    }
    private var rows: [InternationalLotteryEntry] { entries.filter { $0.gameID == game.rawValue && !$0.isDraw } }
    private var visible: [InternationalLotteryEntry] {
        let source = showingDraws ? draws : rows
        return showAll ? source : Array(source.prefix(50))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(game.mainCount) hovedtall av \(game.mainMaximum) + \(game.extraCount) \(game.extraTitle.lowercased()) av \(game.extraMaximum)")
                    Text("Trekning \(game.schedule)").foregroundStyle(.secondary)
                    HStack {
                        Button("Ny rekke", systemImage: "plus.circle") { editor = .row }
                        Spacer()
                        Button("Forslag", systemImage: "wand.and.stars") { showSuggestions = true }
                    }.buttonStyle(.bordered)
                    Button("Statistikk", systemImage: "chart.bar") { showStatistics = true }
                }
                Section("Resultater fra Norsk Tipping") {
                    LabeledContent("Lagrede trekninger", value: "\(draws.count)")
                    if let latest = draws.first { LabeledContent("Siste trekning", value: LotteryCalendar.text(latest.date)) }
                    Button {
                        Task { await update() }
                    } label: {
                        HStack {
                            if updating { ProgressView() }
                            Text(updating ? "Oppdaterer …" : "Hent nye trekninger")
                        }
                    }.disabled(updating)
                    if updating { Text(progress).font(.caption).foregroundStyle(.secondary) }
                    Text("Historikk fra 2023. Bare ferdigbehandlede trekninger vises. Egne rekker lagres her; levering skjer hos Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Vis", selection: $showingDraws) {
                        Text("Mine rekker (\(rows.count))").tag(false)
                        Text("Trekninger (\(draws.count))").tag(true)
                    }.pickerStyle(.segmented)
                    if visible.isEmpty {
                        Text(showingDraws ? "Ingen trekninger ennå. Trykk Hent nye trekninger." : "Ingen egne rekker ennå. Lagre en rekke eller prøv Forslag.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(LotteryCalendar.text(entry.date)).font(.caption).foregroundStyle(.secondary)
                            Text(entry.numbersText).font(.headline).monospacedDigit()
                            if !entry.isDraw { Text(matchText(entry)).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .contextMenu {
                            ShareLink(item: "\(game.title) \(LotteryCalendar.text(entry.date))\n\(entry.numbersText)") {
                                Label("Del rekke", systemImage: "square.and.arrow.up")
                            }
                            if !entry.isDraw {
                                Button("Slett rekke", role: .destructive) { delete(entry) }
                            }
                        }
                    }
                    if !showAll && (showingDraws ? draws.count : rows.count) > 50 {
                        Button("Vis alle") { showAll = true }
                    }
                }
            }
            .navigationTitle(game.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Innstillinger", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Registrer trekning", systemImage: "calendar.badge.plus") { editor = .draw }
                }
            }
            .sheet(item: $editor) { mode in LotteryEntryEditor(game: game, mode: mode) }
            .sheet(isPresented: $showSuggestions) { InternationalSuggestionsView(game: game) }
            .sheet(isPresented: $showStatistics) { InternationalStatisticsView(game: game) }
            .sheet(isPresented: $showSettings) { LotterySettingsSheet() }
            .alert("\(game.title)", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(message ?? "") }
            .task {
                do { try InternationalLotteryUpdater.seed(context: context) }
                catch { message = "Kunne ikke lese grunnarkivet: \(error.localizedDescription)" }
            }
        }
        .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).colorScheme)
    }

    private func matchText(_ row: InternationalLotteryEntry) -> String {
        guard let draw = draws.first(where: { LotteryCalendar.day($0.date) == LotteryCalendar.day(row.date) }) else {
            return "Venter på trekningsresultat"
        }
        let main = Set(row.mainNumbers).intersection(draw.mainNumbers).count
        let extra = Set(row.extraNumbers).intersection(draw.extraNumbers).count
        return "\(main) hovedtall + \(extra) \(game.extraTitle.lowercased()) rette. Sjekk eventuell premie hos Norsk Tipping."
    }
    private func delete(_ entry: InternationalLotteryEntry) {
        context.delete(entry)
        do { try context.save() } catch { context.rollback(); message = error.localizedDescription }
    }
    @MainActor private func update() async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let count = try await InternationalLotteryUpdater.update(game: game, context: context) { progress = $0 }
            message = "La til \(count) nye trekninger."
        } catch is CancellationError { }
        catch { message = "Kunne ikke fullføre oppdateringen. Lagrede trekninger er tilgjengelige, og du kan prøve igjen. \(error.localizedDescription)" }
    }
}

private struct LotterySettingsSheet: View {
    @AppStorage("toleranse") private var tolerance = 3.0
    var body: some View { SettingsView(toleranse: $tolerance) }
}

enum LotteryEditorMode: String, Identifiable {
    case row, draw
    var id: String { rawValue }
}

struct LotteryEntryEditor: View {
    let game: InternationalGame
    let mode: LotteryEditorMode
    var initialRow: InternationalSuggestedRow? = nil
    var initialDate: Date? = nil
    @Query private var favoriteChanges: [LotteryFavoriteChange]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var main = Set<Int>()
    @State private var extra = Set<Int>()
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 44))]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Trekningsdato", selection: $date, displayedComponents: .date)
                    Text("Trekning \(game.schedule)").font(.caption).foregroundStyle(.secondary)
                }
                Section("Hovedtall: \(main.count) av \(game.mainCount)") {
                    numberGrid(maximum: game.mainMaximum, limit: game.mainCount, selection: $main)
                }
                Section("\(game.extraTitle): \(extra.count) av \(game.extraCount)") {
                    numberGrid(maximum: game.extraMaximum, limit: game.extraCount, selection: $extra)
                }
                if mode == .draw {
                    Text("Registrer bare bekreftede vinnertall. Samme dato kan ikke ha ulike resultater.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle(mode == .draw ? "Ny trekning" : "Ny rekke")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }.disabled(main.count != game.mainCount || extra.count != game.extraCount)
                }
            }
            .onAppear {
                date = initialDate ?? game.nextDraw(onOrAfter: .now)
                if let initialRow {
                    main = Set(initialRow.mainNumbers)
                    extra = Set(initialRow.extraNumbers)
                } else if mode == .row {
                    let profile = LotteryFavorites.selection(for: LotteryReportGame(rawValue: game.rawValue)!, records: favoriteChanges.map(\.record))
                        .effective(for: LotteryReportGame(rawValue: game.rawValue)!)
                    main = Set(profile.mainNumbers)
                    extra = Set(profile.extraNumbers)
                }
            }
        }
    }
    private func numberGrid(maximum: Int, limit: Int, selection: Binding<Set<Int>>) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...maximum, id: \.self) { number in
                Button {
                    if selection.wrappedValue.contains(number) { selection.wrappedValue.remove(number) }
                    else if selection.wrappedValue.count < limit { selection.wrappedValue.insert(number) }
                } label: {
                    Text("\(number)").font(.body.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection.wrappedValue.contains(number) ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(selection.wrappedValue.contains(number) ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tall \(number)")
                .accessibilityAddTraits(selection.wrappedValue.contains(number) ? .isSelected : [])
            }
        }
    }
    private func save() {
        errorMessage = game.validation(main: main.sorted(), extra: extra.sorted(), date: date)
        guard errorMessage == nil else { return }
        if mode == .draw && LotteryCalendar.day(date) > LotteryCalendar.day(.now) {
            errorMessage = "En trekning kan ikke registreres før trekningsdagen."
            return
        }
        do {
            let existing = try context.fetch(FetchDescriptor<InternationalLotteryEntry>()).filter {
                $0.gameID == game.rawValue && $0.isDraw == (mode == .draw) && LotteryCalendar.day($0.date) == LotteryCalendar.day(date)
            }
            if mode == .draw && !existing.isEmpty { errorMessage = "Denne trekningen er allerede registrert."; return }
            if existing.contains(where: { Set($0.mainNumbers) == main && Set($0.extraNumbers) == extra }) {
                errorMessage = "Denne rekken er allerede lagret på denne datoen."; return
            }
            context.insert(InternationalLotteryEntry(game: game, isDraw: mode == .draw, date: date, main: main.sorted(), extra: extra.sorted()))
            try context.save()
            dismiss()
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}
