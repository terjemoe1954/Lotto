//
//  ListMyCupons.swift
//  Lotto
//
//  Created by Terje Moe on 06/02/2026.
//

import SwiftUI
import SwiftData
import UIKit
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
    @Environment(\.openURL) private var openURL
    @Query(sort: \Result.dato, order: .reverse) private var results: [Result]
    @AppStorage("transferredResultKeys") private var transferredResultKeysRaw = ""
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
    @State private var statusMessage: String?

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

    private var transferredResultKeys: Set<String> {
        Set(transferredResultKeysRaw.split(separator: "\n").map(String.init))
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
                            HStack {
                                Text(formattedDate(result.dato))
                                Spacer()
                                if isTransferred(result) {
                                    Label("Overført", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
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
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                copyToClipboard([result])
                            } label: {
                                Label("Kopier", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)

                            Button {
                                toggleTransferred(result)
                            } label: {
                                Label(
                                    isTransferred(result) ? "Ikke overført" : "Overført",
                                    systemImage: isTransferred(result) ? "circle" : "checkmark.circle"
                                )
                            }
                            .tint(isTransferred(result) ? .gray : .green)
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
                            copyToClipboard(exportResults)
                            openNorskTipping()
                        } label: {
                            Label("Kopier og åpne Norsk Tipping", systemImage: "arrow.up.forward.app")
                        }

                        Button {
                            copyToClipboard(exportResults)
                        } label: {
                            Label("Kopier rekker", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button {
                            setTransferred(exportResults, transferred: true)
                        } label: {
                            Label("Merk som overført", systemImage: "checkmark.circle")
                        }

                        Button {
                            setTransferred(exportResults, transferred: false)
                        } label: {
                            Label("Fjern overført-markering", systemImage: "circle")
                        }
                    } label: {
                        Label("Lever", systemImage: "ticket")
                    }
                    .disabled(filteredResults.isEmpty)

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
        .alert("Mine rekker", isPresented: statusAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage ?? "")
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
        setTransferred([result], transferred: false)
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

    private func copyToClipboard(_ rows: [Result]) {
        guard !rows.isEmpty else { return }
        UIPasteboard.general.string = LottoDeliveryBuilder.clipboardText(from: rows)
        statusMessage = rows.count == 1
            ? "Rekken er kopiert."
            : "\(rows.count) rekker er kopiert, én rekke per linje."
    }

    private func openNorskTipping() {
        guard let url = URL(string: "https://www.norsk-tipping.no/lotteri/lotto/kupong?prefilled=false&weeks=1") else {
            errorMessage = "Kunne ikke åpne Norsk Tipping."
            return
        }
        openURL(url)
    }

    private func isTransferred(_ result: Result) -> Bool {
        transferredResultKeys.contains(selectionKey(for: result))
    }

    private func toggleTransferred(_ result: Result) {
        setTransferred([result], transferred: !isTransferred(result))
    }

    private func setTransferred(_ rows: [Result], transferred: Bool) {
        var keys = transferredResultKeys
        let rowKeys = rows.map(selectionKey(for:))
        if transferred {
            keys.formUnion(rowKeys)
        } else {
            keys.subtract(rowKeys)
        }
        transferredResultKeysRaw = keys.sorted().joined(separator: "\n")
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

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { isPresented in
                if !isPresented {
                    statusMessage = nil
                }
            }
        )
    }
}

enum LottoDeliveryBuilder {
    static func clipboardText(from results: [Result]) -> String {
        results
            .map { result in
                [result.nr1, result.nr2, result.nr3, result.nr4, result.nr5, result.nr6, result.nr7]
                    .map { String(format: "%02d", $0) }
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
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
    private let rowsPerPage = LottoPrintLayout.rowsPerPage

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
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(filterTitle)
                        Spacer()
                        Text("\(results.count) rekker")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.bottom, 8)

                    HStack(spacing: 8) {
                        Text("Dato")
                            .frame(width: 72, alignment: .leading)
                        Text("Uke")
                            .frame(width: 34, alignment: .leading)
                        Text("Tall")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                    Divider()

                    ForEach(chunk) { result in
                        HStack(spacing: 8) {
                            Text(formattedDate(result.dato))
                                .frame(width: 72, alignment: .leading)
                            Text(String(result.weekNr))
                                .frame(width: 34, alignment: .leading)
                            Text(printableNumbers(for: result))
                                .monospacedDigit()
                        }
                        .font(.system(size: 10))
                        .frame(height: 24)

                        Divider()
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
                .frame(height: printablePageHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
        }
    }

    private func printableNumbers(for result: Result) -> String {
        [result.nr1, result.nr2, result.nr3, result.nr4, result.nr5, result.nr6, result.nr7]
            .map { String(format: "%02d", $0) }
            .joined(separator: "  ")
    }
}

enum LottoPrintLayout {
    static let rowsPerPage = 24

    static func pageCount(for rowCount: Int) -> Int {
        guard rowCount > 0 else { return 1 }
        return Int(ceil(Double(rowCount) / Double(rowsPerPage)))
    }
}

#Preview {
    ListLotteryView()
}
