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
    @State private var counts: [Int: Int] = [:]
    @State private var averageDaysBetween: [Int: Double] = [:]
    @State private var lastDatePerNumber: [Int: Date] = [:]
    @State private var nextDatePerNumber: [Int: Date] = [:]
    @State private var isPresentingPrintDialog = false
    
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
        }
    }
    
    
    /// Returns the week number (1-53) for the given date.
    func getWeekNumber(from date: Date) -> Int {
        let calendar = Calendar.current
        // Returns 1-53
        return calendar.component(.weekOfYear, from: date)
    }
    
    /// Counts occurrences for numbers 1-34.
    func frequencyForNumbers1to34(in numbers: [Int]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for number in numbers {
            if (1...34).contains(number) {
                counts[number, default: 0] += 1
            }
        }
        return counts
    }
    
    /// Computes average days between occurrences per number.
    func averageDayGapsPerNumber(from jackpots: [JackPot]) -> [Int: Double] {
        var appearances: [Int: [Date]] = [:]
        for jackpot in jackpots {
            let date = jackpot.dato
            let nums = [jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4,
                        jackpot.nr5, jackpot.nr6, jackpot.nr7, jackpot.nr8]
            for n in nums where (1...34).contains(n) {
                appearances[n, default: []].append(date)
            }
        }
        
        var result: [Int: Double] = [:]
        let calendar = Calendar.current
        
        for (number, dates) in appearances {
            let sorted = dates.sorted()
            guard sorted.count >= 2 else { continue }
            
            var gaps: [Double] = []
            for i in 1..<sorted.count {
                let d1 = sorted[i-1]
                let d2 = sorted[i]
                if let days = calendar.dateComponents([.day], from: d1, to: d2).day {
                    gaps.append(Double(days))
                }
            }
            
            if !gaps.isEmpty {
                // NEW: Handle outliers - use trimmed mean or median
                let avg = trimmedAverage(gaps: gaps) // or use median(gaps)
                result[number] = avg
            }
        }
        return result
    }
    
    // MARK: - Outlier-resistant average calculations
    /// Trims outliers before averaging.
    private func trimmedAverage(gaps: [Double]) -> Double {
        let sortedGaps = gaps.sorted()
        let count = sortedGaps.count
        
        // Remove top/bottom 20% as outliers (minimum 1 gap each side)
        let trimCount = max(1, count / 5)
        let startIndex = trimCount
        let endIndex = count - trimCount
        
        let trimmedGaps = Array(sortedGaps[startIndex..<endIndex])
        return trimmedGaps.reduce(0, +) / Double(trimmedGaps.count)
    }
    
    /// Median for a list of gaps.
    private func median(gaps: [Double]) -> Double {
        let sortedGaps = gaps.sorted()
        let count = sortedGaps.count
        
        if count % 2 == 0 {
            let mid1 = sortedGaps[count/2 - 1]
            let mid2 = sortedGaps[count/2]
            return (mid1 + mid2) / 2.0
        } else {
            return sortedGaps[count/2]
        }
    }
    
    /// Summarizes stats per number.
    func statsPerNumber(from jackpots: [JackPot]) -> (
        avgGaps: [Int: Double],
        lastDates: [Int: Date]
    ) {
        var appearances: [Int: [Date]] = [:]
        
        for jackpot in jackpots {
            let date = jackpot.dato
            let nums = [jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4,
                        jackpot.nr5, jackpot.nr6, jackpot.nr7, jackpot.nr8]
            for n in nums where (1...34).contains(n) {
                appearances[n, default: []].append(date)
            }
        }
        
        var avgGaps: [Int: Double] = [:]
        var lastDates: [Int: Date] = [:]
        let calendar = Calendar.current
        
        for (number, dates) in appearances {
            let sorted = dates.sorted()
            lastDates[number] = sorted.last
            
            guard sorted.count >= 2 else { continue }
            
            var gaps: [Double] = []
            for i in 1..<sorted.count {
                let d1 = sorted[i-1]
                let d2 = sorted[i]
                if let days = calendar.dateComponents([.day], from: d1, to: d2).day {
                    gaps.append(Double(days))
                }
            }
            
            if !gaps.isEmpty {
                // Use trimmed average instead of simple mean
                avgGaps[number] = trimmedAverage(gaps: gaps)
                // Alternative: avgGaps[number] = median(gaps: gaps)
            }
        }
        return (avgGaps, lastDates)
    }
    
    
    
    
    /// Loads stats and updates the view.
    private func loadCounts() {
        do {
            let descriptor = FetchDescriptor<JackPot>()
            let jackpots = try context.fetch(descriptor)
            let stats = statsPerNumber(from: jackpots)
            self.averageDaysBetween = stats.avgGaps
            self.lastDatePerNumber = stats.lastDates
            
            // Computes predicted next date per number.
            var predicted: [Int: Date] = [:]
            let calendar = Calendar.current
            for (number, lastDate) in stats.lastDates {
                if let avgDays = stats.avgGaps[number] {
                    // Use at least 1 day and round to nearest whole day
                    let stepDays = max(1, Int(avgDays.rounded()))
                    var candidate = calendar.date(byAdding: .day, value: stepDays, to: lastDate)
                    let now = Date()
                    // Advance in whole average-day steps until strictly after now
                    while let c = candidate, c <= now {
                        candidate = calendar.date(byAdding: .day, value: stepDays, to: c)
                    }
                    if let c = candidate {
                        // Normalize to start of the next day to avoid "present date"
                        if let startOfDay = calendar.startOfDay(for: c) as Date?,
                           let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
                            predicted[number] = nextDay
                        } else {
                            predicted[number] = c
                        }
                    }
                }
            }
            self.nextDatePerNumber = predicted
            let numbers = jackpots.flatMap { jackpot in
                [jackpot.nr1, jackpot.nr2, jackpot.nr3, jackpot.nr4,
                 jackpot.nr5, jackpot.nr6, jackpot.nr7, jackpot.nr8]
            }
            counts = frequencyForNumbers1to34(in: numbers)
        } catch {
            print("Failed to load counts: \(error)")
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
                                    let weekNumber = Calendar.current.component(.weekOfYear, from: next)
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
                                        let weekNumber = Calendar.current.component(.weekOfYear, from: next)
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

