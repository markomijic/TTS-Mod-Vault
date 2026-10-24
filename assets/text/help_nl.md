# Aan de slag

TTS Mod Vault leest de mappen `Mods` en `Saves` van Tabletop Simulator, toont elke mod, save en elk opgeslagen object met de status van de assetbestanden, en laat je ontbrekende bestanden downloaden, `.ttsmod`-back-ups maken en terugzetten.

- Stel de mappen in onder Instellingen → Mappen. Een back-upmap is optioneel, maar nodig om de back-upstatus tussen opstarten te onthouden.
- De bibliotheek wordt bij het opstarten geïndexeerd; klik op Vernieuwen in de zijbalk nadat je buiten de app bestanden hebt gewijzigd. "Vault-cache wissen" leest alle JSON-bestanden opnieuw in.
- Mods, Saves, Opgeslagen objecten en Back-ups zijn tabbladen boven de lijst. Opgeslagen objecten verschijnen als ze aan staan onder Instellingen → Functies, Back-ups zodra er een back-upmap is ingesteld.

# Bibliotheek

- Klik links op een mod om de assets en acties te zien
- Klik rechts op een mod voor meer acties (downloaden, back-up maken, map openen, hernoemen, verwijderen, ...)
- Ctrl+klik (Cmd+klik op macOS) om meerdere mods te selecteren voor bulkacties
- Beweeg over het back-uppictogram van een mod om de back-updatum en het aantal assets te zien
- Beweeg over de typekeuze om te zien hoeveel mods, saves en opgeslagen objecten er zijn
- Zoek, sorteer en filter via de werkbalk; bulkacties houden rekening met de zoektekst en filters
- Toetsenbord: Ctrl+F gaat naar zoeken, F5 vernieuwt, Esc wist de selectie, Delete verwijdert de geselecteerde mod na bevestiging

# Geselecteerde mod

Het rechterpaneel toont de assets van de geselecteerde mod, gegroepeerd per type. Kleuren van URL's:

- Rood: het assetbestand ontbreekt
- Groen: het assetbestand is gedownload
- Oranje: een URL-controle heeft de URL als ongeldig gemarkeerd
- Gemarkeerd: de URL waarop je het laatst hebt geklikt

Acties:

- Klik links of rechts op een URL voor opties (openen, kopiëren, downloaden, vervangen, bestand verwijderen)
- Dubbelklik op een PDF-miniatuur om het bestand te openen
- Alles downloaden: downloadt alle ontbrekende assetbestanden. Bestanden die daarna nog ontbreken worden gecontroleerd: het venster "Resultaten van downloadcontrole" toont onbereikbare domeinen en URL's die niet meer werken. Je kunt dit uitzetten onder Instellingen → Netwerk → Ontbrekende bestanden controleren na downloads
- "3 ontbreken, 2 ongeldig" op een kaart: 3 bestanden ontbreken, en een URL-controle heeft vastgesteld dat 2 van hun URL's kapot zijn, dus die kunnen niet worden gedownload
- Back-up maken: maakt een back-up van de gedownloade assetbestanden
- Audio-assets kun je algemeen uitsluiten onder Instellingen → Functies, en per mod aanpassen via het rechtsklikmenu

# Back-ups

- Back-ups zijn `.ttsmod`-archieven met de JSON van de mod, de afbeelding en alle gedownloade assetbestanden.
- De back-upstatus vergelijkt de back-up met de mod: actueel, verouderd (de JSON is na de back-up gewijzigd) of aantal assets komt niet overeen.
- Back-ups importeren in de zijbalk zet archieven terug in de map Mods. JSON importeren voegt een mod toe vanuit een JSON-bestand.
- Bulkback-ups bieden Overslaan, Vervangen en Vervangen als verouderd, en kunnen daarna desgewenst de bestanden van de mod verwijderen.

# URL's bijwerken

De functie URL's bijwerken vervangt het begin van URL's, of zelfs hele URL's, van het "Oude voorvoegsel" naar het "Nieuwe voorvoegsel".

Je kunt meerdere oude voorvoegsels invoeren, gescheiden door het teken `|` (verticale streep). Onder Instellingen → Voorinstellingen voor URL-updates kun je voorinstellingen maken die daarna in het venster URL's bijwerken worden aangeboden.

Met één oud voorvoegsel:

- Oud voorvoegsel: `http://pastebin.com/raw.php?i=`
- Nieuw voorvoegsel: `https://pastebin.com/raw/`

Als je mod `http://pastebin.com/raw.php?i=1234` en `http://pastebin.com/raw.php?i=example` bevat, worden die `https://pastebin.com/raw/1234` en `https://pastebin.com/raw/example`.

Met meerdere oude voorvoegsels:

- Oude voorvoegsels: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Nieuw voorvoegsel: `https://pastebin.com/raw/`

Als je mod `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` en `http://pastebin.com/example2` bevat, worden die `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` en `https://pastebin.com/raw/example2`.

# Workshop

- Download Workshop-mods via de zijbalk met hun Steam Workshop-ID of URL; je kunt meerdere ID's tegelijk invoeren.
- Bijwerken vanuit Steam Workshop downloadt de JSON van een al aanwezige mod opnieuw. De optie Bijwerken forceren overschrijft ook een nieuwer lokaal bestand.

# Problemen oplossen

- Het logboekpaneel onder de lijst houdt elke bewerking en de fouten ervan bij; klap het uit om te filteren op niveau en bron, te zoeken, items te kopiëren of het te wissen. Klik op een item om de bijbehorende mod te selecteren.
- Het logbestand `vault.log` staat naast de database. Open het via de kop van het logboekpaneel of het tabblad Over; voeg het toe aan bugmeldingen.
- Verschijnt er niets na het wijzigen van een map? Klik op Vernieuwen. Nog steeds niets? Controleer de mappaden onder Instellingen → Mappen en de uitgesloten submappen.
- Mislukken werkende URL's als er veel downloads tegelijk lopen? Verlaag het aantal gelijktijdige downloads onder Instellingen → Netwerk.
- URL-controles en de controle na een download testen eerst of elk domein bereikbaar is. URL's op een onbereikbaar domein (offline of geblokkeerd op je netwerk) worden niet als ongeldig gemarkeerd, en een URL-controle met zo'n domein wordt niet opgeslagen. Instellingen → Netwerk → Alle domeinen van mods en saves controleren test elk domein dat je mods en saves gebruiken.
