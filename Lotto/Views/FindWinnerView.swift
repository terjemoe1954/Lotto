//
//  FindWinnerView.swift
//  Lotto
//
//  Created by Terje Moe on 06/02/2026.
//

import SwiftUI
import SwiftData

/// Compares user rows against the winning row for the selected date.
struct FindWinnerView: View {
    // Selected date for which to compare results with jackpot
    @State private var selectedDate: Date = .now
    // Computed comparisons for the selected date
    @State private var comparisons: [ResultComparison] = []
    // Loading and error states
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var isPresentingPrintDialog = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Velg Dato") {
                    DatePicker("Dato", selection: $selectedDate, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                }
                
                Section {
                    Button {
                        Task { await runComparison() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().padding(.trailing, 4) }
                            Text("Kontroller dine rekker")
                        }
                    }
                    .disabled(isLoading)
                }
                
                if let errorMessage {
                    Section("Feil") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("Treff") {
                    Text(errorMessage == nil ? "Dato: \(selectedDate, style: .date)" : "")
                        .font(.subheadline)
                        .bold()
                    if comparisons.isEmpty {
                        Text("Velg en dato og trykk Kontroll.")
                            .foregroundStyle(.secondary)
                    } else {
                        List(comparisons) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Treff: \(item.matchCount)")
                                        .bold()
                                }
                                
                                HStack(alignment: .top, spacing: 12) {
                                    NumberCountView(title: "Dine nummer", numbers: item.result.numbers, extraNumber: nil)
                                    NumberCountView(title: "Vinner nummer", numbers: item.jackpot.numbers, extraNumber: item.jackpot.extraNumber)
                                }
                                if !item.matchedNumbers.isEmpty {
                                    Text("Treff: \(item.matchedNumbers.sorted().map(String.init).joined(separator: ", "))")
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                                if let extra = item.matchedExtraNumber {
                                    Text("Du traff ekstratall: \(extra)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .bold()
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 260)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ferdig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingPrintDialog = true
                    } label: {
                        Label("Print", systemImage: "printer.fill")
                    }
                    .disabled(comparisons.isEmpty || isLoading)
                }
            }
            .navigationTitle("Finn Vinner")
            .sheet(isPresented: $isPresentingPrintDialog) {
                PrintController(
                    content: PrintableResultsView(
                        comparisons: comparisons,
                        selectedDate: selectedDate
                    ),
                    title: "Resultater",
                    date: selectedDate,
                    completion: {
                        isPresentingPrintDialog = false
                    }
                )
            }
            
        }
    }
}

// MARK: - Models

/// A single user row for a draw date.
struct ResultRow: Identifiable, Hashable {
    let id: String
    let date: Date
    let numbers: [Int]
}

/// The winning row for a given date.
struct JackpotRow: Hashable {
    let date: Date
    let numbers: [Int]
    let extraNumber: Int?
}

/// Comparison between a user row and the winning row.
struct ResultComparison: Identifiable, Hashable {
    let id: String
    let result: ResultRow
    let jackpot: JackpotRow
    let matchedNumbers: [Int]
    let matchedExtraNumber: Int?
    
    var matchCount: Int { matchedNumbers.count }
}

// MARK: - Data Access
extension FindWinnerView {
    /// Fetches all Result rows for the selected date from SwiftData.
    func fetchResults(for date: Date) async throws -> [ResultRow] {
        let dayStart = normalize(date)
        // Build a date range [startOfDay, nextDay)
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        // Query SwiftData for Result rows on that date (between start and next day)
        let descriptor = FetchDescriptor<Result>(
            predicate: #Predicate { $0.dato >= dayStart && $0.dato < nextDay },
            sortBy: [SortDescriptor(\.dato)]
        )
        let results = try modelContext.fetch(descriptor)
        // Map to lightweight view model
        return results.enumerated().map { idx, r in
            ResultRow(
                id: String(r.persistentModelID.hashValue),
                date: normalize(r.dato),
                numbers: [r.nr1, r.nr2, r.nr3, r.nr4, r.nr5, r.nr6, r.nr7]
            )
        }
    }
    
