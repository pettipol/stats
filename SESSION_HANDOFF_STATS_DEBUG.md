# Handoff — Debug Stats / StatsDebug (barra dei menu + crash)

> Sessione del **2026-07-01** (sera), macOS **26.5.1** (build 25F80), MacBook Pro **M4 Max** arm64.
> Documento di raccordo per **riprendere dopo il riavvio**. Tutti i path sono **assoluti**.
> Repo fork: `/Users/vittoriovillani/Code/stats` — branch `feature/usb-power-monitoring`
> (remotes: `origin` = github.com/pettipol/stats, `upstream` = github.com/exelban/stats).

---

## ✅ AGGIORNAMENTO 5 — 2026-07-02 (notte) — **RISOLTO E VALIDATO** — LEGGERE PER PRIMO

**Causa (alta confidenza, ricerca SOTA + verifica avversariale):** bug macOS 26 Tahoe = **wedge per-`CFBundleIdentifier`** tenuto in-memory da ControlCenter/WindowServer (NON su disco). Pinna certi bundle-id fuori barra (`button.window.screen==nil` → firma `(7, altezza_main−1)`). Refutati con prove locali: Bartender, geometria multi-display (3 setup identici), overflow/barra piena (screenshot con spazio libero), posizione salvata mancante (Backblaze la **ha** ed è orfano; Ollama/OneDrive **non** l'hanno e stanno in barra), API `.view` legacy (Stats usa `.button`), permesso "Menu Bar" (gli item esistono nell'AX tree → creati e permessi, solo non piazzati). Fonti: exelban/stats **#3120** (commento AndrewBeniston) + CodexBar **#802**. Il fork ha già il fix autosaveName **#2768** (`2a23ab84`).

**Fix applicato:**
1. Test no-compile decisivo: `Stats.app` 3.0.5 → cambiato solo `CFBundleIdentifier` → `eu.exelban.StatsDebug` + re-sign ad-hoc → **5 item a y=3** (in barra). Wedge confermato/aggirato.
2. **Rebuild pulito del fork**: rename consistente `eu.exelban.Stats*` → `eu.exelban.StatsDebug*` in `Stats.xcodeproj/project.pbxproj` (serve per `ValidateEmbeddedBinary`: appex Widgets + login item LaunchAtLogin devono essere prefissati dall'app; backup `Stats.xcodeproj/project.pbxproj.prewedge.bak`). Build `xcodebuild -scheme Stats -configuration Release CODE_SIGNING_ALLOWED=NO VALIDATE_PRODUCT=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64` → `codesign --force --deep --sign -` (ad-hoc, no hardened runtime → i moduli si caricano) → installato in **`/Applications/StatsDebug.app`** (ufficiale intatto).
3. **Barra OK**: 6 item tutti a y=3 (CPU/GPU/RAM/Rete/Batteria+USB/Disk). La tua feature USB (`Battery.swift`) mostra "USB: xx.xW".
4. **Patch crash Disk validato**: `Disk_state=true` → app viva, 0 crash report.
5. **Login item swappato** (System Events): rimosso "Stats", aggiunto "StatsDebug"; BTM ora solo `eu.exelban.StatsDebug`.

**Residui / prossimi passi:**
- Modifica USB `Kit/Widgets/Battery.swift` **non committata** → verificare rischio deadlock `queue.sync` **prima** di committare (pbxproj + Disk patch + Battery).
- Firma ad-hoc → **fan control** (helper SMC privilegiato, richiede OU=RP2S87B72W) non funziona; temperature/sensori sì.
- **Self-heal** (`screen==nil` → remove+recreate su `didChangeScreenParametersNotification`, come iStat Menus v7.2) NON aggiunto: enhancement opzionale anti-re-wedge futuro in `Kit/module/widget.swift`.
- **Backblaze** (`bzbmenu`) ancora orfano (closed source, non patchabile): serve **update client Backblaze**. Verificato che relaunch stesso bundle-id → ri-orfana subito.
- Verifica dopo il prossimo login: che parta `StatsDebug` (e non lo Stats ufficiale). In `StatsDebug → Impostazioni` puoi anche attivare "Avvia al login" (registrazione SMAppService pulita) e in *Impostazioni di Sistema → Generali → Elementi login* controllare che il vecchio Stats sia OFF.

---

## 🟢 AGGIORNAMENTO 3 — 2026-07-02 (Bartender era VIVO → ucciso → SCAGIONATO)

**Scoperta chiave**: la "disinstallazione" dell'AGGIORNAMENTO 2 aveva solo **spostato i file su disco**, **senza uccidere il processo**. Bartender 6 (**PID 20954**, avviato **11:53:22**, login item) **era ancora vivo**: su macOS un processo continua a girare anche se sposti il suo `.app` (segue l'inode → il path mostrava la cartella di backup). Riscriveva plist/caches (per questo `com.surteesstudios.Bartender.plist` "ricompariva"). Il `pkill` iniziale non l'aveva centrato.

