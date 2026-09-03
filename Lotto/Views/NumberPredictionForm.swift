//
//  NumberPredictionForm.swift
//  Lotto
//
//  Created by Terje Moe on 08/02/2026.
//
import SwiftUI
import SwiftData

/// Suggests playable rows based on predictions and historical draw patterns.
struct NumberPredictionForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Result.dato, order: .forward) private var results: [Result]
    @AppStorage(LottoAppPreferences.toleranceKey) private var toleranse: Double = 3.0
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var selectedDate = Date()
    @State private var jackpots: [JackPot] = []
    @State private var predictedNumbers: [Int] = []
    @State private var suggestedRows: [SuggestedRow] = []
    @State private var suggestionMode: SuggestionMode = .balansert
    @State private var suggestionCount = 5
    @State private var stats: (
        avgGaps: [Int: Double],
        lastDates: [Int: Date],
        nextDates: [Int: Date]
    ) = ([:], [:], [:])
    @State private var isLoading = true
    @State private var isPresentingPrintDialog = false
    @State private var rowForTransfer: SuggestedRow?
    @State private var handledRowKeys = Set<String>()
    @State private var saveMessage: String?
    @State private var errorMessage: String?

    private let suggestionCountRange = 5...20

    var body: some View {
        NavigationStack {
            Form {
                Section("Velg dato") {
                    DatePicker(
                        "For denne datoen",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)

                    Text("Kun lordager brukes i forslagene. Andre datoer flyttes til neste lordag.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Forslag") {
                    Picker("Modus", selection: $suggestionMode) {
                        ForEach(SuggestionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Antall rekker: \(suggestionCount)", value: $suggestionCount, in: suggestionCountRange)

                    Text(suggestionMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Tolererer (+/-) \(Int(toleranse)) dagers avvik. Dette kan endres i settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if excludeHighestGapFromAverage {
                        Text("Gjennomsnitt er beregnet uten hoyeste mellomrom.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isLoading {
                    Section {
                        ProgressView("Laster statistikk...")
                            .frame(maxWidth: .infinity)
                    }
                }

                if let errorMessage {
                    Section("Feil") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let saveMessage {
                    Section {
                        Text(saveMessage)
                            .foregroundStyle(.green)
                    }
                }

                Section("Predikerte tall for \(selectedDateLabel)") {
                    if predictedNumbers.isEmpty {
                        Text("Ingen tall predikert for denne datoen.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(predictedNumbers.sorted(), id: \.self) { number in
                                NumberPill(number: number)
                            }
                        }
                    }
                }

                Section("Rapport") {
                    Text("\(predictedNumbers.count) av 34 tall er aktuelle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(suggestedRows.count) forslag kombinerer predikerte tall, vinnerrekker fra samme ukenummer og generell frekvens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("\(suggestedRows.count) forslag til rekker") {
                    if suggestedRows.isEmpty {
                        Text("Ingen forslag tilgjengelig for denne datoen ennå.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(suggestedRows.enumerated()), id: \.element.id) { index, row in
                            SuggestedRowCard(
                                index: index + 1,
                                row: row,
                                isDisabled: isRowUnavailable(row),
                                onSave: { saveSuggestedRow(row) },
                                onTransfer: { transferSuggestedRow(row) }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Forslag til rekker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("I dag") {
                        selectedDate = Date()
                        updatePredictions()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isPresentingPrintDialog = true
                    } label: {
                        Label("Print", systemImage: "printer.fill")
                    }
                    .disabled(suggestedRows.isEmpty)

                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                enforceSaturdaySelection()
                loadStats()
            }
            .onChange(of: selectedDate) { _, _ in
                enforceSaturdaySelection()
                updatePredictions()
            }
            .onChange(of: excludeHighestGapFromAverage) { _, _ in
                loadStats()
            }
            .onChange(of: suggestionCount) { _, _ in
                updatePredictions()
            }
            .onChange(of: suggestionMode) { _, _ in
                updatePredictions()
            }
        }
        .sheet(isPresented: $isPresentingPrintDialog) {
            PrintController(
                content: PrintableSuggestedRowsView(
                    selectedDate: selectedDate,
                    suggestionMode: suggestionMode,
                    predictedNumbers: predictedNumbers,
                    suggestedRows: suggestedRows
                ),
                title: "Lotto forslag - \(suggestionMode.title)",
                date: selectedDate,
                completion: {
                    isPresentingPrintDialog = false
                }
            )
        }
        .sheet(item: $rowForTransfer) { row in
            MyLotteryView(
                initialDrawDate: selectedDate,
                initialNumbers: row.numbers
            )
        }
    }

    private var selectedDateLabel: String {
        selectedDate.formatted(Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.twoDigits).year())
    }

    /// Loads stats from all draws and prepares predicted numbers.
    private func loadStats() {
        Task { @MainActor in
            do {
                let fetchedJackpots = try context.fetch(FetchDescriptor<JackPot>())
                jackpots = fetchedJackpots
                let (avgGaps, lastDates) = LottoStatistics.statsPerNumber(
                    from: fetchedJackpots,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage
                )
                let nextDates = LottoStatistics.nextDatesPerNumber(avgGaps: avgGaps, lastDates: lastDates)
                stats = (avgGaps, lastDates, nextDates)
                errorMessage = nil
                saveMessage = nil
                isLoading = false
                updatePredictions()
            } catch {
                errorMessage = "Kunne ikke laste statistikk: \(error.localizedDescription)"
                suggestedRows = []
                isLoading = false
            }
        }
    }

    /// Updates the predicted numbers and row suggestions for the selected date.
    private func updatePredictions() {
        let calendar = Calendar.current
        let toleranceDays = toleranse

        predictedNumbers = stats.nextDates.filter { _, predictedDate in
            if let daysDiff = calendar.dateComponents([.day], from: predictedDate, to: selectedDate).day {
                return abs(Double(daysDiff)) <= toleranceDays
            }
            return false
        }
        .keys
        .sorted()

        suggestedRows = LottoSuggestionEngine.makeSuggestedRows(
            for: selectedDate,
            predictedNumbers: predictedNumbers,
            jackpots: jackpots,
            mode: suggestionMode,
            rowCount: suggestionCount
        )
    }

    private func saveSuggestedRow(_ row: SuggestedRow) {
        guard row.numbers.count == 7 else {
            errorMessage = "Forslaget inneholder ikke 7 gyldige tall."
            return
        }

        guard !isRowUnavailable(row) else {
            errorMessage = "Denne rekken er allerede brukt for valgt dato."
            return
        }

        let result = Result(
            dato: LottoDateSupport.normalize(selectedDate),
            nr1: row.numbers[0],
            nr2: row.numbers[1],
            nr3: row.numbers[2],
            nr4: row.numbers[3],
            nr5: row.numbers[4],
            nr6: row.numbers[5],
            nr7: row.numbers[6],
            weekNr: LottoDateSupport.weekNumber(for: selectedDate)
        )

        do {
            context.insert(result)
            try context.save()
            handledRowKeys.insert(rowKey(for: row, drawDate: selectedDate))
            saveMessage = "Rekke \(row.numbers.map(String.init).joined(separator: " ")) er lagret."
            errorMessage = nil
        } catch {
            context.delete(result)
            errorMessage = "Kunne ikke lagre rekken: \(error.localizedDescription)"
        }
    }

    private func transferSuggestedRow(_ row: SuggestedRow) {
        guard !isRowUnavailable(row) else {
            errorMessage = "Denne rekken er allerede brukt for valgt dato."
            return
        }

        handledRowKeys.insert(rowKey(for: row, drawDate: selectedDate))
        rowForTransfer = row
        errorMessage = nil
    }

    private func isRowUnavailable(_ row: SuggestedRow) -> Bool {
        let key = rowKey(for: row, drawDate: selectedDate)
        if handledRowKeys.contains(key) {
            return true
        }

        return LottoRules.duplicateResultValidationMessage(
            numbers: row.numbers,
            drawDate: selectedDate,
            existingResults: results
        ) != nil
    }

    private func rowKey(for row: SuggestedRow, drawDate: Date) -> String {
        let normalizedDate = LottoDateSupport.normalize(drawDate).timeIntervalSince1970
        let numbers = LottoRules.normalizedResultNumbers(row.numbers).map(String.init).joined(separator: "-")
        return "\(normalizedDate)-\(numbers)"
    }

    private func enforceSaturdaySelection() {
        let saturday = LottoDateSupport.nextSaturday(onOrAfter: selectedDate)
        if saturday != LottoDateSupport.normalize(selectedDate) {
            selectedDate = saturday
        }
    }
}

private struct SuggestedRowCard: View {
    let index: Int
    let row: SuggestedRow
    let isDisabled: Bool
    let onSave: () -> Void
    let onTransfer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rekke \(index)")
                        .font(.headline)
                    Text(row.sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack {
                    Button("Levere") {
                        onTransfer()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isDisabled)

                    Button("Lagre") {
                        onSave()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isDisabled)
                }
            }

            Text(row.numbers.map { String(format: "%02d", $0) }.joined(separator: "  "))
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            if !row.predictedMatches.isEmpty {
                MatchLine(title: "Predikert", numbers: row.predictedMatches)
            }

            if !row.sameWeekMatches.isEmpty {
                MatchLine(title: "Samme uke", numbers: row.sameWeekMatches)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MatchLine: View {
    let title: String
    let numbers: [Int]

    var body: some View {
        Text("\(title): \(numbers.map(String.init).joined(separator: ", "))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Print-friendly report for suggested rows.
private struct PrintableSuggestedRowsView: View {
    let selectedDate: Date
    let suggestionMode: SuggestionMode
    let predictedNumbers: [Int]
    let suggestedRows: [SuggestedRow]

    private let printablePageHeight: CGFloat = 730
    private let firstPageRows = 5
    private let followingPageRows = 6

    private var chunkedRows: [[SuggestedRow]] {
        guard !suggestedRows.isEmpty else { return [] }

        var chunks: [[SuggestedRow]] = []
        var startIndex = 0
        var pageIndex = 0

        while startIndex < suggestedRows.count {
            let pageSize = pageIndex == 0 ? firstPageRows : followingPageRows
            let endIndex = min(startIndex + pageSize, suggestedRows.count)
            chunks.append(Array(suggestedRows[startIndex..<endIndex]))
            startIndex = endIndex
            pageIndex += 1
        }

        return chunks
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(chunkedRows.indices, id: \.self) { index in
                let chunk = chunkedRows[index]
                VStack(alignment: .leading, spacing: 12) {
                    if index == 0 {
                        Text("Dato: \(LottoDateSupport.formattedDate(selectedDate))")
                            .font(.headline)
                        Text("Modus: \(suggestionMode.title)")
                            .font(.subheadline)
                        Text("Predikerte tall: \(formattedNumbers(predictedNumbers))")
                            .font(.subheadline)
                        Divider()
                    }

                    ForEach(Array(chunk.enumerated()), id: \.element.id) { rowIndex, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rekke \(displayRowNumber(pageIndex: index, rowIndex: rowIndex)) - \(row.sourceLabel)")
                                .font(.headline)
                            Text(formattedNumbers(row.numbers))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                            Text("Predikert: \(formattedNumbers(row.predictedMatches))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Samme uke: \(formattedNumbers(row.sameWeekMatches))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 8)
                    }
                }
                .frame(height: printablePageHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
        }
    }

    private func formattedNumbers(_ numbers: [Int]) -> String {
        if numbers.isEmpty {
            return "-"
        }
        return numbers.map { String(format: "%02d", $0) }.joined(separator: "  ")
    }

    private func displayRowNumber(pageIndex: Int, rowIndex: Int) -> Int {
        let rowsBeforePage: Int
        if pageIndex == 0 {
            rowsBeforePage = 0
        } else {
            rowsBeforePage = firstPageRows + ((pageIndex - 1) * followingPageRows)
        }
        return rowsBeforePage + rowIndex + 1
    }
}

// MARK: - Supporting views
/// Simple pill-style view for a number.
struct NumberPill: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.title2.bold())
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Circle()
                    .fill(.blue.opacity(0.2))
                    .overlay(
                        Circle()
                            .stroke(.blue, lineWidth: 2)
                    )
            )
            .foregroundStyle(.blue)
    }
}

#Preview {
    NumberPredictionForm()
        .modelContainer(for: JackPot.self)
}
