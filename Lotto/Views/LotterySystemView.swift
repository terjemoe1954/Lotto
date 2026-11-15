import SwiftUI
import SwiftData

struct LotterySystemView: View {
    let initialGame: LotteryReportGame
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var game: LotteryReportGame = .lotto
    @State private var mainCount = 8
    @State private var extraCount = 0
    @State private var main = Set<Int>()
    @State private var extra = Set<Int>()
    @State private var date = Date()
    @State private var message: String?
    private var count: Int { LotterySystem.rowCount(game: game, main: mainCount, extra: extraCount) }
    private var error: String? { LotterySystem.validation(game: game, main: main.sorted(), extra: extra.sorted(), date: date) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Fullt system") {
                    Picker("Spill", selection: $game) { ForEach(LotteryReportGame.allCases) { Text($0.title).tag($0) } }
                    DatePicker("Trekningsdato", selection: $date, displayedComponents: .date)
                    Stepper("Hovedtall: \(mainCount)", value: $mainCount, in: LotterySystem.mainCount(game)...(game == .eurojackpot ? 10 : 12))
                    if game != .lotto {
                        Stepper("Tilleggstall: \(extraCount)", value: $extraCount, in: LotterySystem.extraCount(game)...(game == .vikinglotto ? 5 : 12))
                    }
                    Text("Du velger antall tall; antall rekker følger av alle kombinasjonene. Maks 2000 rekker i appen. Pris etter dagens rekkepris; kontroller pris hos Norsk Tipping.").font(.footnote)
                }
                LotteryOddsSummary(game: game, main: mainCount, extra: extraCount)
                Section("Hovedtall: \(main.count) av \(mainCount)") { numberGrid(maximum: game == .lotto ? 34 : (game == .vikinglotto ? 48 : 50), selection: $main, limit: mainCount) }
                if game != .lotto {
                    Section(game == .vikinglotto ? "Vikingtall: \(extra.count) av \(extraCount)" : "Stjernetall: \(extra.count) av \(extraCount)") {
                        numberGrid(maximum: game == .vikinglotto ? 5 : 12, selection: $extra, limit: extraCount)
                    }
                }
                Section {
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Button("Lagre systemets \(count) enkeltrekker") {
                        let rows = LotterySystem.rows(game: game, main: main.sorted(), extra: extra.sorted(), date: date)
                        guard !rows.isEmpty else { return }
                        do {
                            let added = try LotterySystem.save(rows, context: context)
                            message = "Lagret \(added) nye enkeltrekker. \(rows.count - added) var allerede lagret. Du finner dem under Mine rekker / Liste og i Ukesrapport. Merk dem som Levert først når du faktisk har levert hos Norsk Tipping."
                        } catch { message = error.localizedDescription }
                    }.disabled(error != nil || main.count != mainCount || extra.count != extraCount)
                    Text("Systemet lagres som enkeltrekker, uten egen systemgruppe. Hver rekke kontrolleres mot sin trekning og får sin ordinære premie. Gevinster summeres i Mine gevinster. Dette er ikke innlevering eller betaling, og omfatter ikke reduserte systemer eller andelsfordeling.").font(.footnote)
                }
            }
            .navigationTitle("Systemspill")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .onAppear { game = initialGame; reset() }
            .onChange(of: game) { _, _ in reset() }
            .onChange(of: mainCount) { _, _ in main = [] }
            .onChange(of: extraCount) { _, _ in extra = [] }
            .alert("Systemspill", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
        }
    }
    private func reset() {
        mainCount = LotterySystem.mainCount(game) + 1; extraCount = LotterySystem.extraCount(game)
        main = []; extra = []
        date = game == .lotto ? LottoDateSupport.nextSaturday(onOrAfter: .now) : InternationalGame(rawValue: game.rawValue)!.nextDraw(onOrAfter: .now)
    }
    private func numberGrid(maximum: Int, selection: Binding<Set<Int>>, limit: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))]) {
            ForEach(1...maximum, id: \.self) { number in
                Button {
                    if selection.wrappedValue.contains(number) { selection.wrappedValue.remove(number) }
                    else if selection.wrappedValue.count < limit { selection.wrappedValue.insert(number) }
                } label: {
                    Text("\(number)").frame(maxWidth: .infinity, minHeight: 36)
                        .background(selection.wrappedValue.contains(number) ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(selection.wrappedValue.contains(number) ? Color.white : Color.primary)
                }.buttonStyle(.plain).accessibilityLabel("Tall \(number)").accessibilityAddTraits(selection.wrappedValue.contains(number) ? .isSelected : [])
            }
        }
    }
}