**Azione**: `kill 20954` (morto, nessun respawn, nessun helper) + rimossi i file ricreati + **app rinominata `Bartender 6.app.DISABLED`** nel backup così LaunchServices **non può rilanciarla** al login. Sistema ora **realmente senza Bartender** (0 processi, 0 app, 0 config).

**TEST DECISIVO**: con Bartender davvero assente, **riavvio di Stats** (item creati da zero) → **6 item ANCORA orfani a `(7,1328)`**; Backblaze idem. 
➡️ **BARTENDER SCAGIONATO**: rimuoverlo/ucciderlo **non** risolve. Non era lui.

**Cosa resta (ipotesi forte)**: bug di **placement di macOS Tahoe** su **come Stats e Backblaze registrano gli `NSStatusItem`** — sospetto **API legacy `statusItem.view`** (custom NSView) invece di `statusItem.button`, che Tahoe non piazza correttamente. Spiega perché **solo** questi due (app "vecchie" con view custom) e non le 20 moderne. Abbiamo il **SORGENTE del fork** → indagabile/patchabile in codice. Lega a upstream #3120.

**Sulla ricerca "bartender" dell'utente**: i risultati erano (a) la cartella di **backup**; (b) **materiale suo in OneDrive** — installer `Bartender 6.dmg` (28 MB) + `Your Bartender5 License Key.pdf` (lasciati intatti); (c) file **non correlati** (audio Anki che dicono "bartender", invoice Outlook, icona cache Logi). **Nessun residuo-app attivo** fuori dal backup.

**PROSSIMO PASSO — il reboot ora è un test PULITO** (Bartender non può ripartire):
```
zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh
```
- Se dopo reboot Stats/Backblaze **compaiono** → Bartender aveva lasciato uno **stato di sistema** (visibilità item) che persisteva fino al riavvio: ora risolto dalla rimozione.
- Se **ancora orfani** → confermato **bug app/OS**: investigare nel **sorgente del fork** come vengono creati gli status item (cerca `statusItem.view` / `NSStatusItem` / `withLength` nei moduli e in `Kit/`), valutare migrazione a `.button` o workaround; allineare a #3120.

---

## 🔴 AGGIORNAMENTO 2 — 2026-07-02 (postazione nuova + DISINSTALLAZIONE Bartender)

**Nuovo setup hardware**: cambiata postazione → monitor esterno + iPad in Sidecar. Geometria: **main `2056×1329`** (barra qui) + Full HD `1920×1080` + iPad `1376×1032`, entrambi **a sinistra** (x negativa), senza barra. **Configurazione display completamente diversa** da quella del primo update.

**Esito (misura sul nuovo setup)**: Stats (×6) e Backblaze (×1) **di nuovo orfani** a **`(7,1328)`** (= angolo basso-sx del main, altezza−1). Verificate **20 app** in barra, incluse utility "monitor" simili (**CPU Temperature**, **Parallels Toolbox**): **tutte OK**. Orfani **esattamente e solo Stats + Backblaze**.

