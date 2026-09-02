//
//  ListMyCupons.swift
//  Lotto
//
//  Created by Terje Moe on 06/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Shows all submitted rows and lets the user delete them.
struct ListLotteryView: View {
    private enum ReportFilter: String, CaseIterable, Identifiable {
        case allPosts
        case weekOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .allPosts:
                return "Alle poster"
            case .weekOnly:
                return "Ukenummer"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Result.dato, order: .reverse) private var results: [Result]
    @State private var rowToDelete: Result? = nil
    @State private var showConfirmation = false
    @State private var reportFilter: ReportFilter = .weekOnly
    @State private var selectedWeekNr: Int?
    @State private var isPresentingPrintDialog = false
    @State private var isPresentingCSVExport = false
    @State private var isPresentingTextExport = false
    @State private var csvDocument = LotteryCSVDocument(text: "")
    @State private var textDocument = LotteryTextDocument(text: "")
    @State private var selectedResultKeys = Set<String>()
    @State private var errorMessage: String?

    private var availableWeeks: [Int] {
        Array(Set(results.map(\.weekNr))).sorted(by: >)
    }

    private var currentWeekNr: Int {
        LottoDateSupport.weekNumber(for: .now)
    }

    private var filteredResults: [Result] {
        switch reportFilter {
        case .allPosts:
            return results
        case .weekOnly:
            guard let selectedWeekNr else { return [] }
            return results.filter { $0.weekNr == selectedWeekNr }
        }
    }

    private var filterTitle: String {
        switch reportFilter {
        case .allPosts:
            return "Alle poster"
        case .weekOnly:
            guard let selectedWeekNr else { return "Uke: -" }
            return "Uke: \(selectedWeekNr)"
        }
    }

