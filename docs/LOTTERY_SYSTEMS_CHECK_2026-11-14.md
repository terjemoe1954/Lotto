# Kontroll 14. november 2026

- Debug-bygg: bestått, Xcode-skjema Lotto, DerivedData /private/tmp/Lotto-Systems.
- Testpakke: 106 tester i 18 suiter bestod. Inkluderer 4 nye systemtester: offisielle rekkeantall/grenser, Lotto 9-talls gevinstfordeling (1 andre-, 2 tredje-, 18 fjerde- og 15 femtepremier), Eurojackpot 7+2 / dato-isolasjon, og duplikatfri lagring i SwiftData.
- Resultatpakke: /private/tmp/Lotto-Systems/Logs/Test/Test-Lotto-2026.11.14_07-45-27-+0100.xcresult
- iPhone 17 UDID 1AC5CF22-4235-4E14-B4E8-244FC3B74F2C klargjort med ensure_simulator; ingen avinstallasjon eller nullstilling.
- Device Hub: startknappene, Systemspill og Mine gevinster kontrollert med reell UI-navigasjon. System 8 viste 8 rekker / 40 kr; økning til 10 viste 120 rekker / 600 kr. Gevinstlisten viste fra-/til-dato, spillfilter, sum, vinnerantall og ventende premier. Vikinglotto viste Trekningsdato 2026-11-04 og teksten Bare dine rekker for valgt trekning vises.
- Ingen testrekker eller leveringsmarkeringer ble lagt til i brukerens simulator under UI-kontrollen. Lagring ble testet i separat minnedatabase.
- Ingen ny datamodell, endring av backupformat, produksjonsskjema, TestFlight eller App Store-innsending.

Begrensning: Fulle systemer lagres som enkeltrekker uten egen systemgruppe. Reduserte systemer og andelsfordeling er ikke støttet. Appens grense er 2000 kombinasjoner. Se README for kilder og støttede tallantall.