**Esclusioni ora DEFINITIVE (con prove su due setup diversi)**:
- ❌ **Geometria / multi-display**: cambiati tutti i monitor → sintomo **identico** (regola fissa `(7, altezza_main−1)`). L'obiezione dell'utente era corretta.
- ❌ **Overflow / barra piena**: 20 app entrano con spazio; se mancasse posto ne cadrebbe altre.
- ❌ **Posizione salvata di Stats**: nessuna chiave `NSStatusItem Preferred Position` né in prefs né in ByHost; item **freschi** rifiutati **da macOS**.
- ❌ **Bartender attivo**: **non** in esecuzione.
- ⚠️ **Unico indizio residuo**: il config di Bartender (`com.surteesstudios.Bartender.plist`) elencava **letteralmente i 6 item `eu.exelban.Stats-*` in `AlwaysHide`** (Backblaze **no** — ma Bartender 6 ha anche auto-hide degli item sconosciuti).

**AZIONE ESEGUITA — disinstallazione completa di Bartender 6 (reversibile)**: spostati in backup app + `com.surteesstudios.Bartender.plist` + Caches + HTTPStorages + Application Support (Bartender + revenuecat) + Group Container `24J875RH8J.com.surteesstudios.Bartender`. `killall cfprefsd`. 
- **Backup (86 MB)**: `/Users/vittoriovillani/Bartender6-uninstall-backup-2026-07-02/` — ripristino con `zsh /Users/vittoriovillani/Bartender6-uninstall-backup-2026-07-02/RESTORE.sh`.

**PROSSIMO PASSO — RIAVVIARE, poi misurare**:
```
zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh
```
- ✅ **Stats/Backblaze COMPAIONO** → era **stato/residuo di Bartender**: risolto dalla disinstallazione. Poi: in *Impostazioni di Sistema → Generali → Elementi login ed estensioni* rimuovere l'eventuale voce **login item orfana** di Bartender (registrazione BTM residua, innocua ma da ripulire). Decidere se ricompilare il fork con la patch Disk e riattivare Disk.
- ❌ **NON compaiono** → **Bartender definitivamente scagionato**: è un **bug di placement di macOS Tahoe** su certi item (Stats #3120). Se si rivuole Bartender: `RESTORE.sh`. Trattare a parte: declutter barra / attendere fix upstream / indagare lato Stats l'`autosaveName` e l'ordine di registrazione degli `NSStatusItem` (perché **proprio** Stats e Backblaze?).

**Script di misura**: aggiornato e reso display-agnostico → `/Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh`.

---

## AGGIORNAMENTO 1 — 2026-07-02 (primo post-riavvio, vecchia postazione 6K) — storico

> Superato dall'AGGIORNAMENTO 2 qui sopra (che scagiona anche la geometria multi-display). Conservato per tracciabilità.

**Esito del test previsto per ieri**: dopo il riavvio **con Bartender disabilitato**, gli item di Stats **NON compaiono** ancora in barra. La diagnosi è però **chiusa a livello di causa**.

**Non è Bartender, e Stats funziona.** Processi Bartender/NotchBar **assenti** (`pgrep`); gira **solo** `/Applications/Stats.app` (istanza singola) e **crea correttamente 6 status item** con dimensioni reali (44/57/37/71/71/71 px). Sono creati ma **non piazzati**: macOS Tahoe li scarica **fuori barra** a `(7,1691)`.

**Prova che scagiona Stats/fork (decisiva)**: enumerando gli status item di **tutti** i ~30 processi in barra, **Backblaze (`bzbmenu`)** è colpito in modo **identico** — unico item reale a `(7,1691)`, esattamente come i 6 di Stats. Due app **indipendenti** sulla stessa coordinata off-screen ⇒ **bug di layout barra a livello di sistema (macOS Tahoe 26.5.1)**, non di Stats né del fork. Riconducibile a upstream #3120.

**Geometria / coordinate (AX, origine alto-sx)**:
- Item "sani" delle altre ~25 app: in barra a `y≈3`, x da ~2705 fino a **4051** — cioè **oltre il bordo destro del 6K (x=3008)**, sopra il monitor verticale che **non ha barra**.
- Stats (×6) e Backblaze (×1): tutti a **`(7,1691)`** = angolo **basso-sinistra del 6K** (fuori barra).
- Display: **6K main** `(0,0) 3008×1692` (unico con barra); **SSN-24 verticale** `(3008,−228) 1080×1920` a destra, più alto, offset −228, **senza barra**.
- Meccanismo ipotizzato: macOS dispone gli status item su uno spazio-coordinate che **ingloba il secondario** (larghezza totale 4088), right-anchored; quelli che eccedono la regione **visibile** finiscono a `(7,1691)`.

**Test eseguiti (negativi sul fix, utili come esclusione)**:
- `killall ControlCenter` (con Bartender morto) → invariato, item ancora `(7,1691)`.
- **Riavvio di Stats** → ricrea i 6 item, di nuovo `(7,1691)`.
- Foreground = ghostty (menù stretti) → parte sinistra della barra libera, ma non basta.
- ⚠️ **Nessuna modifica alle preferenze in questa sessione**: `Disk_state` resta `0`, `CombinedModules` resta `0`, nessuna chiave posizione toccata.

**Obiezione dell'utente (DA VERIFICARE, non ancora provata)**: *"non credo sia il monitor verticale; su quello come sempre non si vedono icone oltre un certo punto, e l'orizzontale ha molto spazio libero e comunque non le mostra."* → È **coerente** col meccanismo (item right-anchored: lo spazio a **sinistra** del 6K non viene mai usato), ma resta un'ipotesi finché non la si falsifica.

**PROSSIMO PASSO — l'utente sta cambiando POSTAZIONE e MONITOR** (il cambio è l'esperimento A/B naturale). Alla nuova postazione, **prima di tutto**, ri-misurare:
```
zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh
```
- **Icone COMPAIONO** sul nuovo display → confermata la causa **multi-display/arrangiamento**. Fix: rendere il monitor principale **il più a destra** dell'arrangiamento (monitor verticale **a sinistra** del main), oppure sfoltire la barra.
- **Icone NON compaiono** anche su un setup diverso → la geometria **non** è la causa: indagare stato per-app / bug Tahoe #3120 indipendente, o **cosa accomuna Stats + Backblaze** (entrambi ex-gestiti da Bartender? autosave-name `NSStatusItem` corrotto? ordine/timing di registrazione al login?).

