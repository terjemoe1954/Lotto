//
//  NumberPredictionForm.swift
//  Lotto
//
//  Created by Terje Moe on 08/02/2026.
//
import SwiftUI
import SwiftData

/// Predicts possible numbers based on historical draws.
struct NumberPredictionForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("toleranse") var toleranse: Double = 3.0
    @State private var selectedDate = Date()
    @State private var predictedNumbers: [Int] = []
    @State private var stats: (
        avgGaps: [Int: Double],
        lastDates: [Int: Date],
        nextDates: [Int: Date]
    ) = ([:], [:], [:])
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Form {
                // Date picker section
                Section("Velg dato") {
                    DatePicker(
                        "For denne datoen",
                        selection: $selectedDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                }
                
                // Loading indicator
                if isLoading {
                    Section {
                        ProgressView("Laster statistikk...")
                            .frame(maxWidth: .infinity)
                    }
                }
                Text("Tolererer (+/-) \(Int(toleranse)) dagers avvik. Dette kan endres i settings")
                // Predicted numbers
                Section("Mulige tall for \(selectedDate.formatted(Date.FormatStyle.dateTime.weekday(.abbreviated).month(.twoDigits).day(.twoDigits)))") {
                    if predictedNumbers.isEmpty {
                        Text("Ingen tall predikert for denne datoen")
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
                
                // Stats summary
                Section("Statistikk") {
                    Text("\(predictedNumbers.count) av 34 tall er aktuelle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Predikerte tall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ferdig") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("I dag") {
                        selectedDate = Date()
                        updatePredictions()
                    }
                }
            }
            .onAppear(perform: loadStats)
            .onChange(of: selectedDate) { _, _ in
                updatePredictions()
            }
        }
    }
    
    // MARK: - Data loading
    /// Loads stats from all JackPot rows and computes the next date per number.
    private func loadStats() {
        Task { @MainActor in
            do {
                let descriptor = FetchDescriptor<JackPot>()
                let jackpots = try context.fetch(descriptor)
                let (avgGaps, lastDates) = statsPerNumber(from: jackpots)
                
                var nextDates: [Int: Date] = [:]
                let calendar = Calendar.current
                for (number, lastDate) in lastDates {
                    if let avgDays = avgGaps[number] {
                        if let nextDate = calendar.date(
                            byAdding: .day,
                            value: Int(avgDays.rounded()),
                            to: lastDate
                        ) {
                            nextDates[number] = nextDate
                        }
                    }
                }
                
                stats = (avgGaps, lastDates, nextDates)
                updatePredictions()
                isLoading = false
            } catch {
                print("Failed to load stats: \(error)")
                isLoading = false
            }
        }
    }
    
    /// Updates the list of predicted numbers for the selected date.
    private func updatePredictions() {
        let calendar = Calendar.current
        
        // Filter numbers whose predicted date is close to selected date (±3 days)
        let toleranceDays: Double = toleranse
        predictedNumbers = stats.nextDates.filter { number, predictedDate in
            if let daysDiff = calendar.dateComponents([.day], from: predictedDate, to: selectedDate).day {
                return abs(Double(daysDiff)) <= toleranceDays
            }
            return false
        }.keys.map { $0 }
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

// MARK: - Reuse your existing functions (add trimmedAverage)
extension NumberPredictionForm {
    /// Calculates average gaps between occurrences per number.
    private func statsPerNumber(from jackpots: [JackPot]) -> (
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
                avgGaps[number] = trimmedAverage(gaps: gaps)
            }
        }
        return (avgGaps, lastDates)
    }
    
    /// Robust average that tolerates outliers in the data set.
    private func trimmedAverage(gaps: [Double]) -> Double {
        let sortedGaps = gaps.sorted()
        let count = sortedGaps.count
        
        // Fallback to previous 20% trimmed mean for very small samples
        if count < 4 {
            let trimCount = max(1, count / 5)
            let startIndex = min(trimCount, max(0, count - 1))
            let endIndex = max(startIndex + 1, count - trimCount)
            let trimmed = Array(sortedGaps[startIndex..<endIndex])
            let sum = trimmed.reduce(0, +)
            return sum / Double(trimmed.count)
        }
        
        // Helper to compute median of a slice
        func median(of array: [Double]) -> Double {
            let n = array.count
            if n == 0 { return .nan }
            if n % 2 == 1 {
                return array[n / 2]
            } else {
                return (array[n / 2 - 1] + array[n / 2]) / 2.0
            }
        }
        
        // Split into lower and upper halves (exclude median if odd count)
        let mid = count / 2
        let lowerHalf: [Double]
        let upperHalf: [Double]
        if count % 2 == 0 {
            lowerHalf = Array(sortedGaps[..<mid])
            upperHalf = Array(sortedGaps[mid...])
        } else {
            lowerHalf = Array(sortedGaps[..<mid])
            upperHalf = Array(sortedGaps[(mid+1)...])
        }
        
        let q1 = median(of: lowerHalf)
        let q3 = median(of: upperHalf)
        let iqr = q3 - q1
        
        // If IQR is zero, fall back to simple mean (all values identical or nearly so)
        if iqr <= 0 {
            let sum = sortedGaps.reduce(0, +)
            return sum / Double(count)
        }
        
        let lowerFence = q1 - 1.5 * iqr
        let upperFence = q3 + 1.5 * iqr
        let filtered = sortedGaps.filter { $0 >= lowerFence && $0 <= upperFence }
        
        // If filtering removed everything, fall back to 20% trimmed mean
        if filtered.isEmpty {
            let trimCount = max(1, count / 5)
            let startIndex = min(trimCount, max(0, count - 1))
            let endIndex = max(startIndex + 1, count - trimCount)
            let trimmed = Array(sortedGaps[startIndex..<endIndex])
            let sum = trimmed.reduce(0, +)
            return sum / Double(trimmed.count)
        }
        
        let sum = filtered.reduce(0, +)
        return sum / Double(filtered.count)
    }
}

#Preview {
    NumberPredictionForm()
        .modelContainer(for: JackPot.self)
}
