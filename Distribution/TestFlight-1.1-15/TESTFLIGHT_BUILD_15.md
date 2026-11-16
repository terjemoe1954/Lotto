# Lotto 1.1 (15)

Opplastet til intern TestFlight 15. november 2026. Apple har fullført behandlingen. Build-ID: fc453297-b4ac-480c-bae5-71af4113e9b7.

Innhold: variertere vektede forslag, ekstra unik favorittrekke utover valgt antall forslag i alle tre spill, systemforslag og bevart systemutvalg, systemmerking av delrekker og oversikt i ukerapport/PDF/Excel, oppdatert brukermanual. Eksisterende rekker beholdes og telles bare én gang.

Validering: 124 tester i 23 suiter bestod. Release-arkiv og eksport lykkes, bundle com.terjemoe.Lotto, versjon 1.1, build 15, iPhone og iPad. Opplastingen lykkes.

iCloud: eksisterende utviklingsskjema eksportert før endring. Bare systemMembershipJSON (STRING med standardindekser) og tilhørende ckAsset-felt lagt til på CD_Result og CD_InternationalLotteryEntry. Ingen endrede roller eller dataleting. Import validert og produksjonsdistribusjon bekreftet i CloudKit Console. Fysisk synkronisering må testes på iPhone/iPad.

Testnotater er lagret. Brukeren godkjente eksplisitt krypteringserklæringen for build 15, og None of the algorithms mentioned above er lagret. App Store Connect bekreftet status Testing og gruppen Internal med én tester. Build 15 er tilgjengelig for intern testing på iPhone og iPad. Ingen ekstern eller App Store-innsending.
