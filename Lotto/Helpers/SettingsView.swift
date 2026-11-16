//
//  SettingsView.swift
//  Lotto
//
//  Created by Terje Moe on 12/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum BackupRestoreScope {
    case verify
    case everything
    case drawsOnly
}

private enum BackupExportScope {
    case everything
    case drawsOnly
}

/// App settings (dark mode and prediction tolerance).
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var context
    @Binding var toleranse: Double
    @AppStorage(LottoAppPreferences.appearanceModeKey) private var appearanceModeRawValue = AppearanceMode.system.rawValue
    @AppStorage(LottoAppPreferences.excludeHighestGapKey) private var excludeHighestGapFromAverage = false
    @State private var isExportingBackup = false
    @State private var showingExportOptions = false
    @State private var isImportingBackup = false
    @State private var showingRestoreOptions = false
    @State private var restoreScope: BackupRestoreScope = .everything
    @State private var backupDocument = LottoBackupDocument(
        snapshot: LottoBackupSnapshot(
            exportedAt: .now,
            settings: LottoBackupSettings(
                tolerance: 0,
                appearanceModeRawValue: AppearanceMode.system.rawValue,
                excludeHighestGapFromAverage: false
            ),
            jackpots: [],
            results: []
        )
    )
    @State private var backupFileName = "Lotto-backup.json"
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingManual = false
    @State private var showingOwnGamesReset = false
    @State private var showingDuplicateCleanup = false
    @State private var showingPrivacy = false
    @State private var isUpdatingDraws = false

    private var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRawValue) ?? .system }
        nonmutating set { appearanceModeRawValue = newValue.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Utseende") {
                    Picker("Modus", selection: Binding(
                        get: { appearanceMode },
                        set: { appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Statistikk") {
                    Toggle("Fjern hoyeste verdi fra gjennomsnitt", isOn: $excludeHighestGapFromAverage)

                    HStack {
                        Text("Toleranse")
                        Spacer()
                        TextField("Dager", value: $toleranse, formatter: toleranceFormatter)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Text("0 betyr ingen toleranse rundt intervallberegnede datoer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LotteryCloudStatusSection()

                Section("Backup") {
                    Button("Kontroller backupfil") {
                        restoreScope = .verify
                        isImportingBackup = true
                    }

                    Button("Eksporter") {
                        showingExportOptions = true
                    }

                    Button("Gjenopprett fra backup") {
                        showingRestoreOptions = true
                    }

                    Text("Du kan gjenopprette hele backupen eller bare importere manglende trekninger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Vedlikehold") {
                    Button("Start på nytt med egne spill") { showingOwnGamesReset = true }
                    Button("Rydd dupliserte egne rekker") { showingDuplicateCleanup = true }
                    Text("Beholder én kopi per spill, trekningsdato og tall. Tar en kontrollert full backup før sletting.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Trekninger") {
                    Button {
                        Task {
                            await updateDraws()
                        }
                    } label: {
                        if isUpdatingDraws {
                            HStack {
                                ProgressView()
                                Text("Kontrollerer nye trekninger …")
                            }
                        } else {
                            Label("Oppdater trekninger", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isUpdatingDraws)

                    Text("Appen kontrollerer også automatisk etter nye trekninger ved oppstart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Hjelp") {
                    Button("Åpne brukermanual") {
                        showingManual = true
                    }
                    Text("Uavhengig verktøy uten reklame. Utvikleren mottar ikke reklameinntekter eller provisjon fra Norsk Tipping. Appen er ikke tilknyttet eller godkjent av Norsk Tipping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("App") {
                    Button("Personvern og kontakt", systemImage: "hand.raised") { showingPrivacy = true }
                    LabeledContent("Versjon", value: LottoAppPreferences.appVersion)
                    LabeledContent("Build", value: LottoAppPreferences.buildNumber)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .confirmationDialog(
                "Hva vil du eksportere?",
                isPresented: $showingExportOptions,
                titleVisibility: .visible
            ) {
                Button("Full backup") {
                    exportBackup(scope: .everything)
                }

                Button("Bare trekninger") {
                    exportBackup(scope: .drawsOnly)
                }

                Button("Avbryt", role: .cancel) { }
            } message: {
                Text("Eksporten omfatter alle tre spill. En trekningseksport inneholder ikke egne rekker eller personlige innstillinger.")
            }
            .confirmationDialog(
                "Hva vil du gjenopprette?",
                isPresented: $showingRestoreOptions,
                titleVisibility: .visible
            ) {
                Button("Alt fra backup") {
                    restoreScope = .everything
                    isImportingBackup = true
                }

                Button("Bare trekninger") {
                    restoreScope = .drawsOnly
                    isImportingBackup = true
                }

                Button("Avbryt", role: .cancel) { }
            } message: {
                Text("Alt erstatter data og innstillinger på denne enheten. Bare trekninger beholder egne rekker og innstillinger.")
            }
            .fileExporter(
                isPresented: $isExportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFileName
            ) { result in
                switch result {
                case .success:
                    showAlert(title: "Backup", message: "Backup ble eksportert.")
                case .failure(let error):
                    showAlert(title: "Feil", message: "Kunne ikke eksportere backup: \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $isImportingBackup,
                allowedContentTypes: [.json]
            ) { result in
                restoreBackup(from: result)
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingOwnGamesReset) {
                LotteryOwnGamesResetView(settings: LottoBackupSettings(
                    tolerance: toleranse, appearanceModeRawValue: appearanceMode.rawValue,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage,
                    weeklyRegisteredRows: UserDefaults.standard.string(forKey: WeeklyLotteryDelivery.storageKey) ?? "",
                    lottoTransferredRows: UserDefaults.standard.string(forKey: "transferredResultKeys") ?? ""))
            }
            .sheet(isPresented: $showingDuplicateCleanup) {
                LotteryDuplicateCleanupView(settings: LottoBackupSettings(
                    tolerance: toleranse, appearanceModeRawValue: appearanceMode.rawValue,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage,
                    weeklyRegisteredRows: UserDefaults.standard.string(forKey: WeeklyLotteryDelivery.storageKey) ?? "",
                    lottoTransferredRows: UserDefaults.standard.string(forKey: "transferredResultKeys") ?? ""))
            }
            .sheet(isPresented: $showingPrivacy) { LottoPrivacyView() }
            .sheet(isPresented: $showingManual) {
                LottoManualView()
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }

    private var toleranceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        return formatter
    }

    @MainActor
    private func exportBackup(scope: BackupExportScope) {
        do {
            let settings: LottoBackupSettings
            let content: LottoBackupContent

            switch scope {
            case .everything:
                settings = LottoBackupSettings(
                    tolerance: toleranse,
                    appearanceModeRawValue: appearanceMode.rawValue,
                    excludeHighestGapFromAverage: excludeHighestGapFromAverage,
                    weeklyRegisteredRows: UserDefaults.standard.string(forKey: WeeklyLotteryDelivery.storageKey) ?? "",
                    lottoTransferredRows: UserDefaults.standard.string(forKey: "transferredResultKeys") ?? ""
                )
                content = .everything
            case .drawsOnly:
                settings = LottoBackupSettings(
                    tolerance: 0,
                    appearanceModeRawValue: AppearanceMode.system.rawValue,
                    excludeHighestGapFromAverage: false
                )
                content = .drawsOnly
            }

            let snapshot = try LottoBackupStore.snapshot(context: context, content: content, settings: settings)

            backupDocument = LottoBackupDocument(snapshot: snapshot)
            let filePrefix = scope == .everything ? "Lotto-backup" : "Lotto-trekninger"
            backupFileName = "\(filePrefix)-\(Date.now.formatted(.iso8601.year().month().day())).json"
            isExportingBackup = true
        } catch {
            showAlert(title: "Feil", message: "Kunne ikke lage backup: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func restoreBackup(from result: Swift.Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LottoBackupSnapshot.self, from: data)

            if snapshot.content == .drawsOnly && restoreScope != .verify {
                let result = try importDraws(from: snapshot)
                showAlert(title: "Trekninger", message: result)
                return
            }

            switch restoreScope {
            case .verify:
                let checked = try LottoBackupStore.check(snapshot)
                showAlert(title: "Backupkontroll", message: checked.message)
            case .everything:
                try restoreEverything(from: snapshot)
                let warnings = LottoBackupStore.personalRowWarnings(snapshot)
                let description = warnings.count == 1 ? "Én eldre rekke bør kontrolleres. Den er beholdt uendret." : "\(warnings.count) eldre rekker bør kontrolleres. De er beholdt uendret."
                let note = warnings.isEmpty ? "" : "\n\n" + description + "\n" + warnings.prefix(3).joined(separator: "\n")
                showAlert(title: "Backup", message: "Hele backupen ble gjenopprettet." + note)
            case .drawsOnly:
                let result = try importDraws(from: snapshot)
                showAlert(title: "Trekninger", message: result)
            }
        } catch {
            context.rollback()
            let operation = restoreScope == .verify ? "kontrollere" : "gjenopprette"
            showAlert(title: "Feil", message: "Kunne ikke \(operation) backup: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func restoreEverything(from snapshot: LottoBackupSnapshot) throws {
        try LottoBackupStore.restoreEverything(snapshot, context: context)
        if let marks = snapshot.settings.weeklyRegisteredRows { UserDefaults.standard.set(marks, forKey: WeeklyLotteryDelivery.storageKey) }
        if let marks = snapshot.settings.lottoTransferredRows { UserDefaults.standard.set(marks, forKey: "transferredResultKeys") }
        toleranse = snapshot.settings.tolerance
        appearanceMode = AppearanceMode(rawValue: snapshot.settings.appearanceModeRawValue) ?? .system
        excludeHighestGapFromAverage = snapshot.settings.excludeHighestGapFromAverage
    }

    @MainActor
    private func importDraws(from snapshot: LottoBackupSnapshot) throws -> String {
        let result = try LottoBackupStore.importDraws(snapshot, context: context)
        if result.conflicts == 0 {
            return "\(result.added) nye trekninger ble importert. Egne rekker og innstillinger ble beholdt."
        }
        return "\(result.added) nye trekninger ble importert. \(result.conflicts) konflikter ble hoppet over. Egne rekker og innstillinger ble beholdt."
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    @MainActor
    private func updateDraws() async {
        isUpdatingDraws = true
        defer { isUpdatingDraws = false }

        do {
            let result = try await LottoDrawUpdater.update(modelContext: context)
            let message = result.addedCount == 0
                ? "Alle tilgjengelige trekninger er allerede oppdatert."
                : "La til \(result.addedCount) nye trekninger."
            showAlert(title: "Trekninger", message: message)
        } catch {
            showAlert(
                title: "Kunne ikke oppdatere",
                message: "Kontroller internettforbindelsen og prøv igjen. \(error.localizedDescription)"
            )
        }
    }
}

private struct LottoManualView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    manualSection(
                        title: "Om appen og ansvarlig bruk",
                        lines: [
                            "Appen er et uavhengig verktøy for historikk, statistikk, egne rekker og oversikt over innsats og gevinster i Lotto, Vikinglotto og Eurojackpot. Den selger ikke spill, tar ikke imot innsatser og betaler ikke ut gevinster.",
                            "Appen inneholder ikke reklame. Utvikleren mottar ikke reklameinntekter eller provisjon fra Norsk Tipping. Appen er ikke tilknyttet eller godkjent av Norsk Tipping.",
                            "Statistikk og favoritttall øker ikke sjansen for at en enkeltrekke vinner. Historiske intervaller og mønstre forutsier ikke neste trekning. Alle gyldige enkeltrekker i samme spill har lik sjanse.",
                            "Flere ulike rekker koster mer. Selv mange rekker gir ingen garanti for gevinst, og du kan tape hele innsatsen. En premie betyr ikke nødvendigvis at du har spilt med overskudd."
                        ]
                    )

                    manualSection(
                        title: "Lagre rekker og markere Levert",
                        lines: [
                            "Velg spill og riktig trekningsdato før du lagrer tallene. Lotto trekkes lørdag, Vikinglotto onsdag og Eurojackpot tirsdag og fredag.",
                            "Lagre oppretter en rekke i appen. Det er ikke innlevering eller betaling hos Norsk Tipping. Ny rekke åpner registreringsskjermen for kontroll og lagring, ikke en kjøpsflyt.",
                            "Merk en rekke som Levert / registrert hos Norsk Tipping i Ukesrapport først når du faktisk har levert den der. Du kan fjerne markeringen ved feil. Lagrede forslag blir ikke automatisk regnet som kjøpt.",
                            "Én unik rekke per spill og trekningsdato telles én gang. Har du kjøpt samme rekke flere ganger, føres den ekstra innsatsen og eventuell ekstra gevinst manuelt i Spilleoversikt. Unngå dobbeltføring."
                        ]
                    )

                    manualSection(
                        title: "Kontroll mot riktig trekning",
                        lines: [
                            "Alle tre spill har Ny rekke, Forslag og Statistikk på forsiden, samt antall lagrede trekninger, siste trekningsdato og Hent nye trekninger.",
                            "Mine rekker har et eget valg for Trekningsdato og viser bare rekker for valgt dato i alle tre spill. Trekninger viser den offisielle historikken separat. I Lotto gir Liste og eksport tilgang til utskrift og eksport, mens Kontroller dine rekker åpner den utvidede vinnerkontrollen.",
                            "Treff beregnes mot lagret resultat for samme spill og dato. Rekker uten resultat venter på trekningen. Kontroller alltid endelig gevinst hos Norsk Tipping."
                        ]
                    )

                    manualSection(
                        title: "Pris og vinnersjanse",
                        lines: [
                            "Ved registrering, forslag og systemspill vises antall enkeltrekker, beregnet pris og teoretisk vinnersjanse for én trekning etter dagens regler. Pris må kontrolleres hos Norsk Tipping.",
                            "Førstepremie og ordinær premie vises hver for seg, som prosent og omtrent 1 av et antall muligheter. Førstepremie betyr å få del i førstepremiegruppen; det er ingen garanti for å vinne hele potten alene.",
                            "For vanlige forslag vises samlet førstepremiesjanse for ulike rekker, men ordinær premiesjanse per enkeltrekke. Ordinære premiesjanser kan ikke bare ganges med antall rekker, fordi rekkene kan dele tall.",
                            "For et fullt system vises førstepremiesjanse og sjansen for minst én ordinær premie for hele systemet. Beregningen tar hensyn til overlapp mellom delrekkene. Supertrekning, nasjonale tilleggstrekninger og Joker er ikke inkludert."
                        ]
                    )

                    manualSection(
                        title: "Systemspill",
                        lines: [
                            "Åpne Systemspill. Velg spill, trekningsdato, antall hovedtall og eventuelle tilleggstall. Velg deretter de faktiske tallene. Antall enkeltrekker følger av alle kombinasjonene; pris og sjanse oppdateres når antall tall endres.",
                            "Appen støtter fulle systemer med inntil 2000 enkeltrekker. Lotto bruker 8–12 tall. Vikinglotto bruker 6–12 hovedtall og 1–5 vikingtall. Eurojackpot-beregneren bruker 5–10 hovedtall og 2–12 stjernetall. Minst én tallgruppe må være større enn i en vanlig rekke.",
                            "Lagre systemet lagrer nye delrekker og merker både nye og allerede eksisterende delrekker med hele systemtallutvalget. Overlapp telles ikke dobbelt. Tallutvalget vises i Ukesrapport og sist lagrede utvalg beholdes i Systemspill. Levering og betaling skjer hos Norsk Tipping.",
                            "Hver delrekke kan få sin ordinære premie. Et system kan derfor ha flere premier i ulike premiegrupper, som summeres i gevinstoversikten. Reduserte systemer, garantier og andelsfordeling støttes ikke. Beregneren lover ikke at alle kombinasjoner kan kjøpes som et enkelt system hos Norsk Tipping."
                        ]
                    )

                    manualSection(
                        title: "Mine gevinster",
                        lines: [
                            "Åpne Mine gevinster, velg Fra og Til og med, og eventuelt ett spill. Listen viser dine unike, leverte rekker med kjent ordinær gevinst, med beløp, antall gevinstrekker og sum.",
                            "Oppdater premier henter ferdigbehandlede premiebeløp. Manglende resultat eller premie vises som ventende, ikke som en bekreftet gevinst på null kroner.",
                            "Manuelle beløp, Joker og nasjonale tilleggstrekninger inngår ikke i denne listen. Før disse manuelt i Spilleoversikt, og kontroller alltid beløpene mot Norsk Tipping."
                        ]
                    )

                    manualSection(
                        title: "Spilleoversikt og månedsbeløp",
                        lines: [
                            "Spilleoversikt samler automatisk innsats fra Levert-markeringene og manuelle poster. Velg en dato i måneden du vil undersøke. Du ser innsats, registrert eller beregnet gevinst og netto. Uavklarte premier gjør netto foreløpig.",
                            "Innsats og årsbeløp viser registrert innsats til nå i valgt måned, endring fra måneden før, samme månedsbeløp ganget med 12 og faktisk registrert innsats i valgt kalenderår. Fremtidige trekningsdatoer er utelatt fra disse innsatsberegningene.",
                            "Årsbeløpet er en sammenligning, ikke en prognose for resten av året. En påbegynt måned er ikke direkte sammenlignbar med en hel måned. Gevinster trekkes ikke fra innsatsen i innsatskurven."
                        ]
                    )

                    manualSection(
                        title: "Prøv lavere innsats og les kurven",
                        lines: [
                            "Glidebryteren Prøv lavere innsats lar deg redusere valgt måneds registrerte innsats med 0–100 prosent. Beløpene viser lavere månedsnivå, tilsvarende årsbeløp og hvor mye mindre innsats det blir per måned og over 12 måneder.",
                            "Eksempel: 1000 kr per måned tilsvarer 12000 kr over 12 måneder. Med 25 prosent lavere innsats blir det 750 kr per måned, 9000 kr over 12 måneder og 3000 kr mindre innsats.",
                            "Glidebryteren endrer ikke historikken, faktisk levering eller månedsgrensen. Den anslår heller ikke fremtidige gevinster.",
                            "Kurven viser registrert innsats i de 12 månedene fram til valgt måned. Stiplet linje viser det lavere månedsnivået du prøver. Åpne Månedsbeløp og endring i kroner for listen med månedssummer og opp- eller nedgang. Null betyr ingen registrert innsats, ikke nødvendigvis at du ikke har spilt."
                        ]
                    )

                    manualSection(
                        title: "Månedsgrense og oversiktens begrensninger",
                        lines: [
                            "Du kan sette en egen månedsgrense i Spilleoversikt. Den sammenlignes med samlet registrert innsats før gevinster trekkes fra og gir en påminnelse når grensen er nådd.",
                            "Grensen stopper ikke spill hos Norsk Tipping og lagres på denne enheten. Oversikten blir bare så komplett som leveringsmarkeringene og de manuelle postene dine. Den er ikke en automatisk kopi av spillkontoen din.",
                            "Ta gjerne en pause. Spill bare for penger du har råd til å tape, og ikke spill for å vinne tilbake tap. Lenken Spillevett hos Norsk Tipping finnes i Spilleoversikt."
                        ]
                    )

                    manualSection(
                        title: "Statistikk, forslag og favoritttall",
                        lines: [
                            "Statistikken viser frekvens, intervaller og historiske trekninger. Forslag kan bygge på historiske intervaller, samme ukenummer i tidligere år, frekvens eller tilfeldig variasjon. Intervalltreff er en beskrivelse av historikken, ikke en prognose.",
                            "Favoritttall er valgfritt. Når funksjonen er på, brukes favorittene i én ekstra favorittrekke i tillegg til antallet forslag du velger. Manglende tall fylles inn, og like rekker tas ikke med to ganger. Ingen modus eller favoritt gir høyere vinnersjanse for en enkeltrekke.",
                            "Lagre lagrer et forslag i appen. Kontroller / endre eller Levere åpner rekken for kontroll før lagring. Print eller deling lager en rapport, ikke en innlevering."
                        ]
                    )

                    manualSection(
                        title: "Endre og slette registreringer",
                        lines: [
                            "Mine registreringer på forsiden samler egne rekker, systemspill og manuelle poster. Velg måned og eventuelt spill. Offisielle trekninger endres ikke her.",
                            "Endre rekke korrigerer tall eller trekningsdato. En eventuell Levert-markering flyttes til den korrigerte rekken, slik at innsatsen ikke telles dobbelt. En endret delrekke frikobles fra systemet.",
                            "Endre system erstatter hele systemet. Delrekker som er del av andre systemer beholdes. Øvrige gamle delrekker fjernes, også om de først ble lagret enkeltvis. Nye delrekker får ingen ny Levert-markering. Du velger om gamle leveringsmarkeringer skal fjernes.",
                            "Ved sletting velger du mellom å bare fjerne lagrede rekker og å også fjerne Levert. Fjerner du Levert, tas beregnet innsats og gevinst ut av Spilleoversikt. Manuelle beløp kan endres eller slettes separat.",
                            "Endringer gjelder andre enheter via iCloud. Ta en full sikkerhetskopi før større opprydding. Ingen av disse handlingene endrer faktisk innleverte spill hos Norsk Tipping."
                        ]
                    )

                    manualSection(
                        title: "Ukesrapport, eksport og backup",
                        lines: [
                            "Ukesrapport samler rekker for valgt uke og spill. Lever alle merker alle ikke-leverte rekker i denne uken og valgte spill etter en bekreftelse. Det sender ikke spill til Norsk Tipping. Du kan velge rekker, markere dem som faktisk levert og eksportere eller skrive ut en oversikt. Nye systemers delrekker merkes med det opprinnelige tallutvalget. Hele systemet vises i rapporten og i en egen oversikt bakerst i PDF-utskriften. Excel har en kolonne med systemtall.",
                            "Lotto-listen kan eksporteres som CSV til regneark eller TXT til tekstbehandling. Valgte rekker brukes ved eksport; uten valg brukes rekkene i gjeldende filter.",
                            "Full sikkerhetskopi inneholder trekninger, egne rekker, leveringsmarkeringer, favoritter, manuelle spilleposter og innstillinger. Bare trekninger er et eget begrenset eksportvalg. Ta en full kopi før større endringer.",
                            "Offentlige premietabeller lagres lokalt og hentes på nytt på andre enheter. Påminnelsen om månedsgrense er lokal. Eksporterte filer må du selv oppbevare og dele på en trygg måte."
                        ]
                    )

                    manualSection(
                        title: "Systemtall og systemforslag",
                        lines: [
                            "Systemspill kan foreslå et tallutvalg basert på historisk frekvens eller et tilfeldig utvalg. Du kan endre tallene selv før lagring. Ingen metode gjør neste trekning mer forutsigbar.",
                            "Siste lagrede systemtall beholdes på denne enheten når du åpner Systemspill igjen. Ukesrapporten viser hele systemtallutvalget og merker delrekkene. En rekke kan være del av flere systemer, men samme rekke på samme dato telles bare én gang.",
                            "Eldre systemer ble lagret som enkeltrekker uten systeminformasjon, og kan ikke merkes sikkert i ettertid. Du kan registrere det opprinnelige systemtallutvalget på samme dato igjen: da merkes eksisterende delrekker uten å lage dubletter."
                        ]
                    )

                    manualSection(
                        title: "Start på nytt med egne spill",
                        lines: [
                            "Velg Innstillinger → Vedlikehold → Start på nytt med egne spill. Lag og kontroller full backup først. Du kan lagre eller dele filen utenfor appen før du fortsetter.",
                            "Etter egen bekreftelse fjernes egne rekker, systemenes delrekker, Levert-markeringer og manuelle innsatser og gevinster. Offisielle trekninger, tallstatistikk, favoritter og innstillinger beholdes.",
                            "Nullstillingen gjelder også andre enheter med samme Apple-konto via iCloud. La enhetene synkronisere først, og unngå samtidige endringer. Usynkroniserte spill på en frakoblet enhet kan komme tilbake senere. For å angre må du gjenopprette hele backupen."
                        ]
                    )

                    manualSection(
                        title: "iCloud og dubletter",
                        lines: [
                            "Når iCloud er tilgjengelig, kan appdata synkroniseres mellom enheter. Synkronisering kan ta tid. Kontroller at riktige rekker og leveringsmarkeringer er kommet fram før du stoler på oversikten på en annen enhet.",
                            "Appen forebygger og rydder dubletter. Sletting av en lagret rekke fjerner ikke automatisk historikken over det du har merket som levert. Korriger feil markering i Spilleoversikt."
                        ]
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Brukermanual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ferdig") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func manualSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    SettingsView(toleranse: .constant(4.0))
}
