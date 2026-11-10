import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct WeeklyLotteryReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var lottoRows: [Result]
    @Query private var internationalRows: [InternationalLotteryEntry]
    @State private var year = LotteryReportWeek(date: .now).year
    @State private var weekNumber = LotteryReportWeek(date: .now).number
    @State private var games = Set(LotteryReportGame.allCases)
    @Query private var deliveryChanges: [LotteryDeliveryChange]
    @AppStorage("weeklyReport.hideRegistered") private var hideRegistered = false
    @State private var selected = Set<String>()
    @State private var exporting = false
    @State private var document = WeeklyWorkbookDocument(data: Data())
    @State private var preview: WeeklyPDFPreviewItem?
    @State private var message: String?

    private var week: LotteryReportWeek { LotteryReportWeek(year: year, number: weekNumber) }
    private var allRows: [LotteryReportRow] {
        LotteryDeliverySync.applying(WeeklyLotteryReport.rows(lotto: lottoRows, international: internationalRows),
            records: deliveryChanges.map(\.record))
    }
    private var eligible: [LotteryReportRow] { WeeklyLotteryReport.filtered(allRows, week: week, games: games) }
    private var visible: [LotteryReportRow] { eligible.filter { !hideRegistered || !$0.isRegistered } }
    private var chosen: [LotteryReportRow] { visible.filter { selected.contains($0.id) } }

    var body: some View {
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
                    Text("Rapporten bruker lagrede egne rekker. Lagre ønskede forslag først. Uken følger norsk ISO-uke fra mandag til søndag, med årstall.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if visible.isEmpty {
                    Section(week.title) {
                        Text(hideRegistered && !eligible.isEmpty ? "Alle rekkene er registrert. Slå av Skjul registrerte rekker for å vise dem." : "Ingen lagrede rekker for valgte spill i denne uken.")
                            .foregroundStyle(.secondary)
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
            .onChange(of: allRows.map(\.id)) { _, _ in selected.formIntersection(Set(visible.map(\.id))) }
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
    private func selectAll() { selected = Set(visible.map(\.id)) }
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
