//
//  NumberCountTestView.swift
//  Lotto
//
//  Created by Terje Moe on 03/02/2026.
//

import SwiftUI
import SwiftData


/// Shows frequency and intervals for numbers in draws.
struct NumberCountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var counts: [Int: Int] = [:]
    @State private var averageDaysBetween: [Int: Double] = [:]
    @State private var lastDatePerNumber: [Int: Date] = [:]
    @State private var nextDatePerNumber: [Int: Date] = [:]
    @State private var isPresentingPrintDialog = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            // Local sorting for the view.
            let sortedCounts = counts
                .map { ($0.key, $0.value) }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0 < rhs.0
                    }
                    return lhs.1 > rhs.1
                }
            
            Text("Antall Number: \(sortedCounts.count)")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            List {
                ForEach(sortedCounts, id: \.0) { number, count in
                    HStack {
                        Text("Number \(number)")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Count: \(count)")
                            if let avg = averageDaysBetween[number] {
                                Text(String(format: "Avg: %.1f days", avg))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Avg: -")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let next = nextDatePerNumber[number] {
                                Text("Next: \(next, style: .date)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let weekNumber = getWeekNumber(from: next)
                                Text("Uke: \(weekNumber)")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Next: -")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Uke: _")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onAppear(perform: loadCounts)
            .navigationTitle("Number counts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ferdig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                    
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingPrintDialog = true
                    } label: {
                        Label("Print", systemImage: "printer.fill")
                    }
                    .disabled(counts.isEmpty)
                }
            }
            
            .sheet(isPresented: $isPresentingPrintDialog) {
                PrintController(
                    content: PrintableNumberCountsView(
                        counts: counts,
                        averageDaysBetween: averageDaysBetween,
                        nextDatePerNumber: nextDatePerNumber
                    ),
                    title: "Number Statistikk",
                    date: nil,
                    completion: {
                        isPresentingPrintDialog = false
                    }
                )
            }
            .onChange(of: excludeHighestGapFromAverage) { _, _ in
                loadCounts()
            }
        }
    }
    
    
    /// Returns the week number (1-53) for the given date.
    func getWeekNumber(from date: Date) -> Int {
        LottoDateSupport.weekNumber(for: date)
    }
    
    /// Loads stats and updates the view.
    private func loadCounts() {
        do {
            let descriptor = FetchDescriptor<JackPot>()
            let jackpots = try context.fetch(descriptor)
            let stats = LottoStatistics.statsPerNumber(
                from: jackpots,
                excludeHighestGapFromAverage: excludeHighestGapFromAverage
            )
            self.averageDaysBetween = stats.avgGaps
            self.lastDatePerNumber = stats.lastDates
            self.nextDatePerNumber = LottoStatistics.nextDatesPerNumber(
                avgGaps: stats.avgGaps,
                lastDates: stats.lastDates,
                advancingPast: Date()
            )
            counts = LottoStatistics.frequency(for: jackpots)
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke laste statistikk: \(error.localizedDescription)"
        }
    }
    /// Print-friendly view of number stats.
    struct PrintableNumberCountsView: View {
        let counts: [Int: Int]
        let averageDaysBetween: [Int: Double]
        let nextDatePerNumber: [Int: Date]

        private let printablePageHeight: CGFloat = 730
        private let horizontalPadding: CGFloat = 16
        private let headerHeight: CGFloat = 26
        private let rowHeight: CGFloat = 18
        private let rowsPerPage: Int

        init(counts: [Int: Int], averageDaysBetween: [Int: Double], nextDatePerNumber: [Int: Date]) {
            self.counts = counts
            self.averageDaysBetween = averageDaysBetween
            self.nextDatePerNumber = nextDatePerNumber
            self.rowsPerPage = Int((printablePageHeight - headerHeight) / rowHeight)
        }
        
        private var sortedCounts: [(Int, Int)] {
            counts
                .map { ($0.key, $0.value) }
                .sorted { lhs, rhs in
                    if lhs.1 == rhs.1 {
                        return lhs.0 < rhs.0
                    }
                    return lhs.1 > rhs.1
                }
        }
        
        private var chunkedCounts: [[(Int, Int)]] {
            let allChunks = stride(from: 0, to: sortedCounts.count, by: rowsPerPage).map { start in
                Array(sortedCounts[start..<min(start + rowsPerPage, sortedCounts.count)])
            }
            return allChunks.filter { !$0.isEmpty }
        }

        private var fitsOnOnePage: Bool { chunkedCounts.count == 1 }
        
        var body: some View {
            Group {
                if fitsOnOnePage {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Number Statistikk")
                            .bold()
                            .font(.headline)
                            .padding(.bottom, 6)
                        Text("Totalt antall numre: \(sortedCounts.count)")
                            .font(.footnote)
                        Divider()
                        // Header row
                        HStack {
                            Spacer()
                            Text("Count")
                                .frame(width: 60, alignment: .trailing)
                            Text("Avg Days")
                                .frame(width: 80, alignment: .trailing)
                            Text("Next Date")
                                .frame(width: 100, alignment: .trailing)
                            Text("Uke")
                                .frame(width: 40, alignment: .trailing)
                        }
                        .font(.caption)
                        .frame(height: rowHeight)
                        Divider()
                        
                        ForEach(sortedCounts, id: \.0) { number, count in
                            HStack {
                                Text("Number \(number)")
                                    .frame(width: 80, alignment: .leading)
                                Spacer()
                                Text("\(count)")
                                    .frame(width: 60, alignment: .trailing)
                                    .fontWeight(.semibold)
                                let avg = averageDaysBetween[number]
                                Text(avg != nil ? String(format: "%.1f", avg!) : "-")
                                    .frame(width: 80, alignment: .trailing)
                                
                                if let next = nextDatePerNumber[number] {
                                    Text(next, style: .date)
                                        .frame(width: 100, alignment: .trailing)
                                    let weekNumber = LottoDateSupport.weekNumber(for: next)
                                    Text("\(weekNumber)")
                                        .frame(width: 40, alignment: .trailing)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("-")
                                        .frame(width: 100, alignment: .trailing)
                                    Text("_")
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                            .font(.caption)
                            .frame(height: rowHeight)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.black)
                } else if chunkedCounts.count > 0 {
                    ForEach(Array(chunkedCounts.enumerated()), id: \.offset) { index, chunk in
                        VStack(alignment: .leading, spacing: 0) {
                            if index == 0 {
                                Text("Number Statistikk")
                                    .bold()
                                    .font(.headline)
                                    .padding(.bottom, 6)
                                Text("Totalt antall numre: \(sortedCounts.count)")
                                    .font(.footnote)
                                Divider()
                                // Header row
                                HStack {
                                    Spacer()
                                    Text("Count")
                                        .frame(width: 60, alignment: .trailing)
                                    Text("Avg Days")
                                        .frame(width: 80, alignment: .trailing)
                                    Text("Next Date")
                                        .frame(width: 100, alignment: .trailing)
                                    Text("Uke")
                                        .frame(width: 40, alignment: .trailing)
                                }
                                .font(.caption)
                                .frame(height: rowHeight)
                                Divider()
                            }
                            ForEach(chunk, id: \.0) { number, count in
                                HStack {
                                    Text("Number \(number)")
                                        .frame(width: 80, alignment: .leading)
                                    Spacer()
                                    Text("\(count)")
                                        .frame(width: 60, alignment: .trailing)
                                        .fontWeight(.semibold)
                                    let avg = averageDaysBetween[number]
                                    Text(avg != nil ? String(format: "%.1f", avg!) : "-")
                                        .frame(width: 80, alignment: .trailing)
                                    
                                    if let next = nextDatePerNumber[number] {
                                        Text(next, style: .date)
                                            .frame(width: 100, alignment: .trailing)
                                        let weekNumber = LottoDateSupport.weekNumber(for: next)
                                        Text("\(weekNumber)")
                                            .frame(width: 40, alignment: .trailing)
                                            .fontWeight(.semibold)
                                    } else {
                                        Text("-")
                                            .frame(width: 100, alignment: .trailing)
                                        Text("_")
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }
                                .font(.caption)
                                .frame(height: rowHeight)
                                Divider()
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 4)
                        .background(Color.white)
                    }
                }
            }
        }
    }
}

#Preview {
    NumberCountsView()
}
