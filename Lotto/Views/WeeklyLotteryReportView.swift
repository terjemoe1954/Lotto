import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct WeeklyLotteryReportView: View {
    @State private var year = LotteryReportWeek(date: .now).year
    @State private var weekNumber = LotteryReportWeek(date: .now).number
    @State private var games = Set(LotteryReportGame.allCases)
    var body: some View { WeeklyLotteryReportSource(year: $year, weekNumber: $weekNumber, games: $games) }
}

/// Only fetch own rows in this ISO week. Delivery-only changes do not rebuild this source.
private struct WeeklyLotteryReportSource: View {
    @Binding var year: Int
    @Binding var weekNumber: Int
    @Binding var games: Set<LotteryReportGame>
    @Query private var lottoRows: [Result]
    @Query private var internationalRows: [InternationalLotteryEntry]
    init(year: Binding<Int>, weekNumber: Binding<Int>, games: Binding<Set<LotteryReportGame>>) {
        _year = year; _weekNumber = weekNumber; _games = games
        let week = LotteryReportWeek(year: year.wrappedValue, number: weekNumber.wrappedValue)
        let start = week.start
        let end = LotteryReportWeek.calendar.date(byAdding: .day, value: 7, to: start)!
        _lottoRows = Query(filter: #Predicate<Result> { $0.dato >= start && $0.dato < end })
        _internationalRows = Query(filter: #Predicate<InternationalLotteryEntry> { !$0.isDraw && $0.date >= start && $0.date < end })
    }
    var body: some View {
        WeeklyLotteryReportContent(year: $year, weekNumber: $weekNumber, games: $games,
            baseRows: WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows))
    }
}

private struct WeeklyLotteryReportContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Binding var year: Int
    @Binding var weekNumber: Int
    @Binding var games: Set<LotteryReportGame>
    let baseRows: [LotteryReportRow]
    @Query private var deliveryChanges: [LotteryDeliveryChange]
    @State private var confirmDeliverAll = false
    @AppStorage("weeklyReport.hideRegistered") private var hideRegistered = false
    @State private var selected = Set<String>()
    @State private var exporting = false
    @State private var document = WeeklyWorkbookDocument(data: Data())
    @State private var preview: WeeklyPDFPreviewItem?
    @State private var message: String?

    init(year: Binding<Int>, weekNumber: Binding<Int>, games: Binding<Set<LotteryReportGame>>, baseRows: [LotteryReportRow]) {
        _year = year; _weekNumber = weekNumber; _games = games; self.baseRows = baseRows
        _deliveryChanges = Query()
    }

    private var week: LotteryReportWeek { LotteryReportWeek(year: year, number: weekNumber) }
    private var visibleRows: [LotteryReportRow] {
        LotteryDeliverySync.applying(baseRows.filter { games.contains($0.game) }, records: deliveryChanges.map(\.record))
            .filter { !hideRegistered || !$0.isRegistered }
    }

