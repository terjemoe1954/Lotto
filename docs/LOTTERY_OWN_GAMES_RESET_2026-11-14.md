# Start på nytt med egne spill

Tilgjengelig i Innstillinger → Vedlikehold. Full JSON-backup skrives atomisk til Dokumenter/Lotto-backups, leses tilbake og prøvegjenopprettes i isolert database før bekreftelse tillates. Delingsknappen lar brukeren lagre kopien utenfor appen.

Etter iCloud-bekreftelse og en separat destruktiv bekreftelse slettes Result, internasjonale egne rekker (ikke isDraw) og manuelle spilleposter individuelt. Nye falske leveringshendelser bevares for å overstyre eldre positive hendelser fra iCloud. Eldre lokale leveringsnøkler tømmes etter vellykket lagring. Ved lagringsfeil rulles databaseendringene tilbake.

JackPot, internasjonale trekninger, favoritter, innstillinger og eksisterende backupfiler beholdes. Spillehistorikkens gevinster og beløp begynner på nytt; tallstatistikk basert på trekninger beholdes.

Før sletting kontrolleres backupfilen på nytt og hele den nåværende lokale backuprepresentasjonen sammenlignes med den kontrollerte kopien, uten eksporttid og uten å være avhengig av fetch-rekkefølge. Endringer etter backup krever ny backup.

CloudKit-slettinger synkroniseres til samme Apple-kontos enheter. Dette er ikke en global atomisk sletting av data som aldri har nådd denne enheten: frakoblede enheter kan ha usynkroniserte nye spill. Grensesnitt og manual forklarer at alle enhetene bør synkronisere først og at samtidige endringer bør unngås.

Nullstillingen testes kun mot isolerte minnedatabaser. Brukerens egne spill skal ikke nullstilles under UI-kontrollen. Endringen finnes i lokal kildekode og simulatorbygg; opplastet TestFlight 1.1 (11) er uendret.