**Fix candidati (in ordine), dopo la ri-misura**:
1. **Arrangiamento display**: monitor verticale **a sinistra** del 6K (6K = il più a destra) → item disposti nella sola x del main. `brew install displayplacer` per farlo/verificarlo da CLI.
2. **Sfoltire la barra** (doppioni evidenti): **3× OneDrive**, **CPU Temperature** (duplica i Sensori di Stats), agenti Logitech multipli, **Parallels Toolbox**.
3. **Stats più leggero**: `defaults write eu.exelban.Stats CombinedModules -bool true` (6→1 item) — palliativo, **non** risolve Backblaze.
4. Toggle **"Displays have separate Spaces"** (richiede logout).

**Script diagnostico riutilizzabile** (sola lettura): `/Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh` — enumera item reali vs orfani di tutte le app, con verdetto OK/ORFANO per Stats e Backblaze.

> La sezione "PROSSIMO PASSO" più sotto (test post-riavvio con Bartender) è **eseguita e superata** da questo aggiornamento.

---

## TL;DR — due problemi DISTINTI

| # | Problema | Causa (accertata) | Stato |
|---|----------|-------------------|-------|
| 1 | Stats **crashava** (SIGABRT) subito dopo l'avvio | Bug **upstream** del modulo **Disk** di Stats 3.0.5 (`NSGridView.removeRow(at:)` → `NSException` non catturata). NON è codice del fork. | **Mitigato** (Disk off) + **patch scritta** (da compilare) |
| 2 | La barra dei menu **non mostra** gli item di Stats | **Bartender 6.5.2** (funzione **NotchBar**) ha preso i 6 item e li ha lasciati **orfani fuori barra** su Tahoe, con display principale 6K **senza notch**. NON è un bug di Stats né del fork. | **Isolato**; richiede **riavvio con Bartender disabilitato** (test in sospeso) |