    /// Fetches the JackPot row for the selected date from SwiftData.
    func fetchJackpot(for date: Date) async throws -> JackpotRow? {
        let dayStart = normalize(date)
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return nil
        }
        // Query SwiftData for JackPot on that date (unique per date per your model)
        let descriptor = FetchDescriptor<JackPot>(
            predicate: #Predicate { $0.dato >= dayStart && $0.dato < nextDay },
            sortBy: [SortDescriptor(\.dato)]
        )
        let jackpots = try modelContext.fetch(descriptor)
        guard let j = jackpots.first else { return nil }
        // Map to lightweight view model (include the first 7 numbers, ignore nr8 if it's an extra number)
        return JackpotRow(
            date: normalize(j.dato),
            numbers: [j.nr1, j.nr2, j.nr3, j.nr4, j.nr5, j.nr6, j.nr7],
            extraNumber: j.nr8
        )
    }
}

// MARK: - Logic
extension FindWinnerView {
    /// Normalizes a date to year-month-day (no time).
    func normalize(_ date: Date) -> Date {
        LottoDateSupport.normalize(date)
    }
    
    /// Runs the comparison for the selected date and updates the UI.
    func runComparison() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            comparisons = []
        }
        
        do {
            let date = normalize(selectedDate)
            async let resultsTask = fetchResults(for: date)
            async let jackpotTask = fetchJackpot(for: date)
            
            let (results, jackpotOpt) = try await (resultsTask, jackpotTask)
            
            guard let jackpot = jackpotOpt else {
                await MainActor.run {
                    errorMessage = "Ingen registrert Vinner Rekke funnet for valgte dato."
                    isLoading = false
                }
                return
            }
            
            
            let comps: [ResultComparison] = results.map { result in
                LottoWinnerLogic.comparison(for: result, against: jackpot)
            }
            
            await MainActor.run {
                comparisons = comps.sorted { $0.matchCount > $1.matchCount }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Small summary of numbers in a row (user/winner).
struct NumberCountView: View {
    let title: String
    let numbers: [Int]
    let extraNumber: Int?
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(numbers.sorted().map(String.init).joined(separator: ", "))
                .font(.system(size: 12, weight: .semibold))
            if let extraNumber {
                Text("Ekstra tall: \(extraNumber)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }
}

/// Print-friendly view of results for a selected date.
struct PrintableResultsView: View {
    let comparisons: [ResultComparison]
    let selectedDate: Date
    
    private let printablePageHeight: CGFloat = 730
    private let rowsPerPage: Int = 6
    private let horizontalPadding: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(chunkedComparisons.enumerated()), id: \.offset) { index, chunk in
                VStack(alignment: .leading, spacing: 8) {
                    if index == 0 && comparisons.isEmpty {
                        Text("Ingen rekker funnet for valgt dato.")
                    } else {
                        ForEach(chunk) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Treff: \(item.matchCount)")
                                    .font(.subheadline)
                                Text("Dine nummer: \(item.result.numbers.sorted().map(String.init).joined(separator: ", "))")
                                    .font(.caption2)
                                Text("Vinnernummer: \(item.jackpot.numbers.sorted().map(String.init).joined(separator: ", "))")
                                    .font(.caption2)
                                if let ekstra = item.jackpot.extraNumber {
                                    Text("Ekstra tall: \(ekstra)")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                                if let extra = item.matchedExtraNumber {
                                    Text("Du traff ekstratall: \(extra)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .bold()
                                }
                                if !item.matchedNumbers.isEmpty {
                                    Text("Treff: \(item.matchedNumbers.sorted().map(String.init).joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                                Divider()
                            }
                            .font(.footnote)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 12)
                .frame(height: printablePageHeight, alignment: .top)
                .background(Color.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.black)
    }

    private var chunkedComparisons: [[ResultComparison]] {
        guard !comparisons.isEmpty else {
            return [[]]
        }
        return stride(from: 0, to: comparisons.count, by: rowsPerPage).map { start in
            Array(comparisons[start..<min(start + rowsPerPage, comparisons.count)])
        }
    }
}

#Preview {
    FindWinnerView()
}
