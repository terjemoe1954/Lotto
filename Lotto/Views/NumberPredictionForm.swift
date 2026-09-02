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
    @AppStorage(LottoAppPreferences.toleranceKey) private var toleranse: Double = 3.0
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var selectedDate = Date()
    @State private var jackpots: [JackPot] = []
    @State private var predictedNumbers: [Int] = []
    @State private var suggestedRows: [SuggestedRow] = []
    @State private var suggestionMode: SuggestionMode = .balansert
    @State private var suggestionCount = 20
    @State private var stats: (
        avgGaps: [Int: Double],
        lastDates: [Int: Date],
        nextDates: [Int: Date]
    ) = ([:], [:], [:])
    @State private var isLoading = true
    @State private var isPresentingPrintDialog = false
    @State private var saveMessage: String?
    @State private var errorMessage: String?

    private let suggestionCountRange = 5...40

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
                                onSave: { saveSuggestedRow(row) }
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
            .onAppear(perform: loadStats)
            .onChange(of: selectedDate) { _, _ in
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
            saveMessage = "Rekke \(row.numbers.map(String.init).joined(separator: " ")) er lagret."
            errorMessage = nil
        } catch {
            context.delete(result)
            errorMessage = "Kunne ikke lagre rekken: \(error.localizedDescription)"
        }
    }
}

private struct SuggestedRowCard: View {
    let index: Int
    let row: SuggestedRow
    let onSave: () -> Void

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
                Button("Lagre") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
    private let rowsPerPage: Int = 8

    private var chunkedRows: [[SuggestedRow]] {
        stride(from: 0, to: suggestedRows.count, by: rowsPerPage).map {
            Array(suggestedRows[$0..<min($0 + rowsPerPage, suggestedRows.count)])
        }
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
                            Text("Rekke \(index * rowsPerPage + rowIndex + 1) - \(row.sourceLabel)")
                                .font(.headline)
                            Text(formattedNumbers(row.numbers))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                            if !row.predictedMatches.isEmpty {
                                Text("Predikert: \(formattedNumbers(row.predictedMatches))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !row.sameWeekMatches.isEmpty {
                                Text("Samme uke: \(formattedNumbers(row.sameWeekMatches))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
