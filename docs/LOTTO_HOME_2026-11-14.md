# Felles forside for Lotto

Lotto bruker samme listeoppsett og delte handlingskomponent som Vikinglotto og Eurojackpot: Ny rekke, Forslag og Statistikk, deretter lagrede trekninger, siste trekningsdato og Hent nye trekninger. Mine rekker filtreres på valgt trekningsdato, standard siste lagrede trekning. Treff bruker eksisterende LottoWinnerLogic. Trekninger vises separat. Liste og eksport, utvidet vinnerkontroll og manuell trekningsregistrering beholdes.

Spillvelgeren viser Bytter spill … før ny forside konstrueres. Task-kansellering hindrer eldre spillvalg i å overstyre siste valg. Henting av resultater har egen Oppdaterer …-indikator. Lotto-listens sortering slår opp gjeldende trekning én gang i stedet for å bygge trekningsindeksen for hver sammenligning.

Kontroll: 115 eksisterende tester bestod etter forsideendringen. Endelig bygg med spillbytteindikator og manualtekst bygget uten feil. iPhone 17: observerte Bytter spill …, ny Lotto-forside, Ny rekke og tilbake uten lagring, datofilter og eksportknapper. iPad Pro 13-inch (M5): kontrollert layout og bytte fra Mine rekker til Trekninger. Ingen egne brukerdata slettet under kontrollen.

Endringen finnes i lokal kildekode og simulatorer. Allerede opplastet TestFlight 1.1 (12) er uendret.
