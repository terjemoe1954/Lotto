import SwiftUI
import SwiftData

struct LotteryOwnGamesResetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let settings: LottoBackupSettings
    @State private var prepared: LotteryOwnGamesReset.Prepared?
    @State private var understandsCloud = false
    @State private var confirmation = false
    @State private var finished = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Dette nullstilles") {
                    Text("Alle egne rekker og systemrekkenes delrekker i Lotto, Vikinglotto og Eurojackpot fjernes. Levert-markeringer og manuelt registrerte innsatser og gevinster fjernes også. Mine gevinster og spilleoversikten begynner dermed på nytt.")
                }
                Section("Dette beholdes") {
                    Text("Offisielle trekninger og tallstatistikken fra dem beholdes. Favoritttall, innstillinger og sikkerhetskopier beholdes også.")
                }
                Section("Gjelder også andre enheter") {
                    Text("Nullstillingen synkroniseres via iCloud til andre enheter med samme Apple-konto. Dette er ikke en nullstilling bare på denne enheten.")
                    Text("La iCloud synkronisere ferdig først. Unngå å legge inn spill på andre enheter mens du nullstiller. Spill som ikke var synkronisert fra en frakoblet enhet, kan dukke opp senere; kontroller enhetene når de er tilkoblet igjen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("1. Sikkerhetskopi først") {
                    Button("Lag og kontroller full backup") {
                        do {
                            prepared = try LotteryOwnGamesReset.prepare(context: context, settings: settings)
                            understandsCloud = false; error = nil
                        } catch { prepared = nil; self.error = error.localizedDescription }
                    }.disabled(finished)
                    if let prepared {
                        Text("Backupen er lagret og kontrollert. Den inneholder \(prepared.ownRows) egne rekker og \(prepared.ledgerEntries) manuelle beløpsposter.")
                        ShareLink("Lagre / del sikkerhetskopi", item: prepared.backupURL)
                        Text("Kopien ligger i appens dokumentmappe, Lotto-backups. Lagre gjerne en kopi utenfor appen via delingsknappen. Den kan senere gjenopprettes med «Gjenopprett hele backupen» i Innstillinger.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !finished {
                    Section("2. Bekreft nullstilling") {
                        Toggle("Jeg forstår at egne spill og beløp nullstilles også på andre enheter via iCloud", isOn: $understandsCloud)
                            .disabled(prepared == nil)
                        Button("Start på nytt med egne spill", role: .destructive) { confirmation = true }
                            .disabled(prepared == nil || !understandsCloud)
                    }
                } else {
                    Section("Fullført") {
                        Text("Egne spill og beløp er nullstilt. Trekninger, tallstatistikk og backup er beholdt. La iCloud synkronisere, og kontroller de andre enhetene.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Start på nytt")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
            .confirmationDialog("Nullstille egne spill på alle enhetene?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("Nullstill egne spill og beløp", role: .destructive) {
                    guard let prepared else { return }
                    do {
                        try LotteryOwnGamesReset.reset(prepared, context: context, settings: settings)
                        finished = true; error = nil
                    } catch {
                        self.error = error.localizedDescription
                        self.prepared = nil; understandsCloud = false
                    }
                }
                Button("Avbryt", role: .cancel) { }
            } message: {
                Text("\(prepared?.ownRows ?? 0) egne rekker og \(prepared?.ledgerEntries ?? 0) manuelle beløpsposter fjernes. Levert-markeringer nullstilles. Endringen gjelder også via iCloud. Trekninger og tallstatistikk beholdes. Du må gjenopprette backupen for å angre.")
            }
        }
    }
}