    private var exportResults: [Result] {
        let selected = filteredResults.filter { selectedResultKeys.contains(selectionKey(for: $0)) }
        return selected.isEmpty ? filteredResults : selected
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("Rapport", selection: $reportFilter) {
                    ForEach(ReportFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if reportFilter == .weekOnly {
                    Picker("Uke", selection: $selectedWeekNr) {
                        ForEach(availableWeeks, id: \.self) { week in
                            Text("Uke \(week)").tag(Optional(week))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Text("Antall Rekker: \(filteredResults.count)")
                if !selectedResultKeys.isEmpty {
                    Text("Markerte rekker: \(exportResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ZStack {
                    List(filteredResults, selection: $selectedResultKeys) { result in
                        VStack(alignment: .leading) {
                            Text(formattedDate(result.dato))
                            Text("Uke: \(result.weekNr)")
                                .font(.headline)
                            Text(formattedNumbers(for: result))
                                .monospacedDigit()
                        }
                        .tag(selectionKey(for: result))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                rowToDelete = result
                                showConfirmation.toggle()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .navigationTitle("Mine rekker")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            prepareCSVExport()
                        } label: {
                            Label("Excel (CSV)", systemImage: "tablecells")
                        }

                        Button {
                            prepareTextExport()
                        } label: {
                            Label("Pages (TXT)", systemImage: "doc.text")
                        }

                        Button {
                            isPresentingPrintDialog = true
                        } label: {
                            Label("Print", systemImage: "printer.fill")
                        }
                    } label: {
                        Label("Eksporter", systemImage: "square.and.arrow.up")
                    }
                    .disabled(filteredResults.isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Slett",
            isPresented: $showConfirmation,
            titleVisibility: .visible,
            presenting: rowToDelete ,
            actions: { item in
                Button(role: .destructive) {
                    do {
                        try delete(result: item)
                    } catch {
                        errorMessage = "Kunne ikke slette rekken: \(error.localizedDescription)"
                    }
                } label: {
                    Text("Slett")
                }
                Button(role: .cancel) {
                } label: {
                    Text("Avbryt")
                }
            },
            message: { item in
                Text("Er du sikker på at du vil slette trekningen \(formattedDate(item.dato))?")
            })
        .alert("Feil", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isPresentingPrintDialog) {
            PrintController(
                content: PrintableLotteryResultsView(
                    results: filteredResults,
                    filterTitle: filterTitle
                ),
                title: "Lotto rekker - \(filterTitle)",
                date: nil,
                completion: {
                    isPresentingPrintDialog = false
                }
            )
        }
        .fileExporter(
            isPresented: $isPresentingCSVExport,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName(extensionName: "csv")
        ) { result in
            handleExportResult(result)
        }
        .fileExporter(
            isPresented: $isPresentingTextExport,
            document: textDocument,
            contentType: .plainText,
            defaultFilename: exportFileName(extensionName: "txt")
        ) { result in
            handleExportResult(result)
        }
        .onAppear {
            ensureSelectedWeek()
        }
        .onChange(of: results) { _, _ in
            ensureSelectedWeek()
            pruneSelection()
        }
        .onChange(of: reportFilter) { _, _ in
            ensureSelectedWeek()
            pruneSelection()
        }
        .onChange(of: selectedWeekNr) { _, _ in
            pruneSelection()
        }
    }
    
    /// Formats date to the app's display format (dd.MM.yyyy).
    func formattedDate(_ date: Date) -> String {
        LottoDateSupport.formattedDate(date)
    }

    private func ensureSelectedWeek() {
        guard reportFilter == .weekOnly else { return }
        guard let firstWeek = availableWeeks.first else {
            selectedWeekNr = nil
            return
        }
        if let selectedWeekNr, availableWeeks.contains(selectedWeekNr) {
            return
        }
        selectedWeekNr = availableWeeks.contains(currentWeekNr) ? currentWeekNr : firstWeek
    }

    private func selectionKey(for result: Result) -> String {
        let numbers = [result.nr1, result.nr2, result.nr3, result.nr4, result.nr5, result.nr6, result.nr7]
            .map(String.init)
            .joined(separator: "-")
        return "\(LottoDateSupport.normalize(result.dato).timeIntervalSince1970)-\(numbers)"
    }

    private func pruneSelection() {
        let validKeys = Set(filteredResults.map(selectionKey(for:)))
        selectedResultKeys = selectedResultKeys.intersection(validKeys)
    }

    private func prepareCSVExport() {
        csvDocument = LotteryCSVDocument(text: LottoExportBuilder.csv(from: exportResults))
        isPresentingCSVExport = true
    }

    private func prepareTextExport() {
        textDocument = LotteryTextDocument(
            text: LottoExportBuilder.pagesText(from: exportResults, filterTitle: filterTitle)
        )
        isPresentingTextExport = true
    }

    private func exportFileName(extensionName: String) -> String {
        let suffix = filterTitle
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return "lotto-rekker-\(suffix).\(extensionName)"
    }

    private func handleExportResult(_ result: Swift.Result<URL, any Error>) {
        if case let .failure(error) = result {
            errorMessage = "Kunne ikke eksportere filen: \(error.localizedDescription)"
        }
    }

    private func formattedNumbers(for result: Result) -> String {
        [result.nr1, result.nr2, result.nr3, result.nr4, result.nr5, result.nr6, result.nr7]
            .map { String(format: "%02d", $0) }
            .joined(separator: " ")
    }

    private func delete(result: Result) throws {
        withAnimation {
            context.delete(result)
        }

        do {
            try context.save()
        } catch {
            context.insert(result)
            throw error
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }
}

private enum LottoExportBuilder {
    static func csv(from results: [Result]) -> String {
        let header = "Dato;Uke;Nr1;Nr2;Nr3;Nr4;Nr5;Nr6;Nr7"
        let rows = results.map { result in
            [
                LottoDateSupport.formattedDate(result.dato),
                String(result.weekNr),
                String(result.nr1),
                String(result.nr2),
                String(result.nr3),
                String(result.nr4),
                String(result.nr5),
                String(result.nr6),
                String(result.nr7)
            ].joined(separator: ";")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func pagesText(from results: [Result], filterTitle: String) -> String {
        let lines = results.enumerated().flatMap { index, result in
            [
                "Rekke \(index + 1)",
                "Dato: \(LottoDateSupport.formattedDate(result.dato))",
                "Uke: \(result.weekNr)",
                "Tall: \(formattedNumbers(for: result))",
                ""
            ]
        }

        return ([
            "Lotto rekker",
            "Filter: \(filterTitle)",
            "Antall rekker: \(results.count)",
            ""
        ] + lines).joined(separator: "\n")
    }

    private static func formattedNumbers(for result: Result) -> String {
        [result.nr1, result.nr2, result.nr3, result.nr4, result.nr5, result.nr6, result.nr7]
            .map { String(format: "%02d", $0) }
            .joined(separator: " ")
    }
}

private struct LotteryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct LotteryTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Print-friendly list of submitted rows.
private struct PrintableLotteryResultsView: View {
    let results: [Result]
    let filterTitle: String

    private let printablePageHeight: CGFloat = 730
    private let horizontalPadding: CGFloat = 16
    private let rowsPerPage: Int = 20

    private func formattedDate(_ date: Date) -> String {
        LottoDateSupport.formattedDate(date)
    }

    private var chunkedResults: [[Result]] {
        stride(from: 0, to: results.count, by: rowsPerPage).map {
            Array(results[$0..<min($0 + rowsPerPage, results.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(chunkedResults.indices, id: \.self) { index in
                let chunk = chunkedResults[index]
                VStack(alignment: .leading, spacing: 10) {
                    if index == 0 {
                        Text("Filter: \(filterTitle)")
                            .font(.headline)
                        Text("Antall rekker: \(results.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chunk) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formattedDate(result.dato))
                            Text("Uke: \(result.weekNr)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.nr1)  \(result.nr2)  \(result.nr3)  \(result.nr4)  \(result.nr5)  \(result.nr6)  \(result.nr7)")
                        }
                        .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
                .frame(height: printablePageHeight)
                .background(Color.white)
            }
        }
    }
}

#Preview {
    ListLotteryView()
}
