import SwiftUI
import CloudKit

enum LotteryCloudConfiguration {
    static let containerIdentifier = "iCloud.iCloude.com.terjemoe.Lottery"
}

struct LotteryCloudStatusSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var checking = false
    @State private var status = "Ikke kontrollert"
    var body: some View {
        Section("iCloud") {
            LabeledContent("Kontotilgang", value: status)
            Button {
                Task { await check() }
            } label: {
                if checking { ProgressView("Kontrollerer iCloud …") }
                else { Label("Kontroller iCloud-tilgang", systemImage: "icloud") }
            }.disabled(checking)
            Text("Egne rekker og registreringsmarkeringer bruker din private iCloud-database når iCloud er tilgjengelig. Du kan også bruke appen uten nett. Endringer kan bruke litt tid mellom enheter.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Kontotilgang bekrefter ikke at alle data er ferdig synkronisert. Behold en full backup i tillegg.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .task { await check() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await check() } }
        }
    }
    @MainActor private func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        #if targetEnvironment(simulator)
        // Unsigned test hosts do not carry CloudKit entitlements; CKContainer can abort before throwing.
        status = "Kontroller på iPhone/iPad"
        #else
        do {
            switch try await CKContainer(identifier: LotteryCloudConfiguration.containerIdentifier).accountStatus() {
            case .available: status = "Tilgjengelig"
            case .noAccount: status = "Ikke logget inn"
            case .restricted: status = "Begrenset tilgang"
            case .temporarilyUnavailable: status = "Midlertidig utilgjengelig"
            case .couldNotDetermine: status = "Kunne ikke kontrolleres"
            @unknown default: status = "Ukjent status"
            }
        } catch { status = "Kunne ikke kontrolleres" }
        #endif
    }
}
