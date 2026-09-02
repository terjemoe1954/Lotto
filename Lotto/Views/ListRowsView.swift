//
//  ListRows.swift
//  Lotto
//
//  Created by Terje Moe on 02/02/2026.
//

import SwiftUI
import SwiftData

/// Shows all registered draws (JackPot) and lets the user delete them.
struct ListRowsView: View {
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
    @Query(sort: \JackPot.dato, order: .reverse) private var jackpots: [JackPot]
    @State private var rowToDelete: JackPot? = nil
    @State private var showConfirmation = false
    @State private var reportFilter: ReportFilter = .weekOnly
    @State private var selectedWeekNr: Int?
    @State private var isPresentingPrintDialog = false
    @State private var errorMessage: String?

    private var availableWeeks: [Int] {
        Array(Set(jackpots.map(\.weekNr))).sorted(by: >)
    }

    private var currentWeekNr: Int {
        LottoDateSupport.weekNumber(for: .now)
    }

    private var filteredJackpots: [JackPot] {
        switch reportFilter {
        case .allPosts:
            return jackpots
        case .weekOnly:
            guard let selectedWeekNr else { return [] }
            return jackpots.filter { $0.weekNr == selectedWeekNr }
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

                Text("Antall Trekninger: \(filteredJackpots.count)")
                ZStack {
                    List(filteredJackpots) { jackpot in
                        VStack(alignment: .leading) {
                            Text(formattedDate(jackpot.dato))
                            Text("Uke: \(jackpot.weekNr)")
                                .font(.headline)
                            HStack {
                                Text("\(jackpot.nr1)")
                                Text("\(jackpot.nr2)")
                                Text("\(jackpot.nr3)")
                                Text("\(jackpot.nr4)")
                                Text("\(jackpot.nr5)")
                                Text("\(jackpot.nr6)")
                                Text("\(jackpot.nr7)")
                                Text("\(jackpot.nr8)")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                rowToDelete = jackpot
                                showConfirmation.toggle()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .navigationTitle("Trekninger")
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
                    .disabled(filteredJackpots.isEmpty)
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
                        try delete(jackpot: item)
                    } catch {
                        errorMessage = "Kunne ikke slette trekningen: \(error.localizedDescription)"
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
                content: PrintableJackpotRowsView(
                    jackpots: filteredJackpots,
                    filterTitle: filterTitle
                ),
                title: "Lotto trekninger - \(filterTitle)",
                date: nil,
                completion: {
                    isPresentingPrintDialog = false
                }
            )
        }
        .onAppear {
            ensureSelectedWeek()
        }
        .onChange(of: jackpots) { _, _ in
            ensureSelectedWeek()
        }
        .onChange(of: reportFilter) { _, _ in
            ensureSelectedWeek()
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

    private func delete(jackpot: JackPot) throws {
        withAnimation {
            context.delete(jackpot)
        }

        do {
            try context.save()
        } catch {
            context.insert(jackpot)
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

/// Print-friendly list of draw rows.
private struct PrintableJackpotRowsView: View {
    let jackpots: [JackPot]
    let filterTitle: String

    private let printablePageHeight: CGFloat = 730
    private let horizontalPadding: CGFloat = 16
    private let rowsPerPage: Int = 20

    private var chunkedJackpots: [[JackPot]] {
        var chunks: [[JackPot]] = []
        var currentChunk: [JackPot] = []

        for jackpot in jackpots {
            currentChunk.append(jackpot)
            if currentChunk.count == rowsPerPage {
                chunks.append(currentChunk)
                currentChunk = []
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }

    private func formattedDate(_ date: Date) -> String {
        LottoDateSupport.formattedDate(date)
    }

    var body: some View {
        ForEach(Array(chunkedJackpots.enumerated()), id: \.offset) { index, chunk in
            VStack(alignment: .leading, spacing: 10) {
                if index == 0 {
                    Text("Filter: \(filterTitle)")
                        .font(.headline)
                    Text("Antall trekninger: \(jackpots.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(chunk, id: \.id) { jackpot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate(jackpot.dato))
                        Text("Uke: \(jackpot.weekNr)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(jackpot.nr1)  \(jackpot.nr2)  \(jackpot.nr3)  \(jackpot.nr4)  \(jackpot.nr5)  \(jackpot.nr6)  \(jackpot.nr7)  \(jackpot.nr8)")
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

#Preview {
    ListRowsView()
}
