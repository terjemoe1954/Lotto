# Forslag og systemmerking

## Forslagskontroll

Tidligere kode valgte de numerisk laveste intervalltreffene som startrekke og beskyttet de første (laveste) tallene ved variasjon. Reserveutfylling begynte også ved 1. Dette kunne holde 1, 2 og 3 i mange rekker selv når mange kandidater hadde lik vurdering. Historikk/frekvens alene forklarte derfor ikke hele likheten.

Ny kode vekter fortsatt intervalltreff, samme ISO-uke og frekvens etter valgt modus, men bruker vektet tilfeldig utvalg uten tilbakelegging og tilfeldig rekkefølge ved lik score. Favorittrekke beholdes som ett eget forslag. Den første historisk vektede rekken bruker de høyest rangerte tallene; resten varierer, og rekker med seks felles tall avvises normalt. Ingen påstand om økt faktisk vinnersjanse. Historikk fra mål-datoen eller senere filtreres bort i motoren.

## Systemer

Valgfri systemMembershipJSON-attributt på Result og InternationalLotteryEntry bevarer spill, dato og hele tallutvalget per delrekke. Stabil identitet basert på spill/dato/tall gjør gjentatt lagring idempotent. Overlappende eksisterende enkeltrekker får systemmerking; de lagres ikke dobbelt og innsats/gevinst følger samme unike rad-ID som før. Én delrekke kan høre til flere systemer.

Ukesrapporten viser systemoversikt og merking. PDF legger til paginerte systemoversikter og S-referanser på delrekkene; Excel har Systemtall-kolonne. Backupens valgfrie felt bevarer metadata, også når dubletter slås sammen. Nullstilling fjerner delrekkene og lokal gjenkalling av siste systemutvalg. Eldre rekker/backuper har nil som før; gamle systemer utledes ikke automatisk. Ny lagring av det opprinnelige utvalget på samme dato kan merke gamle delrekker uten dubletter.

Systemspill kan foreslå valgt antall tall med historisk frekvens eller lik tilfeldig vekt, og siste lagrede tallutvalg per spill beholdes lokalt ved gjenåpning. Delrekker og deres systemmerking ligger i vanlig datamodell for backup og iCloud. De to nye valgfrie CloudKit-attributtene må kontrolleres i utviklings- og produksjonsskjema før en ny TestFlight-distribusjon; denne oppgaven har ikke distribuert eller endret produksjonsskjema.

## Validering

124 tester i 23 suiter bestod. Dekker lik-score uten låsing til 1/2/3, historisk vekting, fremtidige trekninger, overlappende systemer uten ekstra innsats, backup/gjenoppretting, nullstilling og dublettrydding med systemmetadata. Simulator viser forslag med korrekt hoved-/tilleggstallantall og aktiv lagringsknapp; ingen testspill lagret i brukerens database. PDF med flere systemoversiktssider og store tallutvalg er rendret og visuelt kontrollert med Poppler og PDFKit. Excel-kolonne og XML-dimensjon kontrollert.

Endringen er lokal og opplastet TestFlight 1.1 (14) er uendret.

## Ekstra favorittrekke

Antallet brukeren velger gjelder vanlige forslag. Aktive favoritttall gir én ekstra, unik favorittrekke i Lotto, Vikinglotto og Eurojackpot. Delvise favoritter kompletteres som før. Pris og vinnersjanse bruker samlet antall rekker. Ingen ekstra rekke når favoritter er tomme eller deaktivert. Brukermanual og antallsforklaring er oppdatert.