Sia la `Stats.app` ufficiale che `StatsDebug.app` sono **3.0.5 build 810** con **lo stesso bundle-id** `eu.exelban.Stats` → condividono preferenze e widget, e oggi giravano **due istanze insieme** (fonte di confusione in barra).

---

## PROSSIMO PASSO (appena riavvii)

1. **Disabilita Bartender**: Impostazioni di Sistema → Generali → **Elementi login ed estensioni** → spegni **Bartender** ("Consenti in background"). *(È ciò che impedisce a Bartender di ri-orfanare gli item al login; senza questo il test è falsato.)*
2. **Riavvia** (o logout/login).
3. Al login parte **solo** `/Applications/Stats.app` (login item), con **Disk disattivato → niente crash**.
4. Guarda la barra: dovrebbero comparire i **6 item di Stats** (CPU, GPU, RAM, Sensori, Rete, Batteria) — valori reali di Stats, **non** il ~60°C di **Parallels**.
5. Esiti:
   - **Compaiono** → era Bartender/NotchBar. Poi: o si tiene Bartender configurandolo per *mostrare* Stats e **spegnendo la NotchBar**, o si lascia disattivato.
   - **Non compaiono** → è il bug Tahoe di Stats "menu bar items not showing" (https://github.com/exelban/stats/issues/3120); si tratta a parte (toggle moduli / attesa update upstream).

---

## Problema 1 — CRASH (dettaglio)

- **Sintomo**: `EXC_CRASH / SIGABRT`, `abort()`, subito dopo il launch.
- **Prova (crash report)**: `/Users/vittoriovillani/Code/stats/evidence/Stats-crash-2026-07-01-213057.ips`
  (copia persistente; originale in `/Users/vittoriovillani/Library/Logs/DiagnosticReports/Retired/`).
- **Stack chiave**: `objc_exception_throw` → `-[NSAssertionHandler handleFailureInMethod:...]` → `-[NSGridView removeRowAtIndex:]` → **modulo `Disk`** → `_dispatch_call_block_and_release` (main queue).
- **Root cause**: `/Users/vittoriovillani/Code/stats/Modules/Disk/preview.swift`, metodo `capacityCallback` — il teardown righe della `NSGridView` chiama `removeRow(at:)` con indice non valido / stacca le cell view prima di rimuovere la riga → `NSRangeException` non catturata. Codice upstream (commit `0c721a24`, 2026-04-23, "Disk preview (disabled for now)"), presente identico nel binario ufficiale 3.0.5.
- **Perché entrambe le build**: stesso codice Disk + preferenze condivise (Disk abilitato).
- **Perché proprio ora**: aggiornamento alla 3.0.5 (uscita 28 giu) + macOS 26.5.1 + molti dischi esterni (churn di mount/unmount che innesca il path).
- **Mitigazione applicata**: `defaults write eu.exelban.Stats Disk_state -bool false` (modulo Disk spento → nessun crash, su entrambe le build).
- **Patch scritta (da COMPILARE per validare)**: `/Users/vittoriovillani/Code/stats/Modules/Disk/preview.swift`
  - helper `removeGridRow(_:)` (guardie NSNotFound + bounds + identità `row(at:) === target`)
  - rimozione righe **prima** dello stacco delle cell view; azzeramento `gridRow`/`separatorRow`
  - guardia `numberOfColumns >= 3` su `column(at:)`
  - Diff: `cd /Users/vittoriovillani/Code/stats && git diff -- Modules/Disk/preview.swift`
  - Revert se serve: `git checkout -- Modules/Disk/preview.swift`
- **Issue upstream pronta**: `/Users/vittoriovillani/Code/stats/DISK_PREVIEW_CRASH_UPSTREAM_ISSUE.md` (da aprire su github.com/exelban/stats).
- **Validazione**: ricompila il fork (`make` / xcodebuild), poi riattiva Disk **solo sul build patchato**:
  `defaults write eu.exelban.Stats Disk_state -bool true` → verifica che NON crashi.
  ⚠️ NON riattivare Disk sull'app ufficiale finché upstream non rilascia il fix.

## Problema 2 — BARRA VUOTA (dettaglio)

- **Accertato**: `StatsDebug` gira e **crea 6 status item** (Accessibility li conta), ma sono **fuori barra** (AX position degenere `(7,1691)`). Confronto differenziale barra **con vs senza** Stats = **identica** → nessun item Stats visibile.
- **Causa**: **Bartender 6.5.2** — la sua config (`/Users/vittoriovillani/Library/Preferences/com.surteesstudios.Bartender.plist`, modificata oggi 21:27) elenca i 6 item `eu.exelban.Stats-*` e ne mette in `AlwaysHide`; helper **NotchBar** (`NotchBar_BartenderMusic … mediaremote-adapter.pl`) restava vivo anche a Bartender "chiuso". Display principale = **6K esterno senza notch** → gli item assegnati alla NotchBar non vengono disegnati.
- **Scagionati**: **GhostPepper** (`com.github.matthartman.ghostpepper`) = app di **dettatura vocale locale**, non gestisce la barra. Karabiner/Logi/Adobe = irrilevanti.
- **Cosa NON ha funzionato (a sessione viva)**: reset chiavi `NSStatusItem … Position`; `CombinedModules=true` (1 item, sempre `(7,1691)`); `killall ControlCenter`; quit "pulito" di Bartender. Gli item orfani si recuperano **solo** con un ripristino pulito (riavvio/relogin) senza Bartender.
- **Fatto in questa sessione**: uccisi tutti i processi Bartender (incl. helper NotchBar).

---

## Modifiche alle preferenze fatte in sessione (per trasparenza / revert)

Dominio: `eu.exelban.Stats` (file `/Users/vittoriovillani/Library/Preferences/eu.exelban.Stats.plist`).

| Chiave | Prima | Ora | Nota |
|--------|-------|-----|------|
| `Disk_state` | `true` | **`false`** | **TENERE** finché il fork non è ricompilato con la patch (previene il crash). Revert: `defaults write eu.exelban.Stats Disk_state -bool true` |
| `CombinedModules` | `false` | `false` | Rimesso all'originale (era stato messo `true` per test) |
| `NSStatusItem … Position *` | valori vari | **cancellate** | Si rigenerano da sole al prossimo avvio |

Fork (working tree, NON committato):
- `/Users/vittoriovillani/Code/stats/Modules/Disk/preview.swift` — patch crash (sopra)
- `/Users/vittoriovillani/Code/stats/Kit/Widgets/Battery.swift` — **tua** modifica USB preesistente (`self.queue.sync { }`): ⚠️ verificare rischio **deadlock** se il metodo gira già su `self.queue`, prima di committare.
- File nuovi: `SESSION_HANDOFF_STATS_DEBUG.md` (questo), `DISK_PREVIEW_CRASH_UPSTREAM_ISSUE.md`, `evidence/Stats-crash-2026-07-01-213057.ips`

## Igiene fork (separata, da fare con calma)
- Dare a `StatsDebug.app` un **bundle-id distinto** (es. `eu.exelban.StatsDebug`) per non contendersi preferenze/widget/istanze con la release.
- `StatsDebug.app` ha firma **ad-hoc** ("code has no resources…"): innocua per l'esecuzione locale, ma va rifirmata pulita se la si distribuisce.

---

## PROMPT DI RIPRESA (incolla nella prossima sessione dopo il riavvio)

```
Riprendiamo il debug di Stats/StatsDebug. Leggi prima l'handoff completo:
/Users/vittoriovillani/Code/stats/SESSION_HANDOFF_STATS_DEBUG.md

Contesto: crash del modulo Disk (bug upstream 3.0.5) già mitigato con Disk_state=0 e patch
scritta in /Users/vittoriovillani/Code/stats/Modules/Disk/preview.swift (da compilare).
Problema aperto: gli item di Stats non compaiono in barra per colpa di Bartender 6 (NotchBar)
su display 6K senza notch.

Ho appena riavviato con Bartender disabilitato in Elementi login. Esito in barra: <COMPAIONO / NON COMPAIONO>.
Procediamo di conseguenza (se compaiono: configurare/rimuovere Bartender; se no: bug Tahoe #3120).
```
