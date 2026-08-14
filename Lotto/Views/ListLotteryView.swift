//
//  ListMyCupons.swift
//  Lotto
//
//  Created by Terje Moe on 06/02/2026.
//

import SwiftUI
import SwiftData

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

    private var availableWeeks: [Int] {
        Array(Set(results.map(\.weekNr))).sorted(by: >)
    }

    private var currentWeekNr: Int {
        Calendar.current.component(.weekOfYear, from: .now)
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
                ZStack {
                    List(filteredResults) { result in
                        VStack(alignment: .leading) {
                            Text(formattedDate(result.dato))
                            Text("Uke: \(result.weekNr)")
                                .font(.headline)
                            HStack {
                                Text("\(result.nr1)")
                                Text("\(result.nr2)")
                                Text("\(result.nr3)")
                                Text("\(result.nr4)")
                                Text("\(result.nr5)")
                                Text("\(result.nr6)")
                                Text("\(result.nr7)")
                            }
                        }
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
                    Button {
                        isPresentingPrintDialog = true
                    } label: {
                        Label("Print", systemImage: "printer.fill")
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
                    withAnimation {
                        context.delete(item)
                        try? context.save()
                    }
                } label: {
                    Text("Slett")
                }
                Button(role: .confirm) {
                } label: {
                    Text("Avbryt")
                }
            },
            message: { item in
                Text("Er du sikker på at du vil slette trekningen \(formattedDate(item.dato))?")
            })
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
        .onAppear {
            ensureSelectedWeek()
        }
        .onChange(of: results) { _, _ in
            ensureSelectedWeek()
        }
        .onChange(of: reportFilter) { _, _ in
            ensureSelectedWeek()
        }
    }
    
    /// Formats date to the app's display format (dd.MM.yyyy).
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
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
}

/// Print-friendly list of submitted rows.
private struct PrintableLotteryResultsView: View {
    let results: [Result]
    let filterTitle: String

    private let printablePageHeight: CGFloat = 730
    private let horizontalPadding: CGFloat = 16
    private let rowsPerPage: Int = 20

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nb_NO")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
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
