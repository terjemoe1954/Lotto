import SwiftUI
import SwiftData

struct LotteryLedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LotteryLedgerEntry.date, order: .reverse) private var entries: [LotteryLedgerEntry]
    @Query private var deliveryChanges: [LotteryDeliveryChange]
    @State private var prizeCache = LotteryPrizeCache.shared
    private var delivered: [LotteryReportRow] { AutomaticLotteryLedger.deliveredRows(deliveryChanges.map(\.record)) }
    private var automatic: [AutomaticLotteryLedgerItem] { AutomaticLotteryLedger.items(rows: delivered, tables: prizeCache.tables) }
    private var allRecords: [LotteryLedgerRecord] { entries.map(\.record) + automatic.map(\.record) }
    private var monthlyAutomatic: [AutomaticLotteryLedgerItem] {
        let interval = LotteryCalendar.calendar.dateInterval(of: .month, for: month)!
        return automatic.filter { $0.row.date >= interval.start && $0.row.date < interval.end }
    }
    @AppStorage("ledger.monthlyBudget") private var budget = ""
    @State private var month = Date()
    @State private var editing: LotteryLedgerRecord?
    @State private var deleting: LotteryLedgerEntry?
    @State private var error: String?
    private var monthly: [LotteryLedgerEntry] {
        let interval = LotteryCalendar.calendar.dateInterval(of: .month, for: month)!
        return entries.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Rekker du merker som Levert / registrert hos Norsk Tipping regnes automatisk med. Tar du bort haken, tas rekken ut av regnskapet. Innsatsen føres på trekningsdatoen.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Ny manuell post", systemImage: "plus.circle") {
                        editing = LotteryLedgerRecord(id: UUID().uuidString, gameID: "lotto", date: .now, stakeOre: 0, prizeOre: 0, note: "")
                    }
                    Text("Standardpris per rekke: Lotto 5 kr, Vikinglotto 8 kr, Eurojackpot 25 kr. Én unik rekke per spill og trekningsdato telles én gang. Automatisk beregning gjelder fra 2023. Ekstra kjøp av samme rekke og tilleggsspill føres manuelt.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { Task { await prizeCache.refresh(rows: delivered) } } label: {
                        HStack {
                            if prizeCache.updating { ProgressView() }
                            Text(prizeCache.updating ? "Henter premier …" : "Oppdater premier")
                        }
                    }.disabled(prizeCache.updating || delivered.isEmpty)
                    if let error = prizeCache.error { Text(error).font(.footnote).foregroundStyle(.orange) }
                    Text("Gevinst bruker ferdigbehandlede vinnertall og premiebeløpet per vinnerrekke fra Norsk Tipping. Supertrekning, nasjonale tilleggstrekninger og Joker må føres manuelt. Unngå å føre de samme beløpene både manuelt og automatisk.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Valgt måned") {
                    DatePicker("Dato i måneden", selection: $month, displayedComponents: .date)
                    summary(monthly.map(\.record) + monthlyAutomatic.map(\.record), pending: monthlyAutomatic.filter { $0.prizeOre == nil }.count)
                }
                Section("Totalt registrert") { summary(allRecords, pending: automatic.filter { $0.prizeOre == nil }.count) }
                Section("Spillevett") {
                    TextField("Egen månedsgrense i kroner (valgfritt)", text: $budget).keyboardType(.decimalPad)
                    if !budget.isEmpty && (LotteryLedger.ore(budget) ?? 0) == 0 {
                        Text("Skriv et beløp større enn null, eller la feltet stå tomt.").foregroundStyle(.orange)
                    }
                    let now = LotteryCalendar.calendar.dateInterval(of: .month, for: .now)!
                    let stake = LotteryLedger.totals(allRecords.filter { $0.date >= now.start && $0.date < now.end }).stake
                    if LotteryLedger.shouldPause(stake: stake, budget: LotteryLedger.ore(budget)) {
                        Label("Du har nådd månedsgrensen din. Vi anbefaler å ta en pause fra spill.", systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    }
                    Text("Grensen gjelder samlet innsats denne måneden i alle tre spill, før gevinster trekkes fra. Den er en påminnelse og stopper ikke spill hos Norsk Tipping. Grensen lagres på denne enheten.").font(.footnote).foregroundStyle(.secondary)
                    Text("Ta gjerne en pause. Spill bare for penger du har råd til å tape, og ikke spill for å vinne tilbake tap.").font(.footnote)
                    Link("Spillevett hos Norsk Tipping", destination: URL(string: "https://www.norsk-tipping.no/spillevett")!)
                }
                Section("Automatisk i valgt måned") {
                    if monthlyAutomatic.isEmpty { Text("Ingen leverte rekker denne måneden.").foregroundStyle(.secondary) }
                    ForEach(monthlyAutomatic) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(item.row.game.title) · \(LotteryCalendar.text(item.row.date))")
                            Text(item.row.mainText + (item.row.extraNumbers.isEmpty ? "" : " + " + item.row.extraText)).font(.caption).monospacedDigit()
                            Text("Innsats: \(LotteryLedger.money(item.record.stakeOre))").font(.subheadline)
                            if let prize = item.prizeOre {
                                Text("Beregnet gevinst: \(LotteryLedger.money(prize))").font(.subheadline).foregroundStyle(prize > 0 ? Color.green : Color.secondary)
                            } else {
                                Text("Gevinst: venter på trekning / premietabell").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Button("Fjern Levert-markering") {
                                do { try LotteryDeliverySync.set(false, keys: [item.row.id], context: context) }
                                catch { context.rollback(); self.error = error.localizedDescription }
                            }.font(.caption).buttonStyle(.borderless)
                        }
                    }
                    Text("Fjern Levert-markeringen for å korrigere automatisk innsats. Sletting av en lagret rekke fjerner ikke historikken over det du har levert.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Manuelle poster i valgt måned") {
                    if monthly.isEmpty { Text("Ingen registrerte poster.").foregroundStyle(.secondary) }
                    ForEach(monthly) { entry in
                        Button { editing = entry.record } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(LotteryReportGame(rawValue: entry.gameID)?.title ?? entry.gameID) · \(LotteryCalendar.text(entry.date))")
                                Text("Innsats: \(LotteryLedger.money(entry.stakeOre)) · Gevinst: \(LotteryLedger.money(entry.prizeOre))").font(.subheadline)
                                if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) }
                            }.foregroundStyle(.primary)
                        }
                        .swipeActions { Button("Slett", role: .destructive) { deleting = entry } }
                    }
                }
                Section { Text("Manuelle poster og leveringsmarkeringer inngår i full sikkerhetskopi og synkroniseres med iCloud. Offentlige premietabeller lagres lokalt og hentes på nytt på andre enheter. Kontroller beløpene mot spillhistorikken hos Norsk Tipping.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Spilleoversikt")
            .task(id: delivered.map(\.id)) { await prizeCache.refresh(rows: delivered) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .sheet(item: $editing) { record in LotteryLedgerEditor(record: record, existing: entries.first { $0.entryID == record.id }) }
            .confirmationDialog("Slette denne posten?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Slett post", role: .destructive) {
                    guard let deleting else { return }
                    context.delete(deleting)
                    do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription }
                    self.deleting = nil
                }
            }
            .alert("Kunne ikke lagre", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(error ?? "") }
        }
    }
    private func summary(_ records: [LotteryLedgerRecord], pending: Int) -> some View {
        let totals = LotteryLedger.totals(records)
        return Group {
            LabeledContent("Innsats", value: LotteryLedger.money(totals.stake))
            LabeledContent("Registrert / beregnet gevinst", value: LotteryLedger.money(totals.prize))
            LabeledContent(pending == 0 ? "Netto (gevinst − innsats)" : "Foreløpig netto", value: LotteryLedger.money(totals.prize - totals.stake))
            if pending > 0 { Text("Gevinst er ikke avklart for \(pending) rekker. Summene er foreløpige.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

extension LotteryLedgerRecord: Identifiable { }

private struct LotteryLedgerEditor: View {
    let record: LotteryLedgerRecord
    let existing: LotteryLedgerEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var game = LotteryReportGame.lotto
    @State private var date = Date()
    @State private var stake = ""
    @State private var prize = ""
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Spill", selection: $game) { ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0) } }
                DatePicker("Dato", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Innsats i kroner", text: $stake).keyboardType(.decimalPad)
                TextField("Gevinst i kroner", text: $prize).keyboardType(.decimalPad)
                TextField("Merknad (valgfritt)", text: $note)
                Text("Bruk 0 dersom posten bare gjelder innsats eller gevinst. Registrer hvert beløp én gang.").font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(existing == nil ? "Ny post" : "Rediger post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lagre", action: save) }
            }
            .onAppear {
                game = LotteryReportGame(rawValue: record.gameID) ?? .lotto; date = record.date
                stake = LotteryLedger.input(record.stakeOre); prize = LotteryLedger.input(record.prizeOre); note = record.note
            }
        }
    }
    private func save() {
        guard let stakeOre = LotteryLedger.ore(stake), let prizeOre = LotteryLedger.ore(prize), stakeOre > 0 || prizeOre > 0 else {
            error = "Skriv gyldige beløp med høyst to desimaler. Minst ett beløp må være større enn null."; return
        }
        let value = LotteryLedgerRecord(id: record.id, gameID: game.rawValue, date: date, stakeOre: stakeOre, prizeOre: prizeOre, note: note)
        guard value.isValid else { error = "Kontroller beløp og dato."; return }
        if let existing { existing.apply(value) } else { context.insert(LotteryLedgerEntry(record: value)) }
        do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
