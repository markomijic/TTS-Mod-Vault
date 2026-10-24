# Primi passi

TTS Mod Vault legge le cartelle `Mods` e `Saves` di Tabletop Simulator, mostra ogni mod, salvataggio e oggetto salvato con lo stato dei suoi file di risorse, e ti permette di scaricare i file mancanti, creare backup `.ttsmod` e ripristinarli.

- Imposta le cartelle in Impostazioni → Cartelle. La cartella dei backup è facoltativa, ma serve perché lo stato dei backup venga ricordato tra un avvio e l'altro.
- La libreria viene indicizzata all'avvio; fai clic su Aggiorna nella barra laterale dopo aver modificato file fuori dall'app. "Svuota la cache di Vault" rilegge tutti i file JSON.
- Mod, Salvataggi, Oggetti salvati e Backup sono schede sopra l'elenco. Gli oggetti salvati compaiono quando sono attivati in Impostazioni → Funzionalità, i backup non appena è impostata una cartella dei backup.

# Libreria

- Clic sinistro su una mod per vederne le risorse e le azioni
- Clic destro su una mod per altre azioni (scarica, backup, apri cartella, rinomina, elimina, ...)
- Ctrl+clic (Cmd+clic su macOS) per selezionare più mod per le azioni multiple
- Passa il mouse sull'icona del backup di una mod per vedere la data del backup e il numero di risorse
- Passa il mouse sul selettore del tipo per vedere quante mod, salvataggi e oggetti salvati ci sono
- Cerca, ordina e filtra dalla barra degli strumenti; le azioni multiple rispettano il testo cercato e i filtri
- Tastiera: Ctrl+F porta il cursore sulla ricerca, F5 aggiorna, Esc cancella la selezione, Canc elimina la mod selezionata dopo una conferma

# Mod selezionata

Il pannello a destra elenca le risorse della mod selezionata, raggruppate per tipo. Colori degli URL:

- Rosso: il file della risorsa manca
- Verde: il file della risorsa è scaricato
- Arancione: un controllo degli URL ha segnato l'URL come non valido
- Evidenziato: l'ultimo URL su cui hai fatto clic

Azioni:

- Clic sinistro o destro su un URL per vedere le opzioni (apri, copia, scarica, sostituisci, elimina il file)
- Doppio clic su una miniatura PDF per aprire il file
- Scarica tutto: scarica tutti i file di risorse mancanti. I file ancora mancanti dopo vengono controllati: la finestra "Risultati del controllo del download" elenca i domini irraggiungibili e gli URL che non funzionano più. Puoi disattivarlo in Impostazioni → Rete → Controlla i file mancanti dopo i download
- "3 mancanti, 2 non validi" su una scheda: mancano 3 file, e un controllo degli URL ha trovato che 2 dei loro URL non funzionano, quindi quei file non si possono scaricare
- Backup: crea un backup dai file di risorse scaricati
- Le risorse audio si possono escludere globalmente in Impostazioni → Funzionalità, e questa impostazione si può cambiare per ogni mod dal suo menu contestuale

# Backup

- I backup sono archivi `.ttsmod` con il JSON della mod, la sua immagine e tutti i file di risorse scaricati.
- Lo stato del backup confronta il backup con la mod: aggiornato, non aggiornato (il JSON è cambiato dopo il backup) o numero di risorse diverso.
- Importa backup, nella barra laterale, ripristina gli archivi nella cartella Mods. Importa JSON aggiunge una mod da un file JSON.
- I backup multipli offrono Salta, Sostituisci e Sostituisci se non aggiornato, e se vuoi possono eliminare poi i file della mod.

# Aggiorna gli URL

La funzione Aggiorna gli URL sostituisce l'inizio degli URL, o anche URL interi, dal "Prefisso vecchio" al "Prefisso nuovo".

Puoi inserire più prefissi vecchi separandoli con il simbolo `|` (barra verticale). In Impostazioni → Preimpostazioni di aggiornamento URL puoi creare preimpostazioni che verranno poi proposte nella finestra Aggiorna gli URL.

Con un solo prefisso vecchio:

- Prefisso vecchio: `http://pastebin.com/raw.php?i=`
- Prefisso nuovo: `https://pastebin.com/raw/`

Se la tua mod contiene `http://pastebin.com/raw.php?i=1234` e `http://pastebin.com/raw.php?i=example`, diventeranno `https://pastebin.com/raw/1234` e `https://pastebin.com/raw/example`.

Con più prefissi vecchi:

- Prefissi vecchi: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Prefisso nuovo: `https://pastebin.com/raw/`

Se la tua mod contiene `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` e `http://pastebin.com/example2`, diventeranno `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` e `https://pastebin.com/raw/example2`.

# Workshop

- Scarica le mod del Workshop dalla barra laterale tramite ID o URL dello Steam Workshop; puoi inserire più ID alla volta.
- Aggiorna dallo Steam Workshop scarica di nuovo il JSON di una mod già presente. L'opzione Forza l'aggiornamento sovrascrive anche un file locale più recente.

# Risoluzione dei problemi

- Il pannello Log sotto l'elenco registra ogni operazione e i suoi errori; espandilo per filtrare per livello e origine, cercare, copiare le voci o svuotarlo. Fai clic su una voce per selezionarne la mod.
- Il file di log `vault.log` si trova accanto al database. Aprilo dall'intestazione del pannello Log o dalla scheda Informazioni; allegalo alle segnalazioni di bug.
- Non compare nulla dopo aver cambiato cartella? Fai clic su Aggiorna. Ancora nulla? Controlla i percorsi delle cartelle in Impostazioni → Cartelle e le sottocartelle escluse.
- URL funzionanti falliscono quando molti download sono in corso insieme? Riduci i download simultanei in Impostazioni → Rete.
- I controlli degli URL e il controllo dopo il download verificano prima se ogni dominio è raggiungibile. Gli URL su un dominio irraggiungibile (offline o bloccato sulla tua rete) non vengono segnati come non validi, e un controllo degli URL che include un dominio del genere non viene salvato. Impostazioni → Rete → Controlla tutti i domini di mod e salvataggi verifica ogni dominio usato dalle tue mod e dai tuoi salvataggi.
