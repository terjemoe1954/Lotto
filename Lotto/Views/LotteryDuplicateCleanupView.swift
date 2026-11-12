import SwiftUI
import SwiftData

struct LotteryDuplicateCleanupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let settings: LottoBackupSettings
    @State private var counts: LotteryDuplicateCleanup.Counts?
    @State private var confirmation = false
    @State private var running = false
    @State private var outcome: LotteryDuplicateCleanup.Outcome?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Like egne rekker") {
                    Text("En dublett har samme spill, trekningsdato og tall, inkludert tilleggstall. Én eksisterende kopi beholdes uendret. Samme rekke på en annen trekningsdato beholdes også.")
                    Text("Kjør oppryddingen på én enhet om gangen. Vent til slettingene er synkronisert med iCloud før du eventuelt kjører den på en annen enhet.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let counts {
                        LabeledContent("Ekstra Lotto-kopier", value: "\(counts.lotto)")
                        LabeledContent("Ekstra Vikinglotto-kopier", value: "\(counts.vikinglotto)")
                        LabeledContent("Ekstra Eurojackpot-kopier", value: "\(counts.eurojackpot)")
                    }
                    Button("Kontroller på nytt", action: scan).disabled(running)
                }
                Section("Sikkerhetskopi før sletting") {
                    Text("Appen lagrer og kontrollerer en full sikkerhetskopi på denne enheten før noe slettes. Trekninger, favoritter, Levert-markeringer og spilleoversikt beholdes. Den automatiske innsatsen og gevinsten endres ikke av at ekstra kopier fjernes.")
                        .font(.footnote)
                    Button("Behold én kopi og fjern dubletter", role: .destructive) { confirmation = true }
                        .disabled(running || (counts?.total ?? 0) == 0)
                    if running { ProgressView("Tar sikkerhetskopi og rydder …") }
                }
                if let outcome {
                    Section("Resultat") {
                        Text("Fjernet \(outcome.removed.total) ekstra kopier. \(outcome.removed.text).")
                        Text("Slettingene synkroniseres med iCloud. Kontroller også den andre enheten.").font(.footnote)
                        if let file = outcome.backupURL {
                            ShareLink("Del sikkerhetskopien", item: file)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Rydd dubletter")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() }.disabled(running) } }
            .task { scan() }
            .confirmationDialog("Fjern bare ekstra kopier?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Ta backup og fjern dubletter", role: .destructive) {
                    running = true
                    Task { @MainActor in
                        do { outcome = try LotteryDuplicateCleanup.clean(context: context, settings: settings); scan() }
                        catch { self.error = "Oppryddingen kunne ikke fullføres: \(error.localizedDescription)" }
                        running = false
                    }
                }
            } message: {
                Text("\(counts?.total ?? 0) ekstra kopier er funnet. Én kopi av hver rekke beholdes. Oppryddingen kontrollerer antallet på nytt før sletting.")
            }
        }
    }
    private func scan() {
        do { counts = try LotteryDuplicateCleanup.plan(context: context).counts; error = nil }
        catch { self.error = error.localizedDescription; counts = nil }
    }
}
