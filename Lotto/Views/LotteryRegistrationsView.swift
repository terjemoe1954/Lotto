import SwiftUI
import SwiftData

struct LotteryRegistrationsView: View {
    @State private var month = Date()
    var body: some View { LotteryRegistrationsSource(month: $month) }
}

private struct LotteryRegistrationsSource: View {
    @Binding var month: Date
    @Query private var lotto: [Result]
    @Query private var international: [InternationalLotteryEntry]
    @Query private var manual: [LotteryLedgerEntry]
    init(month: Binding<Date>) {
        _month = month
        let interval = LotteryCalendar.calendar.dateInterval(of: .month, for: month.wrappedValue)!
        let start = interval.start, end = interval.end
        _lotto = Query(filter: #Predicate<Result> { $0.dato >= start && $0.dato < end })
        _international = Query(filter: #Predicate<InternationalLotteryEntry> { !$0.isDraw && $0.date >= start && $0.date < end })
        _manual = Query(filter: #Predicate<LotteryLedgerEntry> { $0.date >= start && $0.date < end }, sort: \.date, order: .reverse)
    }
    var body: some View {
        LotteryRegistrationsContent(month: $month, ownRows: WeeklyLotteryReport.rows(lotto: lotto, international: international), manual: manual)
    }
}

private enum RegistrationDeletion: Identifiable {
    case row(LotteryReportRow), system(LotterySystemSelection), manual(LotteryLedgerEntry)
    var id: String {
        switch self { case .row(let r): return r.id; case .system(let s): return s.id; case .manual(let m): return m.entryID }
    }
}
private struct LotteryRegistrationsContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Binding var month: Date
    let ownRows: [LotteryReportRow]
    let manual: [LotteryLedgerEntry]
    @Query private var changes: [LotteryDeliveryChange]
    @State private var gameID = "all"
    @State private var limit = 50
    @State private var editingRow: LotteryReportRow?
    @State private var editingSystem: LotterySystemSelection?
    @State private var editingManual: LotteryLedgerRecord?
    @State private var deletion: RegistrationDeletion?
    @State private var error: String?

    var body: some View {
        let interval = LotteryCalendar.calendar.dateInterval(of: .month, for: month)!
        let events = changes.map(\.record)
        let historical = AutomaticLotteryLedger.deliveredRows(events).filter { $0.date >= interval.start && $0.date < interval.end }
        let rows = LotteryDeliverySync.applying(WeeklyLotteryReport.normalized(ownRows + historical), records: events)
            .filter { gameID == "all" || $0.game.rawValue == gameID }.sorted { $0.date > $1.date }
        let systems = Array(Set(rows.flatMap(\.systems))).sorted { $0.id < $1.id }
        let manualRows = manual.filter { gameID == "all" || $0.gameID == gameID }
        NavigationStack {
            List {
                Section("Velg registreringer") {
                    DatePicker("Dato i måneden", selection: $month, displayedComponents: .date)
                    Picker("Spill", selection: $gameID) {
                        Text("Alle spill").tag("all")
                        ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("Her kan du korrigere egne rekker, systemer og manuelle beløp. Endringer synkroniseres via iCloud. Ta gjerne en full sikkerhetskopi først. Offisielle trekninger endres ikke.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !systems.isEmpty {
                    Section("Systemspill i valgt måned") {
                        ForEach(systems) { system in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(LotteryReportGame(rawValue: system.gameID)?.title ?? system.gameID) · \(system.dateText)").font(.headline)
                                Text(system.numbersText).monospacedDigit()
                                HStack {
                                    Button("Endre system", systemImage: "pencil") { editingSystem = system }
                                    Spacer()
                                    Button("Slett system", role: .destructive) { deletion = .system(system) }
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Egne rekker og leveringer (\(rows.count))") {
                    if rows.isEmpty { Text("Ingen registreringer for valgt måned og spill.").foregroundStyle(.secondary) }
                    ForEach(Array(rows.prefix(limit))) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(row.game.title) · \(WeeklyLotteryReport.dateText(row.date))").font(.headline)
                            Text(row.mainText + (row.extraNumbers.isEmpty ? "" : " + " + row.extraText)).monospacedDigit()
                            if row.isRegistered { Label("Levert", systemImage: "checkmark.square.fill").font(.caption) }
                            if !row.systems.isEmpty { Text("Del av \(row.systems.count) system(er)").font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("Endre rekke", systemImage: "pencil") { editingRow = row }
                                Spacer()
                                Button("Slett", role: .destructive) { deletion = .row(row) }
                            }.buttonStyle(.borderless)
                        }
                    }
                    if rows.count > limit { Button("Vis 50 flere") { limit += 50 } }
                }
                Section("Manuelle poster (\(manualRows.count))") {
                    if manualRows.isEmpty { Text("Ingen manuelle poster denne måneden.").foregroundStyle(.secondary) }
                    ForEach(manualRows) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(LotteryReportGame(rawValue: entry.gameID)?.title ?? entry.gameID) · \(WeeklyLotteryReport.dateText(entry.date))")
                            Text("Innsats: \(LotteryLedger.money(entry.stakeOre)) · Gevinst: \(LotteryLedger.money(entry.prizeOre))").font(.subheadline)
                            if !entry.note.isEmpty { Text(entry.note).font(.caption) }
                            HStack {
                                Button("Endre post", systemImage: "pencil") { editingManual = entry.record }
                                Spacer()
                                Button("Slett post", role: .destructive) { deletion = .manual(entry) }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Mine registreringer")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .onChange(of: month) { _, _ in limit = 50 }
            .onChange(of: gameID) { _, _ in limit = 50 }
            .sheet(item: $editingRow) { LotteryRegistrationEditor(original: $0) }
            .sheet(item: $editingSystem) { LotterySavedSystemEditor(original: $0) }
            .sheet(item: $editingManual) { record in LotteryLedgerEditor(record: record, existing: manual.first { $0.entryID == record.id }) }
            .confirmationDialog("Slette registreringen?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                if case .some(.manual) = deletion {
                    Button("Slett manuell post", role: .destructive) { remove(removeDelivery: true) }
                } else {
                    Button("Slett og fjern Levert", role: .destructive) { remove(removeDelivery: true) }
                    Button("Slett bare lagrede rekker", role: .destructive) { remove(removeDelivery: false) }
                }
                Button("Avbryt", role: .cancel) { deletion = nil }
            } message: {
                Text("Sletting gjelder også de andre enhetene via iCloud. «Fjern Levert» tar bort beregnet innsats og gevinst. «Bare lagrede rekker» beholder leveringshistorikken. Ved sletting av system beholdes delrekker som tilhører andre systemer; øvrige delrekker fjernes, også om de opprinnelig ble lagret enkeltvis. Ingen spill hos Norsk Tipping endres.")
            }
            .alert("Kunne ikke lagre", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(error ?? "") }
        }
    }
    private func remove(removeDelivery: Bool) {
        guard let deletion else { return }
        do {
            switch deletion {
            case .row(let row): try LotteryRegistrationStore.delete([row], removeDelivery: removeDelivery, context: context)
            case .system(let system): try LotteryRegistrationStore.deleteSystem(system, removeDelivery: removeDelivery, context: context)
            case .manual(let entry): context.delete(entry); try context.save()
            }
        } catch { context.rollback(); self.error = error.localizedDescription }
        self.deletion = nil
    }
}

private enum RegistrationNumbers {
    static func parse(_ text: String) -> [Int]? {
        let pieces = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;–-"))).filter { !$0.isEmpty }
        let values = pieces.compactMap(Int.init)
        return values.count == pieces.count ? values.sorted() : nil
    }
    static func text(_ numbers: [Int]) -> String { numbers.map(String.init).joined(separator: " ") }
}

private struct LotteryRegistrationEditor: View {
    let original: LotteryReportRow
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var game = LotteryReportGame.lotto
    @State private var date = Date()
    @State private var main = ""
    @State private var extra = ""
    @State private var error: String?
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Spill", selection: $game) { ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0) } }
                DatePicker("Trekningsdato", selection: $date, displayedComponents: .date)
                TextField("Hovedtall med mellomrom", text: $main).keyboardType(.numbersAndPunctuation)
                if game != .lotto { TextField("Tilleggstall med mellomrom", text: $extra).keyboardType(.numbersAndPunctuation) }
                Text("En korreksjon erstatter den gamle rekken. Er den levert, flyttes Levert til den korrigerte rekken, slik at innsatsen ikke telles dobbelt. Endret delrekke frikobles fra sitt system. Bruk Endre system for å endre hele systemet.").font(.footnote)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Endre rekke")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lagre") { confirm = true } }
            }
            .onAppear { game = original.game; date = original.date; main = RegistrationNumbers.text(original.mainNumbers); extra = RegistrationNumbers.text(original.extraNumbers) }
            .confirmationDialog("Lagre korrigert rekke?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Lagre korreksjon") { save() }
                Button("Avbryt", role: .cancel) { }
            } message: { Text("Endringen gjelder også andre enheter via iCloud. Kontroller mot det du faktisk har levert hos Norsk Tipping.") }
        }
    }
    private func save() {
        guard let numbers = RegistrationNumbers.parse(main), let additional = RegistrationNumbers.parse(extra) else { error = "Bruk hele tall med mellomrom."; return }
        let row = LotteryReportRow(game: game, date: LotteryCalendar.day(date), mainNumbers: numbers, extraNumbers: game == .lotto ? [] : additional)
        do { try LotteryRegistrationStore.replace(original, with: row, context: context); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

private struct LotterySavedSystemEditor: View {
    let original: LotterySystemSelection
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var main = ""
    @State private var extra = ""
    @State private var date = Date()
    @State private var removeOldDelivery = false
    @State private var confirm = false
    @State private var error: String?
    private var game: LotteryReportGame { LotteryReportGame(rawValue: original.gameID) ?? .lotto }
    var body: some View {
        NavigationStack {
            Form {
                Text(game.title).font(.headline)
                DatePicker("Trekningsdato", selection: $date, displayedComponents: .date)
                TextField("Systemets hovedtall", text: $main).keyboardType(.numbersAndPunctuation)
                if game != .lotto { TextField("Systemets tilleggstall", text: $extra).keyboardType(.numbersAndPunctuation) }
                Toggle("Fjern Levert fra gamle delrekker", isOn: $removeOldDelivery)
                Text("Det gamle systemet erstattes. Delrekker som tilhører andre systemer beholdes. Øvrige gamle delrekker fjernes, også om de opprinnelig ble lagret enkeltvis. Nye delrekker får ingen ny Levert-markering. Gamle leveringer beholdes i Spilleoversikt med mindre du velger å fjerne dem.").font(.footnote)
                if let numbers = RegistrationNumbers.parse(main), let additional = RegistrationNumbers.parse(extra),
                   LotterySystem.validation(game: game, main: numbers, extra: additional, date: date) == nil {
                    LotteryOddsSummary(game: game, ordinaryRows: LotterySystem.rowCount(game: game, main: numbers.count, extra: additional.count))
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Endre system")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lagre") { confirm = true } }
            }
            .onAppear { main = RegistrationNumbers.text(original.main); extra = RegistrationNumbers.text(original.extra); date = LotteryCalendar.date(original.dateText) ?? .now }
            .confirmationDialog("Erstatte systemet?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Lagre endret system") {
                    guard let numbers = RegistrationNumbers.parse(main), let additional = RegistrationNumbers.parse(extra) else { error = "Bruk hele tall med mellomrom."; return }
                    do {
                        try LotteryRegistrationStore.replaceSystem(original, game: game, main: numbers, extra: additional, date: date, removeOldDelivery: removeOldDelivery, context: context)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                Button("Avbryt", role: .cancel) { }
            } message: { Text("Endringen synkroniseres til de andre enhetene. Ingen innlevering hos Norsk Tipping endres.") }
        }
    }
}
