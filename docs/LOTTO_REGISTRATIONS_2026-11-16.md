# Ukerapport og egne registreringer – build 16

Ukerapporten henter bare egne rekker i valgt ISO-uke. Rekkegrunnlaget bygges separat fra leveringsmarkeringene, og leveringsstatus beregnes én gang per render. Enkeltmarkering henter bare tilhørende endringer; massemarkering bruker én innlesing og lagring, uten et stort IN-uttrykk. Systemets antall rekker beregnes kombinatorisk uten å generere alle kombinasjonene.

Lever alle gjelder ikke-leverte rekker i valgt uke og valgte spill. Bekreftelsen forklarer iCloud og automatisk innsats. Dette sender aldri inn spill til Norsk Tipping.

Mine registreringer på forsiden samler egne rekker, systemer, tidligere leverte rekker og manuelle poster med måneds- og spillfilter. En korreksjon flytter levertmarkeringen til ny rad-ID i samme lagring. Endret systemkomponent frikobles fra systemet. Ved endring av helt system bevares delrekker som tilhører andre systemer; øvrige gamle delrekker fjernes etter tydelig bekreftelse. Brukeren velger om gamle leveringer skal fjernes. Nye delrekker får ingen nye leveringsmarkeringer. Ved sletting velger brukeren mellom bare lagrede rekker og også leveringshistorikk. Offisielle trekninger berøres ikke.

Ingen nye datamodeller eller CloudKit-felter. Brukermanualen er oppdatert.

Validering: 131 tester i 24 suiter passerte. De 7 registreringstestene passerte også etter isolering av lokale testinnstillinger. 792 markeringer i isolert database tok 0,036–0,041 sekunder. Ingen brukerregistreringer endret eller slettet ved testing.

Visuell kontroll: installert uten avinstallering og startet på iPad Pro 13-inch (M5), UDID 11D4D75C-A33C-49F1-AE17-EB2CBC53AA44. Forsiden og nye Mine registreringer-knappen er synlige. Device Hub returnerte ikke appens tilgjengelighetselementer og automatiske trykk åpnet ikke skjermen, heller ikke etter ny tilkobling. Full interaktiv kontroll er derfor ikke bekreftet og må testes på fysiske enheter. Simulatoren ble ikke nullstilt eller stoppet.
