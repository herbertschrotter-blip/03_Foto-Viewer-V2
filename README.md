# PhotoFolder V2

**Lokale Web-Gallery für Fotos & Videos — powered by PowerShell 7**

PhotoFolder V2 ist eine lokale Foto- und Video-Verwaltung, die als Web-Applikation im Browser läuft. Das PowerShell-Backend dient Bilder und Videos über einen eingebauten HTTP-Server (`HttpListener`), generiert Thumbnails mit FFmpeg und bietet eine moderne Web-UI mit Lightbox, Datei-Sortierung und Bulk-Operationen.

> **Einzigartig:** Kein anderes Projekt in der PowerShell-Community nutzt `HttpListener` als Web-Server für eine vollwertige Media-Gallery. PhotoFolder V2 zeigt, was mit PowerShell 7 alles möglich ist.

---

## Inhaltsverzeichnis

1. [Features](#features)
2. [Voraussetzungen](#voraussetzungen)
3. [Installation & Start](#installation--start)
4. [Was passiert beim Start (Ablauf)](#was-passiert-beim-start-ablauf)
5. [Architektur](#architektur)
6. [Projektstruktur](#projektstruktur)
7. [Datei-für-Datei Dokumentation](#datei-für-datei-dokumentation)
8. [HTTP-Routing im Detail](#http-routing-im-detail)
9. [Async-Architektur (Runspace Pool)](#async-architektur-runspace-pool)
10. [Thumbnail-System](#thumbnail-system)
11. [Video-Streaming (HLS)](#video-streaming-hls)
12. [File Sorter (Pattern-Engine)](#file-sorter-pattern-engine)
13. [Flatten & Move](#flatten--move)
14. [Config-System](#config-system)
15. [Entwicklung & Standards](#entwicklung--standards)
16. [Hinweis für AI-Assistenten](#hinweis-für-ai-assistenten)
17. [Status & Roadmap](#status--roadmap)

---

## Features

### Galerie & Viewer
- **Thumbnail-Grid** mit konfigurierbaren Spalten und Größen
- **Lightbox-Viewer** für Bilder und Videos — Click auf Thumbnail öffnet Fullscreen-Overlay mit Prev/Next-Navigation
- **Lazy Loading** — Thumbnails werden erst beim Scrollen geladen (Intersection Observer API)
- **Akkordeon-Ordner** — ein-/ausklappbare Ordner-Navigation, Medien werden erst bei Klick geladen
- **Keyboard-Navigation** — Pfeiltasten (← →), Enter, Delete, ESC (Lightbox schließen)
- **Folder-Checkboxen** — Ganze Ordner auswählen für Bulk-Operationen
- **Floating Action Bar** — erscheint automatisch bei Selektion, zeigt Zähler (X Ordner, Y Dateien)

### Video-Support
- **FFmpeg-Thumbnails** — automatische Thumbnail-Generierung aus Videos (konfigurierbare Position)
- **HLS-Streaming** — HTTP Live Streaming für Videos (`.m3u8` + `.ts` Segmente via FFmpeg)
- **Codec-Erkennung** — zeigt Codec-Badges auf Thumbnails (H.264, MPEG-2, WMV3 etc.)
- **Browser-Kompatibilitäts-Warnung** — inkompatible Codecs werden erkannt und gemeldet
- **Video in Lightbox** — Video-Player direkt im Lightbox-Overlay mit HLS.js

### Datei-Management
- **File Sorter** — Pattern-basiertes Sortieren mit Multi-Level-Regeln, Drag & Drop, Undo, eigene Hilfe-Seite
- **Flatten & Move** — Dateien aus verschachtelten Unterordnern hochziehen mit Deduplizierung, Ziel-Dialog und Undo
- **Löschen** — Dateien in den Windows-Papierkorb (Recycle Bin API), Bestätigungs-Dialog
- **Archiv-Extraktion** — ZIP/RAR/7z automatisch entpacken beim Start (konfigurierbar)

### Technisch
- **Async Request-Handling** — Runspace Pool für parallele HTTP-Requests (löst Single-Thread-Problem von HttpListener)
- **Hash-basierter Thumbnail-Cache** — persistent auf Disk, selbst-validierend, keine Race Conditions
- **OneDrive-Schutz** — `.thumbs`-Ordner wird per Hidden+System-Attribut und Registry von OneDrive-Sync ausgeschlossen
- **System-Check beim Start** — PowerShell-Version, FFmpeg, Long Path Support, Disk Space
- **Debug-Logging** — `Start-Transcript` in `debug.log`, automatisch anonymisiert (keine echten Pfade im Log)
- **Config-driven** — alle Settings in `config.json`, 60s TTL-Cache, keine hardcoded Werte

---

## Voraussetzungen

| Komponente | Minimum | Empfohlen |
|---|---|---|
| **PowerShell** | 7.0 | 7.4+ |
| **FFmpeg + FFprobe** | 4.x | 6.x+ |
| **OS** | Windows 10 | Windows 11 |
| **Browser** | Chrome/Edge/Firefox | Chromium-basiert |

FFmpeg muss im System-PATH sein:
```powershell
ffmpeg -version
ffprobe -version
```

---

## Installation & Start

```powershell
git clone https://github.com/herbertschrotter-blip/03_Foto-Viewer-V2.git
cd 03_Foto-Viewer-V2
.\start.ps1
```

Beim ersten Start wählt ein Dialog den Root-Ordner. Danach öffnet der Browser automatisch `http://localhost:8888`.

---

## Was passiert beim Start (Ablauf)

Hier der **exakte Ablauf** wenn `.\start.ps1` ausgeführt wird:

### Phase 1: System-Check
1. `Lib_SystemCheck.ps1` wird geladen
2. `Test-SystemRequirements` prüft: PowerShell >= 7.0, FFmpeg im PATH, Long Path Support
3. Bei kritischen Fehlern → Abbruch mit Meldung
4. Bei Warnungen (z.B. kein Long Path Support) → User entscheidet ob fortfahren

### Phase 2: Libraries laden
5. Alle 20+ Lib-Dateien werden per **dot-sourcing** geladen (kein Modul-System)
6. Reihenfolge: Core → Media → UI → Routes → Utils → Sorter → Flatten

### Phase 3: OneDrive-Schutz
7. Prüft ob `.thumbs`-Ordner per Registry von OneDrive ausgeschlossen ist
8. Falls nein → Info-Screen mit Anleitung (oder automatisches Setup)

### Phase 4: Config & State
9. `Get-Config` lädt `config.json` (mit Defaults für fehlende Keys, 60s TTL-Cache)
10. `Get-State` lädt `state.json` (enthält zuletzt gewählten Root-Ordner)
11. CPU-Kerne werden ermittelt → `MaxParallelJobs` wird dynamisch gesetzt

### Phase 5: Root-Ordner wählen
12. Wenn kein Root-Ordner im State → Windows-Folder-Dialog (`Show-FolderDialog`)
13. Root-Ordner wird in State gespeichert

### Phase 6: Archive entpacken (optional)
14. Wenn `config.Features.ArchiveExtraction = true` → `Invoke-ArchiveExtraction` scannt Root nach ZIP/RAR/7z
15. Mehrstufig: auch verschachtelte Archive werden entpackt (Runden-System)

### Phase 7: Medien-Scan
16. `Get-MediaFolders` scannt rekursiv alle Ordner
17. Filtert nach `config.Media.ImageExtensions` + `config.Media.VideoExtensions`
18. Ergebnis: Array von Ordner-Objekten mit `RelativePath`, `Files`, `MediaCount`
19. State wird gespeichert

### Phase 8: Server starten
20. `Start-HttpListener` erstellt `[System.Net.HttpListener]` auf `http://localhost:8888`
21. **Runspace Pool** wird erstellt (`[runspacefactory]::CreateRunspacePool`) mit CPU-Kerne als Worker-Anzahl
22. Browser wird automatisch geöffnet (wenn `AutoOpenBrowser = true`)

### Phase 9: Server-Loop (blockierend)
23. `while ($listener.IsListening)` wartet auf eingehende Requests
24. Jeder Request wird über den **Route-Dispatcher** verarbeitet
25. I/O-intensive Routes (`/img`, `/original`, `/video`, `/hls`) werden an den Runspace Pool delegiert
26. Synchrone Routes (`/`, `/settings`, `/tools`) werden direkt beantwortet
27. Bei `Ctrl+C` → Runspace Pool aufräumen, Listener stoppen, Transcript beenden

---

## Architektur

```
Browser (HTML/CSS/JS)
    |  HTTP (localhost:8888)
PowerShell HttpListener
    |-- Synchrone Routes --> Direkte Antwort
    '-- Async Routes --> Runspace Pool (parallele Worker)
            |
    Dateisystem + FFmpeg + Windows API (Recycle Bin, OneDrive Registry)
```

PhotoFolder ist eine **Single-User Applikation** für lokales Browsen. Kein Login, keine Datenbank — das Dateisystem ist die einzige Datenquelle.

### Warum Lib-System statt .psm1-Module?

PhotoFolder nutzt **dot-sourcing** statt PowerShell-Module:
```powershell
. (Join-Path $ScriptRoot "Lib\Core\Lib_Config.ps1")
```

Gründe: Solo-Projekt, kein Manifest-Overhead, alle Funktionen direkt sichtbar, einfaches Debugging, nur benötigte Libs laden.

---

## Projektstruktur

```
03_Foto-Viewer-V2/
|-- start.ps1                          # Einstiegspunkt + Server-Loop + Route-Dispatcher
|-- config.json                        # Alle konfigurierbaren Settings
|-- state.json                         # Persistenter Zustand (RootPath, etc.)
|
|-- Lib/                               # PowerShell-Bibliotheken
|   |-- Core/                          # Kern-Infrastruktur
|   |   |-- Lib_Config.ps1             #   Config laden/speichern/cachen
|   |   |-- Lib_Http.ps1               #   HTTP-Response Helper
|   |   |-- Lib_Logging.ps1            #   Strukturiertes Logging
|   |   '-- Lib_State.ps1              #   State-Management
|   |
|   |-- Media/                         # Medien-Verarbeitung
|   |   |-- Lib_FileSystem.ps1         #   Dateisystem-Operationen
|   |   |-- Lib_Scanner.ps1            #   Rekursiver Ordner-Scan
|   |   |-- Lib_Thumbnails.ps1         #   Universal-Thumbnail (Dispatcher)
|   |   |-- Lib_ImageThumbnails.ps1    #   Bild-Thumbnails (System.Drawing)
|   |   |-- Lib_VideoThumbnails.ps1    #   Video-Thumbnails (FFmpeg)
|   |   '-- Lib_VideoHLS.ps1           #   HLS-Konvertierung & Streaming
|   |
|   |-- Routes/                        # HTTP-Route-Handler
|   |   |-- Lib_Routes_Media.ps1       #   /original, /video, /hls, /hlschunk
|   |   |-- Lib_Routes_Files.ps1       #   /delete-files
|   |   |-- Lib_Routes_Settings.ps1    #   /settings/*
|   |   |-- Lib_Routes_Sorter.ps1      #   /tools/analyze-*, sort-*, undo-*
|   |   |-- Lib_Routes_Flatten.ps1     #   /tools/flatten-*
|   |   '-- Lib_Routes_Tools.ps1       #   /tools/cache-*, system-*
|   |
|   |-- UI/                            # User Interface
|   |   |-- Lib_Dialogs.ps1            #   Windows-Dialoge (Ordner-Auswahl)
|   |   '-- Lib_UI_Template.ps1        #   HTML-Template-Engine
|   |
|   |-- Utils/                         # Hilfsfunktionen
|   |   |-- Lib_BackgroundJobs.ps1     #   Runspace Pool Management
|   |   |-- Lib_FileSorter.ps1         #   Pattern-Engine (File Sorter Logik)
|   |   |-- Lib_FlattenMove.ps1        #   Flatten & Move Logik
|   |   |-- Lib_ArchiveExtractor.ps1   #   ZIP/RAR/7z Extraktion
|   |   '-- Lib_Tools.ps1              #   Allgemeine Hilfsfunktionen
|   |
|   '-- System/                        # System-Checks
|       '-- Lib_SystemCheck.ps1        #   PS-Version, FFmpeg, Disk Space
|
|-- Templates/                         # Frontend (HTML/CSS/JS)
|   |-- index.html                     #   Hauptseite (Gallery-Grid, Sidebar, Lightbox)
|   |-- styles.css                     #   Externes CSS
|   |-- app.js                         #   Haupt-JavaScript
|   |-- file-sorter.html               #   File Sorter UI
|   |-- file-sorter-help.html          #   File Sorter Hilfe
|   '-- flatten-move.html              #   Flatten & Move UI
|
'-- Debug/                             # Entwickler-Tools
    |-- Copy-AnonymizedStructure.ps1   #   Ordner-Struktur anonymisiert kopieren
    |-- Debug-ConfigValues.ps1         #   Config-Werte ausgeben
    |-- List-Filenames.ps1             #   Dateinamen auflisten
    '-- Test Tools/                    #   Weitere Test-Scripts
```

---

## Datei-für-Datei Dokumentation

### start.ps1 — Einstiegspunkt

**Version:** v0.10.1 | **Groesse:** ~28KB | **Funktion:** Launcher, Server-Loop, Route-Dispatcher

`start.ps1` ist die zentrale Datei. Sie macht alles:

1. **Libs laden** — dot-sourcing aller 20+ Lib-Dateien in korrekter Reihenfolge
2. **System-Check** — PowerShell-Version, FFmpeg, Long Path Support prüfen
3. **Config & State** — `config.json` und `state.json` laden
4. **Root-Ordner** — Dialog oder aus State wiederherstellen
5. **Archive entpacken** — ZIP/RAR/7z wenn Feature aktiviert
6. **Medien scannen** — `Get-MediaFolders` alle Ordner + Dateien indexieren
7. **HttpListener starten** — HTTP-Server auf konfigurierbarem Port
8. **Runspace Pool** — Worker-Threads für parallele Request-Verarbeitung
9. **Server-Loop** — Endlosschleife die Requests empfängt und dispatcht
10. **Route-Dispatcher** — `if/continue`-Logik die URL-Pfade auf Handler mappt

**Besonderheit:** Die `while`-Loop enthält den kompletten Route-Dispatcher inline (nicht in eigener Lib), weil der Dispatcher Zugriff auf `$script:State`, `$runspacePool` und `$listener` braucht.

**Route-Reihenfolge im Dispatcher (wichtig!):**
1. `/` → Hauptseite generieren (HTML aus Templates + Ordner-Daten)
2. `/file-sorter` → File Sorter HTML laden
3. `/file-sorter-help` → Hilfe-Seite laden
4. `/flatten-move` → Flatten & Move HTML laden
5. `/tools/flatten-*` → Flatten API-Routes (VOR allgemeinen Tools!)
6. `/changeroot` → Root-Ordner wechseln (Dialog)
7. `/tools/analyze-*|sort-*|undo-*|...` → File Sorter API
8. `/tools/*` → Cache-Management, System-Info
9. `/settings/*` → Settings-Seite & API
10. `/original|/video|/hls|/hlschunk` → **Async via Runspace Pool** (Media)
11. `/delete-files` → Dateien löschen
12. `/img` → **Async via Runspace Pool** (Thumbnails)
13. `/open-recyclebin` → Windows Papierkorb öffnen
14. `/system/info` → CPU-Kerne als JSON
15. `/ping` → Health-Check
16. `/shutdown` → Server beenden

---

### Lib/Core/ — Kern-Infrastruktur

#### Lib_Config.ps1 (~10KB)
**Funktion:** Config-Management mit Caching

Kernfunktionen:
- `Get-Config` — Lädt `config.json`, merged mit Defaults, cached für 60 Sekunden (`$script:ConfigCacheTTL`). Bei Fehler → Fallback zu Defaults.
- `Save-Config` — Speichert `config.json`, erstellt vorher Backup (`.backup`), invalidiert Cache.
- `Get-ConfigWithDefaults` — Gibt vollständige Default-Config zurück. **Einziger Ort für hardcoded Werte!**
- `Merge-ConfigWithDefaults` — Rekursives Merging: fehlende Keys aus Defaults ergänzen, existierende beibehalten.
- `Get-PowerShellVersionInfo` — PS-Version als Objekt mit `IsPS7`, `DisplayName`.

**Caching:** `$script:ConfigCache` speichert die Config, `$script:ConfigCacheTime` den Zeitstempel. Jeder `Get-Config`-Aufruf prüft ob Cache gültig (< 60s). Erstes Laden: ~50ms (Disk I/O), danach: <1ms.

#### Lib_Http.ps1 (~6KB)
**Funktion:** HTTP-Response Helper

- `Send-ResponseHtml` — Sendet HTML mit `text/html; charset=utf-8`, Status 200
- `Send-ResponseText` — Sendet Text mit konfigurierbarem Content-Type und Status-Code
- `Start-HttpListener` — Erstellt und startet `[System.Net.HttpListener]`
- `Stop-HttpListener` — Stoppt und schließt den Listener

Kapselt das Boilerplate: Encoding setzen, Content-Type, Status-Code, Output-Stream schreiben/schliessen.

#### Lib_Logging.ps1 (~7KB)
**Funktion:** Strukturiertes Logging

- `Write-FVLog` — Log-Einträge mit Timestamp, Level (Debug/Info/Warning/Error), Message
- `Invoke-AnonymizeLogFile` — Ersetzt echte Pfade in `debug.log` durch Platzhalter (Datenschutz)

Logging nutzt `Start-Transcript` (in start.ps1 gestartet) plus `$VerbosePreference = 'Continue'`. Anonymizer läuft beim Server-Stop.

#### Lib_State.ps1 (~3KB)
**Funktion:** Persistenter Zustand

- `Get-State` — Lädt `state.json` (enthält `RootPath`, letzte Einstellungen)
- `Save-State` — Speichert State nach `state.json`

Wichtigster Wert: `RootPath` — damit muss der User nicht jedes Mal den Ordner neu wählen.

---

### Lib/Media/ — Medien-Verarbeitung

#### Lib_Scanner.ps1 (~9KB)
**Funktion:** Rekursiver Ordner-Scan

- `Get-MediaFolders` — Scannt `$RootPath` rekursiv, filtert nach Extensions, gruppiert nach Ordner

**Ablauf:**
1. `Get-ChildItem -Recurse -Directory` holt alle Unterordner
2. Pro Ordner: `Get-ChildItem -File` holt Dateien
3. Filtert nach Extensions (aus Config: `.jpg`, `.mp4`, etc.)
4. Erstellt pro Ordner ein Objekt: `RelativePath`, `Files` (relative Pfade), `MediaCount`
5. `.thumbs`, `.cache`, `.temp` Ordner werden ignoriert

#### Lib_Thumbnails.ps1 (~20KB)
**Funktion:** Universal-Thumbnail-Dispatcher

- `Get-MediaThumbnail` — Entscheidet ob Bild oder Video → ruft `Lib_ImageThumbnails` oder `Lib_VideoThumbnails` auf. Prüft zuerst den Cache (Hash-basiert), nur bei Cache-Miss wird generiert.

#### Lib_ImageThumbnails.ps1 (~13KB)
**Funktion:** Bild-Thumbnails mit System.Drawing

- `New-ImageThumbnail` — Lädt Bild, skaliert mit Aspect-Ratio-Erhaltung, speichert als JPEG
- `Get-ThumbnailPath` — Cache-Pfad: `.thumbs/{hash}.jpg`
- `Test-ThumbnailCache` — Prüft ob Cache-Datei existiert

**Hash:** Basiert auf `Dateiname + Dateigrösse + LastWriteTime`. Bei Änderungen → automatisch neues Thumbnail.

**Technisch:** `[System.Drawing.Image]::FromFile()` + `Graphics.DrawImage()` mit `InterpolationMode.HighQualityBicubic`. JPEG-Encoder mit konfigurierbarer Qualität (Default: 85%).

#### Lib_VideoThumbnails.ps1 (~21KB)
**Funktion:** Video-Thumbnails via FFmpeg

- `New-VideoThumbnail` — Extrahiert Frame aus Video via FFmpeg
- `Get-VideoMetadata` — Liest Codec, Dauer, Auflösung via `ffprobe -print_format json`
- `Test-VideoCodecCompatibility` — Prüft ob Browser den Codec abspielen kann

**FFmpeg-Aufruf:** `ffmpeg -i video.mp4 -ss {StartPercent} -frames:v 1 -q:v {Quality} output.jpg`

`ThumbnailStartPercent` (Default: 10%) überspringt schwarze Intro-Frames.

#### Lib_VideoHLS.ps1 (~8KB)
**Funktion:** HLS-Konvertierung und Streaming

- `Convert-VideoToHLS` — Konvertiert Video zu HLS-Segmente (`.m3u8` + `.ts`) via FFmpeg
- `Get-HLSPlaylist` — Pfad zur `.m3u8` Playlist
- `Test-HLSExists` — Prüft ob HLS-Segmente bereits existieren

**FFmpeg:** `ffmpeg -i input -c:v libx264 -preset {Preset} -c:a aac -f hls -hls_time {SegmentDuration} output.m3u8`

HLS-Segmente im `.temp`-Ordner. Browser lädt `.m3u8` Playlist und `.ts` Segmente via HLS.js.

#### Lib_FileSystem.ps1 (~5KB)
**Funktion:** Dateisystem-Operationen

- `Remove-MediaFile` — Löscht Datei in Windows Papierkorb (`Microsoft.VisualBasic.FileIO` mit `SendToRecycleBin`)
- `Resolve-SafePath` — Path-Traversal-Schutz: `[System.IO.Path]::GetFullPath()` + `StartsWith($RootFull)` Check
- `Test-OneDriveProtection` — Prüft ob `.thumbs` von OneDrive-Sync geschützt ist

---

### Lib/Routes/ — HTTP-Route-Handler

#### Lib_Routes_Media.ps1 (~25KB)
**Funktion:** Media-Auslieferung — **läuft im Runspace Pool (parallel!)**

- `Register-MediaRoutes` — Verarbeitet `/original`, `/video`, `/hls`, `/hlschunk`
- `/original?path=foto.jpg` → Original-Bild für Lightbox, mit Range-Request-Support
- `/video?path=video.mp4` → Video mit Range-Requests (HTTP 206) für Seeking
- `/hls?path=video.wmv` → HLS-Playlist, konvertiert bei Bedarf on-the-fly
- `/hlschunk?path=segment.ts` → Einzelne HLS-Segmente

Sicherheit: Path-Traversal Check bei jeder Route. MIME-Types aus Config.

#### Lib_Routes_Files.ps1 (~6KB)
**Funktion:** Datei-Operationen

- `Handle-FileOperationsRoute` — POST `/delete-files` mit JSON-Body (Array von Pfaden)
- Ruft `Remove-MediaFile` pro Datei, gibt Ergebnis als JSON zurück

#### Lib_Routes_Settings.ps1 (~5KB)
**Funktion:** Settings-UI und API

- `/settings/get` → Config als JSON
- `/settings/save` → Config speichern (POST mit JSON-Body)
- `/settings/page` → Settings-HTML mit Accordion-Kategorien

#### Lib_Routes_Sorter.ps1 (~44KB)
**Funktion:** File Sorter REST-API (grösste Route-Lib)

- `/tools/analyze-folder` — Ordner analysieren, Pattern-Gruppen erkennen
- `/tools/sort-preview` — Dry-Run der Sortierung
- `/tools/sort-execute` — Sortierung ausführen, Undo-Journal schreiben
- `/tools/undo-sort` — Letzte Sortierung rückgängig machen
- `/tools/undo-history` — Alle Undo-Möglichkeiten
- `/tools/folder-list` — Ordner-Liste für Zielauswahl
- `/tools/move-file` — Einzelne Datei verschieben
- `/tools/delete-empty` — Leere Ordner löschen

#### Lib_Routes_Flatten.ps1 (~33KB)
**Funktion:** Flatten & Move REST-API

- `/tools/flatten-scan` — Ordner-Tiefe scannen, Medien-Ordner finden
- `/tools/flatten-preview` — Flatten-Vorschau
- `/tools/flatten-execute` — Flatten ausführen (verschiebt Dateien + `.thumbs`)
- `/tools/flatten-undo` — Rückgängig machen
- `/tools/flatten-delete` — Leere Quell-Ordner löschen

#### Lib_Routes_Tools.ps1 (~13KB)
**Funktion:** Werkzeuge und Cache-Management

- `/tools/cache-stats` — Cache-Statistik (Anzahl Thumbnails, Grösse)
- `/tools/cache-clear` — Cache leeren
- `/tools/cache-rebuild` — Background-Job zum Thumbnail-Regenerieren
- `/tools/cache-rebuild-status` — Progress
- `/tools/cache-rebuild-stop` — Job abbrechen

---

### Lib/UI/ — User Interface

#### Lib_Dialogs.ps1 (~2KB)
- `Show-FolderDialog` — Windows Folder-Browser-Dialog. Vor Dialog: 3-Phasen GC (`[GC]::Collect()` x3) damit keine File-Handles blockieren.

#### Lib_UI_Template.ps1 (~4KB)
- `Get-IndexHTML` — Lädt `index.html`, ersetzt Platzhalter (`{{STYLES}}`, `{{SCRIPTS}}`, `{{FOLDER_CARDS}}`), inlined CSS und JS. Alles wird inline gesendet (keine separaten HTTP-Requests).

---

### Lib/Utils/ — Hilfsfunktionen

#### Lib_BackgroundJobs.ps1 (~21KB)
- `Start-CacheRebuildJob` — Thumbnail-Generierung als Background-Job
- `Get-CacheRebuildStatus` — Progress (0-100%)
- `Stop-CacheRebuildJob` — Abbrechen

#### Lib_FileSorter.ps1 (~64KB) — Grösste Datei im Projekt
Pattern-Engine für intelligente Datei-Sortierung: Regex-basiertes Pattern-Matching, Multi-Level-Regeln, Undo-Journal als JSON, Import/Export von Regelsets.

#### Lib_FlattenMove.ps1 (~9KB)
Flatten verschachtelter Ordner: `Root/E1/E2/E3/foto.jpg` → `Ziel/E3/foto.jpg`. Deduplizierung, Undo-Journal, `.thumbs`-Ordner werden mitgenommen.

#### Lib_ArchiveExtractor.ps1 (~15KB)
ZIP/RAR/7z entpacken. Runden-System für verschachtelte Archive. Nutzt `Expand-Archive` (ZIP) und 7-Zip (RAR/7z).

#### Lib_Tools.ps1 (~16KB)
Helfer: `Get-CacheStats`, `Clear-ThumbnailCache`, `Test-IsVideoFile`, `Test-IsImageFile`.

---

### Lib/System/

#### Lib_SystemCheck.ps1 (~8KB)
- `Test-SystemRequirements` — Prüft PS >= 7.0, FFmpeg, FFprobe, Long Path Support (Registry), Disk Space. Gibt Objekt mit `AllPassed`, `Errors`, `Warnings`.

---

### Templates/ — Frontend

#### index.html (~33KB)
Hauptseite: Sidebar (Root-Anzeige, Buttons), Folder-Cards (Akkordeon), Media-Grid, Lightbox (Fullscreen-Overlay), Floating Action Bar. Platzhalter werden serverseitig ersetzt.

#### styles.css (~24KB)
CSS mit Glassmorphism (`backdrop-filter: blur`), Gradient-Buttons, Animationen. Styles für Sidebar, Folder-Cards, Grid, Lightbox, Action Bar, Settings, Checkboxen, Tooltips, Progress-Bars.

#### app.js (~68KB)
Haupt-JavaScript:
- **Lazy Loading** — `IntersectionObserver` lädt Thumbnails beim Scrollen
- **Ordner Toggle** — Click klappt Grid auf/zu, generiert `<img>` Tags
- **Lightbox** — `openLightbox()` mit Keyboard-Navigation, Prev/Next am Rand ausblenden
- **Folder-Checkboxen** — `getSelectedItems()` sammelt alle Selektionen (auch geschlossene Ordner via `data-files` JSON)
- **Action Bar** — Auto-Show/Hide bei Selektion
- **Löschen** — POST an `/delete-files`, selektives DOM-Update (kein Full-Page-Reload → 3s → 100ms)
- **Video** — HLS.js Integration im Lightbox
- **MutationObserver** — Attached Handler an dynamisch hinzugefügte Elemente

#### file-sorter.html (~69KB)
Standalone SPA: Pattern-Konfiguration, Live-Vorschau, Multi-Level, Drag & Drop, Undo, Export/Import.

#### file-sorter-help.html (~66KB)
Ausführliche Hilfe: Pattern-Typen, Beispiele, FAQ.

#### flatten-move.html (~37KB)
Standalone SPA: Ordner-Tiefe visualisieren, Flatten-Vorschau, Move-Progress, Undo, Delete-Empty.

---

## HTTP-Routing im Detail

| Route | Methode | Async? | Beschreibung |
|---|---|---|---|
| `/` | GET | Nein | Hauptseite (Template + Ordner-Daten) |
| `/img` | GET | **Ja** | Thumbnails (generiert bei Cache-Miss) |
| `/original` | GET | **Ja** | Original-Bilder für Lightbox |
| `/video` | GET | **Ja** | Video-Dateien mit Range-Requests |
| `/hls` | GET | **Ja** | HLS-Playlist (.m3u8) |
| `/hlschunk` | GET | **Ja** | HLS-Segmente (.ts) |
| `/delete-files` | POST | Nein | Dateien in Papierkorb |
| `/changeroot` | POST | Nein | Root-Ordner wechseln |
| `/settings/*` | GET/POST | Nein | Config lesen/schreiben |
| `/tools/cache-*` | GET/POST | Nein | Cache-Management |
| `/tools/analyze-*` | POST | Nein | File Sorter |
| `/tools/sort-*` | POST | Nein | File Sorter |
| `/tools/flatten-*` | GET/POST | Nein | Flatten & Move |
| `/file-sorter` | GET | Nein | File Sorter HTML |
| `/flatten-move` | GET | Nein | Flatten HTML |
| `/ping` | GET | Nein | Health-Check |
| `/shutdown` | POST | Nein | Server beenden |

---

## Async-Architektur (Runspace Pool)

### Das Problem
`HttpListener.GetContext()` ist **blockierend und single-threaded**. Während ein Request verarbeitet wird, warten alle anderen. Bei Thumbnail-Generierung oder Video-Streaming → Timeouts (Video hängt nach ~17 Sekunden).

### Die Lösung
```
Browser Request → HttpListener.GetContext()
                      |
              Route-Dispatcher (Main-Thread)
                      |
              [Ist Route async?]
              |-- Nein → Direkt antworten
              '-- Ja  → Runspace Pool
                          |
                    [powershell]::Create()
                    RunspacePool.BeginInvoke()
                          |
                    Worker-Thread: Libs laden → Request verarbeiten → Antworten
```

Async Routes: `/img`, `/original`, `/video`, `/hls`, `/hlschunk`

Jeder Runspace ist **isoliert** — Libs müssen neu geladen und Parameter als Argumente übergeben werden. Cleanup bei jedem neuen Request + beim Server-Stop.

---

## Thumbnail-System

```
GET /img?path=Ordner/foto.jpg
         |
    Runspace Pool
         |
    Resolve-SafePath (Security)
         |
    Hash berechnen (Name + Groesse + LastWriteTime)
         |
    .thumbs/{hash}.jpg existiert?
    |-- Ja → Cache-Hit (<1ms)
    '-- Nein → Cache-Miss:
        |-- Bild: System.Drawing resize
        '-- Video: FFmpeg -ss {%} -frames:v 1
        → .thumbs/{hash}.jpg speichern → Senden
```

Kein Manifest, kein DB — der **Hash im Dateinamen ist der Cache-Key**. OneDrive-Schutz per Hidden+System Attribut und Registry.

---

## Video-Streaming (HLS)

1. User klickt Video-Thumbnail → Lightbox öffnet mit `<video>` + HLS.js
2. `GET /hls?path=video.wmv` → Server gibt `.m3u8` Playlist zurück
3. Falls keine Segmente → FFmpeg konvertiert on-the-fly
4. HLS.js fetcht `.ts` Segmente nacheinander
5. Segmente gecached im `.temp`-Ordner

---

## File Sorter (Pattern-Engine)

1. User öffnet `/file-sorter`
2. "Analysieren" → Backend erkennt Datei-Gruppen (Regex auf Dateinamen)
3. User konfiguriert Multi-Level-Regeln (Drag & Drop)
4. "Vorschau" → Dry-Run zeigt was passiert
5. "Sortieren" → Dateien verschieben + Undo-Journal schreiben
6. "Rückgängig" → Alles zurück aus Journal

---

## Flatten & Move

Vereinfacht verschachtelte Ordner: `Root/E1/E2/E3/medien` → `Ziel/E3/medien`

1. Scan: Ordner-Tiefe analysieren
2. Vorschau: Zeigen was wohin verschoben wird
3. Ausführen: Dateien + `.thumbs` verschieben, Deduplizierung
4. Aufräumen: Leere Quell-Ordner löschen
5. Undo: Alles zurück aus Journal

---

## Config-System

Alle Settings in `config.json` (9 Bereiche). Zugriff:
```powershell
$config = Get-Config          # Cache (<1ms) oder Disk (~50ms)
$port = $config.Server.Port
```

Wichtigste Werte: `Server.Port` (8888), `UI.ThumbnailSize` (200), `Video.UseHLS` (true), `Performance.MaxParallelJobs` (dynamisch = CPU-Kerne), `FileOperations.UseRecycleBin` (true), `Features.ArchiveExtraction` (true).

Vollständiges Schema: `03_Foto-Viewer-V2-Config-Schema.txt`

---

## Entwicklung & Standards

- **PowerShell 7+ only** — `#Requires -Version 7.0`
- **Genehmigte Verben** — `Get-`, `Set-`, `New-`, `Remove-`, `Test-`, `Invoke-`
- **CmdletBinding** bei jeder Funktion
- **Config statt hardcoded** — `$config = Get-Config`
- **Lib-System** — dot-sourcing, keine `.psm1`
- **Git:** `main` ← `dev2` ← `feature/*`
- **Commit-Format:** `[vX.Y.Z] Dateiname` + WARUM-Beschreibung

---

## Hinweis für AI-Assistenten

### Regeln
- **Schrittweise** — ein Feature, Bestätigung abwarten
- **SUCHE/ERSETZE** mit Kontext, NIE Zeilennummern
- **NIE direkt ins Git-Repo** — Herbert committet selbst
- **Libs beliebig lang** — keine Beschränkung
- **Config-Schema prüfen** bevor Settings verwendet werden

### Architektur (unveränderlich)
- Lib-System (dot-sourcing, keine Module)
- Runspace Pool für async HTTP
- Hash-basierte Thumbnails (kein Manifest)
- Kein DB (Dateisystem = Datenquelle)
- Selective DOM Updates (kein Full-Page-Reload)
- HttpListener single-threaded → Runspace Pool
- Config 60s TTL-Cache
- `.thumbs` mit OneDrive-Schutz

---

## Status & Roadmap

**Alle 12 Phasen + Extras abgeschlossen.**

Offen: Flatten testen (echte Daten), HLS Performance-Validierung, Dark Theme, VLC-Integration.

---

## Lizenz

Private Nutzung.