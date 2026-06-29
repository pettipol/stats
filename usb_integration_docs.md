# Documentazione Integrazione Monitoraggio USB in Stats

Questo documento riepiloga le modifiche effettuate sul codice sorgente del progetto open-source [Stats](https://github.com/exelban/stats) (clonato in `/Users/vittoriovillani/Code/stats`) per implementare:
1. La visualizzazione del consumo e velocità dei dispositivi USB nel popup dei dettagli batteria.
2. Un widget personalizzato ed allargato nella barra dei menu (menu bar) che indica i flussi di corrente in input/output (Power Flow).
3. Una modalità combinata che unisce i flussi di alimentazione reali e la velocità del link dei dispositivi USB connessi.

---

## 1. Dettagli Modifiche Codice Sorgente

Le modifiche sono state implementate integrando la telemetria energetica e USB del modulo `Battery` con il modulo grafico `Kit`.

### A. Condivisione dei Dati e Nuove Opzioni di Configurazione

#### File: [Kit/types.swift](file:///Users/vittoriovillani/Code/stats/Kit/types.swift)
1. Spostamento e dichiarazione pubblica dello struct `USBDevice_t` in `Kit` in modo che sia accessibile sia dal lettore dati (`Battery` module) sia dal widget grafico (`Kit` Widgets):
   ```swift
   public struct USBDevice_t: Codable, Equatable {
       public let name: String
       public let vendor: String
       public let speed: UInt64
       public let alloc: Int
       
       public init(name: String, vendor: String, speed: UInt64, alloc: Int) {
           self.name = name
           self.vendor = vendor
           self.speed = speed
           self.alloc = alloc
       }
   }
   ```
2. Aggiunta delle nuove modalità di visualizzazione del widget nella lista `BatteryInfo`, inclusa la nuova modalità combinata `powerFlowAndSpeed`:
   ```swift
   internal let BatteryInfo: [KeyValue_t] = [
       KeyValue_t(key: "percentage", value: "Percentage"),
       KeyValue_t(key: "time", value: "Time"),
       KeyValue_t(key: "percentageAndTime", value: "Percentage and time"),
       KeyValue_t(key: "timeAndPercentage", value: "Time and percentage"),
       KeyValue_t(key: "powerFlow", value: "Power flow (IN/OUT)"),
       KeyValue_t(key: "usbStatus", value: "USB Speed & Power"),
       KeyValue_t(key: "powerFlowAndSpeed", value: "Power Flow & USB Speed")
   ]
   ```

---

### B. Gestione Dati e Callback Telemetria

#### File: [Modules/Battery/main.swift](file:///Users/vittoriovillani/Code/stats/Modules/Battery/main.swift)
1. Aggiunta dell'array `usbDevices` nello struct globale dello stato batteria `Battery_Usage`.
2. Aggiornamento del callback di notifica `usageCallback` per inoltrare al widget `BatteryDetailsWidget` tutti i nuovi dati energetici e USB (incluso `adapterPower` per la misurazione istantanea dell'alimentatore):
   ```swift
   case let widget as BatteryDetailsWidget:
       widget.setValue(
           percentage: value.level,
           time: value.timeToEmpty == 0 && value.timeToCharge != 0 ? value.timeToCharge : value.timeToEmpty,
           ACStatus: !value.isBatteryPowered,
           ACwatts: value.ACwatts,
           batteryPower: value.batteryPower,
           adapterPower: value.adapterPower,
           usbDevices: value.usbDevices
       )
   ```

#### File: [Modules/Battery/readers.swift](file:///Users/vittoriovillani/Code/stats/Modules/Battery/readers.swift)
1. Interrogazione IOKit asincrona (`readUSBDevices()`) su un thread in background globale (`DispatchQueue.global(qos: .background)`) per evitare di bloccare la UI principale.
2. Invalido del CoreFoundation RunLoop source all'arresto del lettore per prevenire leak di risorse o crash in chiusura.
3. Lettura del sensore SMC `PDTR` (`self.usage.adapterPower`) per catturare il consumo di corrente istantaneo in ingresso dall'alimentatore di rete.

---

### C. Implementazione Grafica e Modalità Barra dei Menu

#### File: [Kit/Widgets/Battery.swift](file:///Users/vittoriovillani/Code/stats/Kit/Widgets/Battery.swift)
1. Estensione di `BatteryDetailsWidget` con le nuove proprietà di istanza:
   ```swift
   private var ACStatus: Bool = false
   private var ACwatts: Int = 0
   private var batteryPower: Double = 0.0
   private var adapterPower: Double = 0.0
   private var usbDevices: [USBDevice_t] = []
   ```
2. Aggiornamento del metodo `setValue` per ricevere i nuovi parametri in modo thread-safe (spostando l'esecuzione sul thread principale se chiamato asincronamente):
   ```swift
   public func setValue(
       percentage: Double? = nil,
       time: Int? = nil,
       ACStatus: Bool = false,
       ACwatts: Int = 0,
       batteryPower: Double = 0.0,
       adapterPower: Double = 0.0,
       usbDevices: [USBDevice_t] = []
   ) {
       if !Thread.isMainThread {
           DispatchQueue.main.async { [weak self] in
               self?.setValue(...)
           }
           return
       }
       // ... aggiorna proprietà ed esegue self.display() se cambiati ...
   }
   ```
3. Aggiunta dei nuovi motori di rendering grafici bidimensionali (su due righe) all'interno di `draw(_ dirtyRect: NSRect)`:
   * **`powerFlow`**: Mostra la sorgente di alimentazione in tempo reale. Se connesso all'alimentatore, legge l'energia istantanea da `adapterPower` (ad es. `IN: 52W` o `IN: 80W`) con fallback a `ACwatts` nominali solo se il valore istantaneo non è disponibile. Se in scarica su batteria, mostra il consumo di sistema reale (ad es. `BAT: -18W`). La seconda riga mostra la potenza totale allocata per i dispositivi USB esterni collegati (`USB: 12.0W`).
   * **`usbStatus`**: Mostra il conteggio dei dispositivi connessi (`USB: 2 Devs`) nella prima riga, e la velocità massima negoziata dal dispositivo più veloce connesso (`10G` / `480M` / `12M`) nella seconda riga.
   * **`powerFlowAndSpeed`**: La modalità combinata. La riga superiore mostra la potenza reale in ingresso (`IN: 52W` o `BAT: -18W`). La riga inferiore unisce la potenza negoziata dei dispositivi USB e la velocità massima negoziata del link (ad es. `USB: 12.0W (480M)` o `USB: 2.5W (10G)`).

---

### D. Miglioramenti dell'Interfaccia Popup Dettagliata

#### File: [Modules/Battery/popup.swift](file:///Users/vittoriovillani/Code/stats/Modules/Battery/popup.swift)
1. Aggiunta di un modulo UI a scomparsa dinamica (`usbView`) posizionato sotto i dettagli tradizionali.
2. Inserimento dei dispositivi con etichetta descrittiva e dettagli sulla velocità del protocollo (es. `USB4/TB`, `USB 3.x`, `USB 2.0`) e sulla potenza erogata.
3. Ricalcolo dell'altezza dinamica della finestra di popup per evitare spazi vuoti nel layout quando non ci sono dispositivi connessi.

---

## 2. Compilazione ed Esecuzione

### Comando di Build Locale (Senza Certificati)
Dato che il progetto originale richiede certificati Apple Developer di produzione, usa questo comando per compilare ed effettuare la firma *ad-hoc* locale:

```bash
xcodebuild -project Stats.xcodeproj \
           -scheme Stats \
           -configuration Debug \
           -destination 'platform=OS X' \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO
```

L'applicazione compilata è stata copiata in:
👉 `/Users/vittoriovillani/Applications/StatsDebug.app`

---

## 3. Considerazioni Fisiche e Vincoli delle API di macOS

1. **Input Energetico Istantaneo (IN)**: La misurazione in tempo reale dell'alimentatore MagSafe o USB-C è possibile leggendo il sensore SMC `PDTR` (DC In Power in Watts). Questo sensore registra l'effettiva potenza dinamica prelevata dall'alimentatore (che varia, per esempio, se il carico della CPU/GPU cresce o se la batteria è in carica rapida).
2. **Output Energetico USB (OUT)**: macOS non espone una misurazione fisica istantanea della corrente erogata individualmente per ogni singola porta USB. La proprietà `UsbPowerSinkAllocation` fornita da IOKit rappresenta il valore di corrente allocata/negoziata (in mA) richiesto dal dispositivo all'atto della connessione (ad es. 12W per un iPad, 2.5W o 500mW per tastiere/mouse). Tale informazione è il limite massimo che la porta riserva a quel dispositivo, e non la lettura dinamica dell'energia consumata in tempo reale.
3. **Consumo di Sistema**: Per visualizzare il consumo reale complessivo del computer quando è alimentato a batteria, viene letto il sensore SMC `PPBR` (System Power Consumption).

---

## 4. Gestione dello Stato di Sospensione (Sleep & Wake)

Durante la sospensione (sleep), le porte USB del Mac vengono alimentate a basso consumo o disattivate, provocando la disconnessione virtuale delle periferiche. Al risveglio (wake), macOS impiega da 1 a 3 secondi per rinegoziare la velocità e la corrente con le periferiche connesse. 

Per garantire che la lista dei dispositivi USB si aggiorni correttamente al risveglio, `UsageReader`:
1. Si mette in ascolto di `NSWorkspace.didWakeNotification` nel metodo `setup()`.
2. All'arrivo della notifica, esegue una prima lettura immediata, seguita da due letture ritardate programmate **dopo 2.0 e 5.0 secondi** tramite `DispatchQueue.main.asyncAfter`. Questo tempo consente al controller USB di completare la rinegoziazione fisica e a IOKit di registrare nuovamente i dispositivi nel registro di sistema.
3. Rimuove l'osservatore in `deinit` per prevenire perdite di memoria.

---

## 5. Mantenimento e Sincronizzazione del Fork (Git Upstream)

Dato che le modifiche risiedono sul tuo fork personale, puoi mantenerle allineate con le novità ufficiali rilasciate dall'autore di Stats eseguendo questi comandi nel terminale all'interno di `/Users/vittoriovillani/Code/stats`:

1. **Allineare il branch master ufficiale**:
   ```bash
   git checkout master
   git pull upstream master
   git push origin master
   ```

2. **Integrare le novità nel tuo branch delle modifiche**:
   ```bash
   git checkout feature/usb-power-monitoring
   git merge master
   # Se ci sono conflitti, risolvili e fai il commit
   git push origin feature/usb-power-monitoring
   ```

3. **Compilazione ed esportazione rapida**:
   ```bash
   killall Stats
   xcodebuild -project Stats.xcodeproj -scheme Stats -configuration Debug -destination 'platform=OS X' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
   rm -rf /Users/vittoriovillani/Applications/StatsDebug.app
   cp -R /Users/vittoriovillani/Library/Developer/Xcode/DerivedData/Stats-bfaflbhkxswipaboupvohkhdjymk/Build/Products/Debug/Stats.app /Users/vittoriovillani/Applications/StatsDebug.app
   open /Users/vittoriovillani/Applications/StatsDebug.app
   ```

