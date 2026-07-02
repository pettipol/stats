# RUNBOOK — Fix Stats barra dei menu + crash Disk + fan control (macOS 26 Tahoe)

> **Scopo:** documentare in modo **replicabile** e **ripristinabile** tutto ciò che è stato fatto per
> risolvere (1) le icone di Stats invisibili in barra, (2) il crash del modulo Disk, (3) il controllo
> ventole + temperature. Ogni path è **assoluto**. Eseguibile anche da un'altra sessione/runtime.
>
> **Data:** 2026-07-02 · **Macchina:** MacBook Pro M4 Max, macOS **26.5.1** (25F80), arm64 · **Xcode 26.6**
> **Repo fork:** `/Users/vittoriovillani/Code/stats` (branch `feature/usb-power-monitoring`)

---

## 0. TL;DR (stato finale)

- **App in uso ora:** `/Applications/StatsDebug.app` — bundle-id **`eu.exelban.StatsDebug`**, firma **ad-hoc**, compilata dal fork. È il **login item** attivo.
- **App ufficiale:** `/Applications/Stats.app` — **intatta**, ma **non parte più al login** (rimossa dai login item). Se lanciata, le sue icone tornano orfane (è il bug, vedi §1).
- **Barra:** icone Stats visibili (CPU/GPU/RAM/Rete/Batteria+USB/Disk/Sensori). ✅
- **Crash Disk:** patch attiva, `Disk_state=1`, nessun crash. ✅
- **Temperature:** funzionano (lettura SMC non privilegiata). ✅
- **Controllo ventole:** funziona — helper root SMC installato via `SMAppService` + **approvato dall'utente** in *Impostazioni di Sistema → Elementi login → Consenti in background*. **Nessun Developer ID necessario.** ✅

---

## 1. Diagnosi (causa radice)

**Sintomo:** gli `NSStatusItem` di Stats (e di Backblaze) venivano creati ma **non piazzati**, parcheggiati a
`(7, altezza_main−1)` = angolo basso-sinistra, invisibili. Firma classica di item con `button.window.screen == nil`.

**Causa:** bug **macOS 26 Tahoe** = **wedge per-`CFBundleIdentifier`**, uno stato "incastrato" tenuto **in
memoria** da ControlCenter/WindowServer (NON su disco), che pinna certi bundle-id fuori barra.

**Perché il fix funziona:** un `CFBundleIdentifier` **mai visto** non ha voce nel wedge → gli item si piazzano.
Provato: stesso identico binario 3.0.5, cambiato **solo** il bundle-id → item in barra.

