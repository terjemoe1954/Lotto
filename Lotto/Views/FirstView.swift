//
//  ContentView.swift
//  Lotto
//
//  Created by Terje Moe on 30/01/2026.
//

import SwiftUI
import SwiftData

/// Main menu for the app with entry points to all features.
struct FirstView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \JackPot.dato, order: .forward) private var jackpots: [JackPot]
    @AppStorage("toleranse") var toleranse: Double = 3.0
    @AppStorage("didSeedJackpots") private var didSeedJackpots = false
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @State private var showListRows = false
    @State private var showRegisterView = false
    @State private var showNumberCountView = false
    @State private var showMyLotteryView = false
    @State private var showListLotteryView = false
    @State private var showFindWinnerView = false
    @State private var showNumberPredictionForm = false
    @State private var showingSettings = false
    @State private var errorMessage: String?
    private var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some View {
        NavigationStack {
            ZStack{
                Image("LotteryBackground")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.2)
                    .ignoresSafeArea()
                VStack {
                    Text("LOTTO")
                        .font(.largeTitle)
                        .bold()
                        .padding(.top, 20)
                  
                    Spacer()
                    HStack {
                        Spacer()
                        VStack {
                            Button(action: {
                                showMyLotteryView = true
                            }) {
                                Image(systemName: "bitcoinsign.ring.dashed")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            Text("Levere")
                        }
                        
                        VStack {
                            Button(action: {
                                showListLotteryView = true
                            }) {
                                Image(systemName: "pencil.and.list.clipboard")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            Text("Liste")
                        }
                        
                        VStack {
                            Button(action: {
                                showNumberPredictionForm = true
                            }) {
                                Image(systemName: "wand.and.stars")
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            Text("Forslag")
                        }
                        Spacer()
                    }
                    Text("Spill")
                        .padding()
                        .font(.largeTitle)
                        .bold()
                    Rectangle()
                        .frame(height: 4)
                        .foregroundStyle(.black)
                    Spacer()
                    
                    HStack {
                        Spacer()
                        VStack {
                            Button(action: {
                                showRegisterView = true
                            }) {
                                Image(systemName: "list.bullet.circle.fill")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Text("Registrer Ny")
                            
                        }
                        .padding()
                        
                        VStack {
                            Button(action: {
                                showListRows = true
                            }) {
                                Image(systemName: "pencil.and.list.clipboard")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            Text("Liste Alle")
                        }
                        .padding()
                        Spacer()
                    }
                    
                    Text("Trekninger" )
                        .padding(.top,10)
                        .font(.largeTitle)
                        .bold()
                    
                    // Spacer()
                    Rectangle()
                        .frame(height: 4)
                        .foregroundStyle(.black)
                    
                    
                    HStack{
                        VStack {
                            Button(action: {
                                showNumberCountView = true
                            }) {
                                Image(systemName: "function")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Text("Statistikk")
                        }
                        
                        .padding()
                        
                        VStack {
                            Button(action: {
                                showFindWinnerView = true
                            }) {
                                Image(systemName: "flag.2.crossed")   // Replace with your asset name
                                    .resizable()
                                    .frame(width: 50, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.borderedProminent)
                            Text("Sjekk Vinner")
                        }
                        .padding()
                        
                    }
                    
                    
                    Spacer()
                }
            }.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(Font.system(size: 25, weight: .black))
                            .background(.clear)
                    }
                }
            }
        }
        .task {
            await seedJackpotsIfNeeded()
            await removeDuplicateJackpotsIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await removeDuplicateJackpotsIfNeeded()
            }
        }
        .onChange(of: jackpots.count) { _, _ in
            Task {
                await removeDuplicateJackpotsIfNeeded()
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .sheet(isPresented: $showNumberPredictionForm) {
            NumberPredictionForm()
        }
        .sheet(isPresented: $showMyLotteryView) {
            MyLotteryView()
        }
        .sheet(isPresented: $showListLotteryView) {
            ListLotteryView()
        }
        .sheet(isPresented: $showListRows) {
            ListRowsView()
        }
        .sheet(isPresented: $showRegisterView) {
            NewJackpotView()
        }
        .sheet(isPresented: $showNumberCountView) {
            NumberCountsView()
        }
        .sheet(isPresented: $showFindWinnerView) {
            FindWinnerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(toleranse: $toleranse)
        }
        .alert("Feil", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    /// Reads `lotto.json` from the app bundle and decodes to JackPot.
    func loadJackpots() throws -> [JackPot] {
        guard let url = Bundle.main.url(forResource: "lotto", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode([JackPot].self, from: data)
    }
    
    /// Returns the week number (1-53) for the given date.
    func getWeekNumber(from date: Date) -> Int {
        LottoDateSupport.weekNumber(for: date)
    }

    @MainActor
    private func seedJackpotsIfNeeded() async {
        do {
            let existingCount = try context.fetchCount(FetchDescriptor<JackPot>())
            guard LottoRules.shouldSeedJackpots(
                didSeedJackpots: didSeedJackpots,
                existingCount: existingCount
            ) else {
                if existingCount > 0 {
                    didSeedJackpots = true
                }
                return
            }

            try await Task.sleep(for: .seconds(2))

            let syncedJackpots = try context.fetch(FetchDescriptor<JackPot>())
            if !syncedJackpots.isEmpty {
                didSeedJackpots = true
                return
            }

            let seedJackpots = try loadJackpots()
            let jackpotsToInsert = LottoRules.missingSeedJackpots(
                seedJackpots: seedJackpots,
                existingDates: syncedJackpots.map(\.dato)
            )

            guard !jackpotsToInsert.isEmpty else {
                didSeedJackpots = true
                return
            }

            for jackpot in jackpotsToInsert {
                jackpot.weekNr = getWeekNumber(from: jackpot.dato)
                context.insert(jackpot)
            }

            try context.save()
            didSeedJackpots = true
            errorMessage = nil
        } catch {
            errorMessage = "Kunne ikke laste historiske trekninger: \(error.localizedDescription)"
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

    @MainActor
    private func removeDuplicateJackpotsIfNeeded() async {
        do {
            let fetchedJackpots = try context.fetch(FetchDescriptor<JackPot>())
            let duplicates = LottoRules.duplicateJackpots(in: fetchedJackpots)
            guard !duplicates.isEmpty else { return }

            for duplicate in duplicates {
                context.delete(duplicate)
            }

            try context.save()
        } catch {
            errorMessage = "Kunne ikke rydde dubletter i trekninger: \(error.localizedDescription)"
        }
    }
    
}


#Preview {
    FirstView()
        .modelContainer(for: JackPot.self, inMemory: true)
}