    var body: some View {
        // Build delivery state once per render, rather than repeatedly sorting the full archive.
        let eligible = LotteryDeliverySync.applying(baseRows.filter { games.contains($0.game) }, records: deliveryChanges.map(\.record))
        let visible = eligible.filter { !hideRegistered || !$0.isRegistered }
        let chosen = visible.filter { selected.contains($0.id) }
        NavigationStack {
            List {
                Section("Velg uke") {
                    Stepper("År: \(String(year))", value: $year, in: 1900...2200)
                    Stepper("Uke: \(weekNumber)", value: $weekNumber, in: 1...LotteryReportWeek.weeks(in: year))
                    Text(week.dateRange).font(.footnote).foregroundStyle(.secondary)
                    Button("Denne uken") {
                        let current = LotteryReportWeek(date: .now)
                        year = current.year
                        weekNumber = current.number
                    }
                }
                Section("Spill i rapporten") {
                    ForEach(LotteryReportGame.allCases) { game in
                        Toggle(game.title, isOn: Binding(get: { games.contains(game) }, set: { enabled in
                            if enabled { games.insert(game) } else { games.remove(game) }
                        }))
                    }
                }
                Section {
                    Toggle("Skjul registrerte rekker", isOn: $hideRegistered)
                    LabeledContent("Registrert hos Norsk Tipping", value: "\(eligible.filter(\.isRegistered).count) av \(eligible.count)")
                    Button("Lever alle", systemImage: "checkmark.square") { confirmDeliverAll = true }
                        .disabled(eligible.allSatisfy(\.isRegistered))
                    Text("Merker alle ikke-leverte rekker i valgt uke og valgte spill som levert. Dette registrerer bare i appen og sender ikke spill til Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Button("Velg alle") { selectAll() }.disabled(visible.isEmpty)
                        Spacer()
                        Button("Fjern valg") { selected.removeAll() }.disabled(chosen.isEmpty)
                    }.buttonStyle(.bordered)
                    LabeledContent("Valgte rekker", value: "\(chosen.count) av \(visible.count)")
                    Button("Papir / forhåndsvisning", systemImage: "printer") {
                        preview = WeeklyPDFPreviewItem(data: WeeklyLotteryPDF.data(rows: chosen, week: week), title: week.title)
                    }.disabled(chosen.isEmpty)
                    Button("Excel (.xlsx)", systemImage: "tablecells") {
                        document = WeeklyWorkbookDocument(data: WeeklyLotteryWorkbook.data(rows: chosen))
                        exporting = true
                    }.disabled(chosen.isEmpty)
                    Text("Rapporten bruker lagrede egne rekker. Lagre ønskede forslag først. Merk rekken som registrert etter levering; da beregnes innsats og ordinær gevinst i Spilleoversikt. Uken følger norsk ISO-uke fra mandag til søndag, med årstall.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if visible.isEmpty {
                    Section(week.title) {
                        Text(hideRegistered && !eligible.isEmpty ? "Alle rekkene er registrert. Slå av Skjul registrerte rekker for å vise dem." : "Ingen lagrede rekker for valgte spill i denne uken.")
                            .foregroundStyle(.secondary)
                    }
                }
                let systemSelections = Array(Set(eligible.flatMap(\.systems))).sorted { $0.id < $1.id }
                if !systemSelections.isEmpty {
                    Section("Lagrede systemer i valgt uke") {
                        ForEach(Array(systemSelections.enumerated()), id: \.element.id) { index, system in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("System \(index + 1) · \(LotteryReportGame(rawValue: system.gameID)?.title ?? system.gameID) · \(system.dateText)").font(.headline)
                                Text(system.numbersText).monospacedDigit()
                                let savedCount = eligible.filter { $0.systems.contains(system) }.count
                                let total = LotterySystem.rowCount(game: LotteryReportGame(rawValue: system.gameID) ?? .lotto, main: system.main.count, extra: system.extra.count)
                                Text("\(savedCount) av \(total) delrekker finnes i rapportgrunnlaget. Overlappende rekker telles bare én gang.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(LotteryReportGame.allCases) { game in
                    let rows = visible.filter { $0.game == game }
                    if !rows.isEmpty {
                        Section(game.title) {
                            ForEach(rows) { row in reportRow(row) }
                        }
                    }
                }
            }
            .navigationTitle("Ukesrapport")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .onAppear { selectAll() }
            .onChange(of: year) { _, _ in
                weekNumber = min(weekNumber, LotteryReportWeek.weeks(in: year))
                selectAll()
            }
            .onChange(of: weekNumber) { _, _ in selectAll() }
            .onChange(of: games) { _, _ in selectAll() }
            .onChange(of: hideRegistered) { _, _ in selected.formIntersection(Set(visible.map(\.id))) }
            .onChange(of: visible.map(\.id)) { _, _ in selected.formIntersection(Set(visible.map(\.id))) }
            .confirmationDialog("Merke alle som levert?", isPresented: $confirmDeliverAll, titleVisibility: .visible) {
                Button("Merk \(eligible.filter { !$0.isRegistered }.count) rekker som levert") {
                    do {
                        try LotteryDeliverySync.set(true, keys: Set(eligible.filter { !$0.isRegistered }.map(\.id)), context: context)
                        if hideRegistered { selected.removeAll() }
                    } catch { context.rollback(); message = "Kunne ikke lagre markeringene: \(error.localizedDescription)" }
                }
                Button("Avbryt", role: .cancel) { }
            } message: { Text("Gjelder \(week.title) og valgte spill. Bruk dette bare for rekker du faktisk har levert. Innsatsen tas med i Spilleoversikt, og markeringen synkroniseres via iCloud.") }
            .fileExporter(isPresented: $exporting, document: document,
                          contentType: WeeklyWorkbookDocument.contentType, defaultFilename: week.filename) { result in
                switch result {
                case .success: message = "Excel-filen ble eksportert."
                case .failure(let error): message = "Kunne ikke eksportere: \(error.localizedDescription)"
                }
            }
            .sheet(item: $preview) { item in WeeklyPDFPreview(item: item) }
            .alert("Ukesrapport", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(message ?? "") }
        }
    }
    private func reportRow(_ row: LotteryReportRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if !selected.insert(row.id).inserted { selected.remove(row.id) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(row.isRegistered ? Color.gray : Color.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(WeeklyLotteryReport.dateText(row.date)).font(.caption)
                        ForEach(row.systems) { system in
                            Label("System: " + system.numbersText, systemImage: "square.grid.3x3").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(row.mainText + (row.extraNumbers.isEmpty ? "" : "  +  " + row.extraText))
                            .font(.headline).monospacedDigit()
                    }
                    .foregroundStyle(row.isRegistered ? Color.secondary : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Velg rekke: \(row.game.title), \(row.mainText), \(row.extraText)")
            .accessibilityAddTraits(selected.contains(row.id) ? .isSelected : [])
            Button {
                do {
                    try LotteryDeliverySync.set(!row.isRegistered, keys: [row.id], context: context)
                    if hideRegistered && !row.isRegistered { selected.remove(row.id) }
                } catch { context.rollback(); message = "Kunne ikke lagre markeringen: \(error.localizedDescription)" }
            } label: {
                Label(row.isRegistered ? "Registrert hos Norsk Tipping" : "Merk som registrert",
                      systemImage: row.isRegistered ? "checkmark.square.fill" : "square")
                    .font(.subheadline).foregroundStyle(row.isRegistered ? Color.gray : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(row.isRegistered ? "Fjern registreringsmarkering" : "Huk av etter at du har registrert rekken hos Norsk Tipping")
        }
        .padding(.vertical, 6)
        .listRowBackground(row.isRegistered ? Color.secondary.opacity(0.06) : Color.clear)
    }
    private func selectAll() { selected = Set(visibleRows.map(\.id)) }
}

struct WeeklyWorkbookDocument: FileDocument {
    static var contentType: UTType { UTType(filenameExtension: "xlsx") ?? UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet", conformingTo: .spreadsheet) }
    static var readableContentTypes: [UTType] { [contentType] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let content = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = content
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct WeeklyPDFPreviewItem: Identifiable {
    let id = UUID()
    let data: Data
    let title: String
}
private struct WeeklyPDFPreview: View {
    let item: WeeklyPDFPreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var printing = false
    var body: some View {
        NavigationStack {
            WeeklyPDFView(data: item.data)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Ferdig") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("Skriv ut", systemImage: "printer") { printing = true } }
                }
                .sheet(isPresented: $printing) {
                    WeeklyPrintController(data: item.data, title: item.title) { printing = false }
                }
        }
    }
}
private struct WeeklyPDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }
}
private struct WeeklyPrintController: UIViewControllerRepresentable {
    let data: Data
    let title: String
    let completion: () -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        DispatchQueue.main.async {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = title
            controller.printInfo = info
            controller.printingItem = data
            controller.present(from: host.view.bounds, in: host.view, animated: true) { _, _, _ in completion() }
        }
        return host
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) { }
}
