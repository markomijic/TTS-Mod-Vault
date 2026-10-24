# Erste Schritte

TTS Mod Vault liest die Ordner `Mods` und `Saves` von Tabletop Simulator, zeigt jeden Mod, jeden Spielstand und jedes gespeicherte Objekt mit dem Status seiner Asset-Dateien und lässt dich fehlende Dateien herunterladen, `.ttsmod`-Backups erstellen und wiederherstellen.

- Lege die Ordner unter Einstellungen → Ordner fest. Ein Backup-Ordner ist optional, wird aber benötigt, damit der Backup-Status zwischen Starts erhalten bleibt.
- Die Bibliothek wird beim Start indiziert; klicke nach Änderungen außerhalb der App in der Seitenleiste auf Aktualisieren. "Vault-Cache leeren" liest alle JSON-Dateien neu ein.
- Mods, Spielstände, Gespeicherte Objekte und Backups sind Tabs über der Liste. Gespeicherte Objekte erscheinen, wenn sie unter Einstellungen → Funktionen aktiviert sind, Backups, sobald ein Backup-Ordner festgelegt ist.

# Bibliothek

- Linksklick auf einen Mod zeigt seine Assets und Aktionen
- Rechtsklick auf einen Mod zeigt weitere Aktionen (herunterladen, sichern, Ordner öffnen, umbenennen, löschen, ...)
- Strg-Klick (Cmd-Klick unter macOS) wählt mehrere Mods für Sammelaktionen aus
- Fahre über das Backup-Symbol eines Mods, um Backup-Datum und Asset-Anzahl zu sehen
- Fahre über die Typauswahl, um zu sehen, wie viele Mods, Spielstände und gespeicherte Objekte es gibt
- Suche, sortiere und filtere über die Werkzeugleiste; Sammelaktionen berücksichtigen Suchtext und Filter
- Tastatur: Strg+F fokussiert die Suche, F5 aktualisiert, Esc hebt die Auswahl auf, Entf löscht den ausgewählten Mod nach einer Bestätigung

# Ausgewählter Mod

Der rechte Bereich listet die Assets des ausgewählten Mods nach Typ gruppiert. URL-Farben:

- Rot: Die Asset-Datei fehlt
- Grün: Die Asset-Datei ist heruntergeladen
- Orange: Eine URL-Prüfung hat die URL als ungültig markiert
- Hervorgehoben: Die zuletzt angeklickte URL

Aktionen:

- Links- oder Rechtsklick auf eine URL zeigt Optionen (öffnen, kopieren, herunterladen, ersetzen, Datei löschen)
- Doppelklick auf ein PDF-Vorschaubild öffnet die Datei
- Alle herunterladen: lädt alle fehlenden Asset-Dateien herunter. Dateien, die danach noch fehlen, werden geprüft: Der Dialog "Ergebnisse der Download-Prüfung" listet nicht erreichbare Domains und nicht mehr funktionierende URLs. Abschalten kannst du das unter Einstellungen → Netzwerk → Fehlende Dateien nach Downloads prüfen
- "3 fehlen, 2 ungültig" auf einer Karte: 3 Dateien fehlen, und eine URL-Prüfung hat 2 ihrer URLs als defekt erkannt, daher können diese nicht heruntergeladen werden
- Backup: erstellt ein Backup aus den heruntergeladenen Asset-Dateien
- Audio-Assets lassen sich unter Einstellungen → Funktionen global ausschließen und pro Mod über dessen Kontextmenü überschreiben

# Backups

- Backups sind `.ttsmod`-Archive mit der Mod-JSON, ihrem Bild und allen heruntergeladenen Asset-Dateien.
- Der Backup-Status vergleicht das Backup mit dem Mod: aktuell, veraltet (die JSON hat sich nach dem Backup geändert) oder Asset-Anzahl weicht ab.
- Backups importieren in der Seitenleiste stellt Archive im Mods-Ordner wieder her. JSON importieren fügt einen Mod aus einer JSON-Datei hinzu.
- Sammel-Backups bieten Überspringen, Ersetzen und Ersetzen, wenn veraltet, und können die Dateien des Mods danach optional löschen.

# URLs aktualisieren

Die Funktion URLs aktualisieren ersetzt den Anfang von URLs, oder sogar ganze URLs, vom "Alten Präfix" durch das "Neue Präfix".

Du kannst mehrere alte Präfixe eingeben, getrennt durch das Zeichen `|` (senkrechter Strich). Unter Einstellungen → Vorlagen für URL-Aktualisierung kannst du Vorlagen anlegen, die dann im Dialog URLs aktualisieren angeboten werden.

Mit einem alten Präfix:

- Altes Präfix: `http://pastebin.com/raw.php?i=`
- Neues Präfix: `https://pastebin.com/raw/`

Wenn dein Mod `http://pastebin.com/raw.php?i=1234` und `http://pastebin.com/raw.php?i=example` enthält, werden sie zu `https://pastebin.com/raw/1234` und `https://pastebin.com/raw/example`.

Mit mehreren alten Präfixen:

- Alte Präfixe: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Neues Präfix: `https://pastebin.com/raw/`

Wenn dein Mod `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` und `http://pastebin.com/example2` enthält, werden sie zu `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` und `https://pastebin.com/raw/example2`.

# Workshop

- Lade Workshop-Mods über die Seitenleiste per Steam-Workshop-ID oder URL herunter; mehrere IDs können auf einmal eingegeben werden.
- Aus dem Workshop aktualisieren lädt die JSON eines bereits vorhandenen Mods erneut herunter. Die Option zum Erzwingen überschreibt auch eine neuere lokale Datei.

# Fehlerbehebung

- Der Log-Bereich unter der Liste protokolliert jeden Vorgang mit seinen Fehlern; klappe ihn aus, um nach Stufe und Quelle zu filtern, zu suchen, Einträge zu kopieren oder ihn zu leeren. Klicke auf einen Eintrag, um seinen Mod auszuwählen.
- Die Log-Datei `vault.log` liegt neben der Datenbank. Öffne sie über die Kopfzeile des Log-Bereichs oder den Tab Über; hänge sie an Fehlerberichte an.
- Nach einem Ordnerwechsel erscheint nichts? Klicke auf Aktualisieren. Immer noch nichts? Prüfe die Ordnerpfade unter Einstellungen → Ordner und die ausgeschlossenen Unterordner.
- Downloads funktionierender URLs schlagen fehl, wenn viele gleichzeitig laufen? Verringere die gleichzeitigen Downloads unter Einstellungen → Netzwerk.
- URL-Prüfungen und die Prüfung nach einem Download testen zuerst, ob jede Domain überhaupt erreichbar ist. URLs auf einer nicht erreichbaren Domain (offline oder in deinem Netzwerk gesperrt) werden nicht als ungültig markiert, und eine URL-Prüfung mit einer solchen Domain wird nicht gespeichert. Einstellungen → Netzwerk → Alle Domains von Mods und Spielständen prüfen testet jede Domain, die deine Mods und Spielstände verwenden.
