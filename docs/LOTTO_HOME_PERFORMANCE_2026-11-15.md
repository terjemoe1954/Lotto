# Heng ved spillbytte og avslutning, build 13

Brukerrapport: tregt spillbytte på iPhone/iPad, arbeidsindikator kom sent. Ved å sveipe appen bort kom TestFlight-krasjmelding etter omtrent ti sekunder. Det ble verre etter ny Lotto-forside. Ingen tilgjengelig krasjrapport i Xcode Organizer ved kontroll; den eksakte avslutningsfeilen er ikke bekreftet.

Bekreftede kodeproblemer: gjentatte fullarkivfiltreringer i egne radfiltre og sorteringssammenligninger; innlesing av grunnarkiv ved gjenoppretting av spillvisninger; ikke-sporede oppdateringsoppgaver startet av sceneendringer; normalisering av gamle leveringsmarkeringer direkte i forsidevisningens task-identitet.

Rettelse: InternationalHomeSnapshot og LottoHomeSnapshot bygger én indeks og beregner treff én gang per aktuell visning. Arkiver klargjøres fra appens rot én gang per økt. Automatisk henting styres av aktiv scene og kanselleres ved bakgrunn. Manuelle henter kanselleres når visningen forsvinner eller appen blir inaktiv. Henter kontrollerer kansellering før arbeid og etter nettverk før databaseendringer. Ingen nye SwiftData/CloudKit-modeller.

Spillvelgeren setter arbeidsindikatoren i selve bindingssetteren, før tasken oppretter neste spillvisning. Gamle leveringsmarkeringer behandles i en isolert hjelpevisning, slik at spillvelgerens og fremdriftsindikatorens tilstand ikke trenger å bygge ukesrapporten.

Validering: 119 tester i 22 suiter bestod. Store isolerte datasett med omtrent 2000 egne rekker kontrollerer rett spill/dato, treffsortering, manglende trekninger og årsskille. Kansellerte nasjonale og internasjonale oppdateringer skal stoppe uten nettverk/fremdrift eller databaseendringer. Simulator: observerte bytte Lotto → Vikinglotto → Eurojackpot, Hjem og lukking fra appveksleren. Dette er ikke en TestFlight/iCloud-test på fysisk enhet; den rapporterte krasjmeldingen er fortsatt ubekreftet.

Rettelsen er lokal. Opplastet TestFlight 1.1 (13) er uendret og må erstattes med en ny build for fysisk retest.