**Ipotesi REFUTATE con prove locali** (non solo escluse a parole):
Bartender (rimosso, sintomo persiste) · geometria multi-display (3 setup diversi, identico) · overflow/barra
piena (screenshot con spazio libero) · posizione salvata mancante (Backblaze la **ha** ed è orfano; Ollama/OneDrive
**non** l'hanno e stanno in barra) · API legacy `statusItem.view` (Stats usa `.button`) · permesso "Menu Bar"
(gli item **esistono** nell'AX tree → creati e permessi, solo non piazzati).

**Fonti primarie:** exelban/stats **#3120** (commento AndrewBeniston: `screen==nil`, fix cambiando `CFBundleIdentifier`)
· **CodexBar #802** (build `.debug` OK, release orfana). Il fix autosaveName **#2768** (`2a23ab84`, modo A) è **già** nel fork.

---

## 2. Inventario COMPLETO delle modifiche fatte

### 2.1 Sorgente (working tree, NON committato)
| File | Modifica | Backup / revert |
|---|---|---|
| `/Users/vittoriovillani/Code/stats/Stats.xcodeproj/project.pbxproj` | Tutti i `PRODUCT_BUNDLE_IDENTIFIER = eu.exelban.Stats*` → `eu.exelban.StatsDebug*` | Backup: `.../project.pbxproj.prewedge.bak` |
| `/Users/vittoriovillani/Code/stats/Modules/Disk/preview.swift` | Patch anti-crash `removeRow(at:)` (già presente da sessione precedente) | `git checkout -- Modules/Disk/preview.swift` |
| `/Users/vittoriovillani/Code/stats/Kit/Widgets/Battery.swift` | Tua modifica USB power (preesistente, **non** mia) | `git checkout -- Kit/Widgets/Battery.swift` |

> **NIENTE è stato committato.** Prima di committare: verificare il rischio deadlock `queue.sync` in `Battery.swift` (vedi §7).

### 2.2 Sistema
| Cosa | Stato | Come si ripristina |
|---|---|---|
| `/Applications/StatsDebug.app` | **Creato** (installato) | `rm -rf /Applications/StatsDebug.app` |
| `/Applications/Stats.app` (ufficiale) | **Intatto** | — |
| Dominio prefs `eu.exelban.StatsDebug` | **Creato** (clonato da `eu.exelban.Stats`) | `defaults delete eu.exelban.StatsDebug` |
| Login item **"Stats"** (ufficiale) | **Rimosso** | vedi §5 |
| Login item **"StatsDebug"** | **Aggiunto** | vedi §5 |
| Helper root SMC `eu.exelban.Stats.SMC.Helper` | **Registrato** (SMAppService, approvato) da StatsDebug | vedi §5 (uninstall) |
| Bartender 6 | Già rimosso/disabilitato in sessione precedente | `zsh /Users/vittoriovillani/Bartender6-uninstall-backup-2026-07-02/RESTORE.sh` |

---

## 3. REPLICARE da zero (es. dopo un update di Stats o su altra macchina)

```bash
cd /Users/vittoriovillani/Code/stats

# 1) Cambia TUTTI i bundle-id dell'app (main + appex/login-item/moduli devono restare prefissati coerenti,
#    altrimenti ValidateEmbeddedBinary fallisce su WidgetsExtension.appex e LaunchAtLogin.app)
cp Stats.xcodeproj/project.pbxproj Stats.xcodeproj/project.pbxproj.orig.bak
sed -i '' '/PRODUCT_BUNDLE_IDENTIFIER = eu\.exelban\.Stats/ s/= eu\.exelban\.Stats/= eu.exelban.StatsDebug/' \
  Stats.xcodeproj/project.pbxproj

# 2) Build SENZA firma (il progetto è configurato per Developer ID che non hai)
xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Release \
  -derivedDataPath /Users/vittoriovillani/Code/stats/build/DD \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" VALIDATE_PRODUCT=NO \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 build

# 3) Firma AD-HOC in profondità (niente hardened runtime → i moduli/framework si caricano;
#    l'helper e l'app avranno lo stesso "certificato vuoto" → XPC check passa)
codesign --force --deep --sign - \
  /Users/vittoriovillani/Code/stats/build/DD/Build/Products/Release/Stats.app

# 4) Installa come app DISTINTA (l'ufficiale resta intatto)
osascript -e 'tell application id "eu.exelban.StatsDebug" to quit' 2>/dev/null
cp -R /Users/vittoriovillani/Code/stats/build/DD/Build/Products/Release/Stats.app /Applications/StatsDebug.app

# 5) (opzionale) clona la config esistente per saltare l'onboarding
defaults export eu.exelban.Stats - | defaults import eu.exelban.StatsDebug -

# 6) Avvia
open /Applications/StatsDebug.app

# 7) Login item: togli l'ufficiale, aggiungi StatsDebug
osascript -e 'tell application "System Events" to delete login item "Stats"' 2>/dev/null
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/StatsDebug.app", hidden:false}'
```

**Poi, nell'app (una tantum, GUI):**
- **Temperature:** *StatsDebug → Impostazioni → Sensors* → scegli i sensori da mostrare in barra.
- **Ventole:** *Sensors → Fan control* → attiva; al primo comando compare la richiesta di **approvare l'helper**
  in *Impostazioni di Sistema → Generali → Elementi login → Consenti in background* → attivalo. Da lì puoi
  forzare le ventole (es. 100%). Persiste al reboot.

**Verifica:** `zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh` → gli item devono essere `OK (in barra)`.

---

## 4. Perché ventole/temperature funzionano senza Developer ID (dettaglio tecnico)

- **Temperature/RPM = lettura SMC** in `SMC/smc.swift` (`IOServiceOpen("AppleSMC")`) nel processo app → **non privilegiata**, funziona sempre.
- **Comando ventole = scrittura SMC** → serve un **helper root**. Stats lo registra con **`SMAppService.daemon`**
  (`Kit/helpers.swift`, `SMCHelper`), non solo col vecchio `SMJobBless`.
- L'handshake XPC helper↔app (`SMC/Helper/main.swift → CodesignCheck.codeSigningMatches`) confronta gli **array
  di certificati**: `certs(helper) == certs(app)`. Con **ad-hoc** entrambi sono **vuoti** → `[] == []` → **passa**.
- Su macOS 26, `SMAppService.daemon` **accetta un daemon ad-hoc** previa **approvazione utente** (BTM: `daemon
  [enabled, allowed]`, `Parent Identifier: 2.eu.exelban.StatsDebug`). Nessun cert Apple richiesto per uso **locale**.
- **Limite noto:** il vecchio requisito `SMPrivilegedExecutables` / `SMAuthorizedClients` (che cita `OU=RP2S87B72W`,
  il team di exelban) NON è enforced da `SMAppService` in questo flusso → per questo l'ad-hoc basta.

**Stato attuale verificato:** helper `eu.exelban.Stats.SMC.Helper` gira **come root**; `Sensors_fanControl = 1`.

---

## 5. RESTORE / ROLLBACK completo (tornare allo stato originale)

```bash
# 1) Login item: togli StatsDebug, rimetti l'ufficiale Stats
osascript -e 'tell application "System Events" to delete login item "StatsDebug"' 2>/dev/null
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Stats.app", hidden:false}'

# 2) Disinstalla l'helper root SMC (modo pulito: bottone "Uninstall" in StatsDebug → Impostazioni → Sensors)
#    oppure da terminale:
sudo launchctl bootout system/eu.exelban.Stats.SMC.Helper 2>/dev/null
#    (poi in Impostazioni di Sistema → Elementi login rimuovere l'eventuale voce residua)

# 3) Chiudi e rimuovi StatsDebug + il suo dominio prefs
osascript -e 'tell application id "eu.exelban.StatsDebug" to quit' 2>/dev/null
rm -rf /Applications/StatsDebug.app
defaults delete eu.exelban.StatsDebug   # opzionale

# 4) Ripristina il sorgente ai bundle-id originali
cd /Users/vittoriovillani/Code/stats
cp Stats.xcodeproj/project.pbxproj.prewedge.bak Stats.xcodeproj/project.pbxproj
#    (Disk patch e Battery mod restano nel working tree; per toglierli: git checkout -- <file>)

# 5) (se vuoi) rilancia l'ufficiale Stats — ATTENZIONE: le sue icone torneranno orfane (è il bug)
open /Applications/Stats.app

# 6) (se vuoi) ripristina Bartender 6
zsh /Users/vittoriovillani/Bartender6-uninstall-backup-2026-07-02/RESTORE.sh
```

---

## 6. Bartender — note per la ri-prova

Bartender è stato **scagionato con prova diretta**: con Bartender del tutto assente, gli item restavano orfani; e
il fix (nuovo bundle-id) funziona **indipendentemente** da Bartender, perché il wedge è per-bundle-id nel
WindowServer, non una cosa di Bartender.

**Se rilanci Bartender** (backup+RESTORE in `/Users/vittoriovillani/Bartender6-uninstall-backup-2026-07-02/`):
- Il fix su StatsDebug **regge**: gli item si piazzano lo stesso.
- Bartender potrebbe **nascondere/gestire** gli item di StatsDebug (è il suo mestiere): se non li vedi, in
  Bartender configura `eu.exelban.StatsDebug-*` come **"Show in Menu Bar"** e **spegni la NotchBar**.
- Per un confronto pulito, prima misura senza Bartender (`measure_menubar.sh`), poi con Bartender attivo.

---

## 7. Open items / prossimi passi

1. **Commit** (quando vuoi): `project.pbxproj` (bundle-id) + `Modules/Disk/preview.swift` (patch crash). **Prima**
   di committare `Kit/Widgets/Battery.swift`, verificare il **deadlock `queue.sync`** (se il metodo gira già su
   `self.queue`). La parte Battery/USB è **secondaria**: se complessa, si può **escludere dal commit**
   (`git add project.pbxproj Modules/Disk/preview.swift` e lasciare Battery.swift fuori).
2. **Self-heal (opzionale, insurance):** in `Kit/module/widget.swift`, dopo aver creato lo status item, su
   `didChangeScreenParametersNotification` e al next-runloop: se `button.window?.screen == nil` (o y off-screen)
   → `removeStatusItem` + ricrea. Come iStat Menus v7.2. Protegge se il nuovo bundle-id venisse mai wedgato.
   Se dovesse succedere: basta **ri-bumpare** il bundle-id (es. `StatsDebug2`) e ricompilare.
3. **Backblaze** — vedi §8.
4. **Aggiornamenti di Stats:** l'ufficiale si auto-aggiorna (Sparkle) ma resta wedgato; StatsDebug NON si
   auto-aggiorna. Per aggiornarlo: ricompila (§3) dal fork ribasato su `upstream`.

---

## 8. Backblaze — prova futura di uninstall pulito (NON ora)

`bzbmenu` (helper barra di Backblaze, `com.backblaze.bzbmenu`) è colpito dallo **stesso** wedge Tahoe: è closed
source → non possiamo cambiargli il bundle-id in sicurezza. Verificato: relaunch stesso bundle-id → ri-orfana subito.

> ⚠️ **NON fare ora:** Backblaze è **attivo** (ripristino file / spostamento cartelle) → rimuoverlo ora è rischioso.

**Quando Backblaze sarà idle**, prova diagnostica (verificare se un reinstall/uninstall pulito sblocca la sua barra):
1. Pausa backup + attendi che `bztransmit`/`bzfilelist` siano fermi.
2. Disinstalla col metodo ufficiale Backblaze (o `/Applications/Backblaze.app` → uninstaller), che rimuove
   `/Library/Backblaze.bzpkg/` e i suoi launchd.
3. Reboot.
4. Reinstalla l'**ultimo** client Backblaze (build che potrebbe adottare il lifecycle Tahoe corretto).
5. Verifica l'icona: `zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh` (guarda la riga `bzbmenu`).
   - Se torna `OK (in barra)` → il reinstall ha sbloccato il wedge per quel bundle-id.
   - Se resta orfano → serve un update lato Backblaze; nel frattempo l'icona non è mostrabile (Stats non ne dipende).

Il flag di soppressione `/Library/Backblaze.bzpkg/bzdata/bzflags/mac_bzbmenu_hide_status_item.bzflag` **non** è
presente (l'item viene creato, non soppresso).

---

## 9. Comandi di verifica utili

```bash
# Item in barra (verdetto OK/ORFANO per Stats e Backblaze)
zsh /Users/vittoriovillani/Code/stats/evidence/measure_menubar.sh

# Chi gira e con quale bundle-id
for pid in $(pgrep -x Stats); do lsappinfo info -only bundleid "$pid"; done

# Stato helper ventole (deve comparire come root)
ps -axo user,pid,comm | grep -i SMC.Helper | grep -v grep
sfltool dumpbtm | grep -A6 -i "SMC.Helper"

# Login items
osascript -e 'tell application "System Events" to get name of every login item'
```

---

*Runbook generato 2026-07-02. Vedi anche `/Users/vittoriovillani/Code/stats/SESSION_HANDOFF_STATS_DEBUG.md`
(AGGIORNAMENTO 5) e la memoria `project_stats_debug_2026-07-01.md`.*
