import SwiftUI

/// Keep the in-app policy and the hosting-ready copy in docs/privacy.html aligned.
enum LottoPrivacyContent {
    static let contactEmail = "terjemoe54@hotmail.com"
    static let updated = "10. november 2026"
    static let sections: [(title: String, body: String)] = [
        ("Om appen", "Lotto er en uavhengig app for statistikk, historiske trekninger og oversikt over egne rekker. Appen øker ikke vinnersjansene dine og selger ikke lodd eller kuponger. Utgiver er Terje Moe."),
        ("Lagring på enheten", "Egne rekker, favoritttall, registreringsmarkeringer, spilleoversikt (innsats, gevinst og merknader) og trekningshistorikk lagres i appens database. Offentlige premietabeller mellomlagres lokalt for automatisk gevinstberegning. Visningsvalg og enkelte innstillinger lagres lokalt i appens innstillinger."),
        ("iCloud", "Når iCloud er tilgjengelig, kan appens database synkroniseres mellom enhetene dine via din private iCloud-database hos Apple. Dette omfatter egne rekker, favoritter, registreringsmarkeringer og spilleoversikt. Trekningshistorikk inngår også i det eksisterende datalageret. Apple behandler iCloud-kontoen og tjenesten etter sine vilkår og sin personvernerklæring. Appen har ingen egen brukerkonto eller passordinnlogging."),
        ("Resultater fra Norsk Tipping", "Appen henter offentlige trekningsresultater fra Norsk Tippings tjenester. Forespørslene inneholder spilltype og datointervall. Egne rekker, favoritttall og registreringsmarkeringer sendes ikke til Norsk Tipping av resultatoppdateringen. Nettjenesten mottar vanlig tilkoblingsinformasjon, som IP-adresse. Åpner du Norsk Tippings nettside, gjelder deres vilkår og personvernerklæring for besøket."),
        ("Sporing og reklame", "Appen inneholder ikke reklame, tredjeparts analyse-SDK-er eller sporing på tvers av apper og nettsteder. Appen har ingen egen server som mottar rekkene eller favorittene dine. Apples plattformtjenester og Norsk Tippings tjenester behandler informasjon etter sine egne retningslinjer."),
        ("Backup og deling", "Du velger selv hvor eksporterte backupfiler, regneark og rapporter lagres, og hvem du deler dem med. Filer kan inneholde egne rekker, favoritter, registreringsstatus og spilleoversikt. Kontroller backupfil prøvegjenoppretter filen i en separat lokal testdatabase; kontrollen laster ikke innholdet opp til en tjeneste."),
        ("Endring og sletting", "Du kan slette egne rekker og endre favoritter i appen. Endringer kan synkroniseres med iCloud. Endringshistorikk kan beholdes i databasen for å håndtere synkronisering, inkludert fjerning av avhukinger. Sletting av appen fjerner ikke nødvendigvis iCloud-data eller filer du har eksportert. iCloud-data administreres i Apples iCloud-innstillinger, og eksporterte filer administreres der du har lagret dem."),
        ("Kontakt", "Spørsmål om appen og personvern kan sendes til \(contactEmail). Hvis du sender en e-post, mottar utgiver adressen og innholdet du velger å sende for å besvare henvendelsen. Slike henvendelser beholdes så lenge det er nødvendig for oppfølging og eventuelle plikter. Du kan kontakte utgiver om innsyn, retting eller sletting av opplysninger du har sendt."),
        ("Endringer i teksten", "Denne informasjonen oppdateres dersom appens databehandling endres. Sist oppdatert: \(updated).")
    ]
}

struct LottoPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(LottoPrivacyContent.sections.enumerated()), id: \.offset) { _, section in
                    Section(section.title) { Text(section.body).font(.body) }
                }
                Section("Kontakt og kilder") {
                    Link(LottoPrivacyContent.contactEmail, destination: URL(string: "mailto:\(LottoPrivacyContent.contactEmail)")!)
                    Link("Apples personvernerklæring", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                    Link("Norsk Tipping", destination: URL(string: "https://www.norsk-tipping.no/")!)
                }
            }
            .navigationTitle("Personvern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } } }
        }
    }
}
