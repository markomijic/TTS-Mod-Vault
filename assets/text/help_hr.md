# Početak rada

TTS Mod Vault čita mape `Mods` i `Saves` igre Tabletop Simulator, prikazuje svaki mod, spremanje i spremljeni objekt sa stanjem njihovih datoteka resursa te omogućuje preuzimanje datoteka koje nedostaju, izradu `.ttsmod` sigurnosnih kopija i njihovo vraćanje.

- Mape postavite u Postavke → Mape. Mapa sigurnosnih kopija nije obvezna, ali je potrebna da bi se stanje kopija pamtilo između pokretanja.
- Biblioteka se indeksira pri pokretanju; nakon promjene datoteka izvan aplikacije pritisnite Osvježi na bočnoj traci. „Očisti Vault predmemoriju“ ponovno čita svaku JSON datoteku.
- Modovi, Spremanja, Spremljeni objekti i Kopije kartice su iznad popisa. Spremljeni objekti pojavljuju se kad se uključe u Postavke → Značajke, a Kopije kad je postavljena mapa sigurnosnih kopija.

# Biblioteka

- Lijevi klik na mod prikazuje njegove resurse i radnje
- Desni klik na mod otvara više radnji (preuzimanje, kopija, otvaranje mape, preimenovanje, brisanje, ...)
- Ctrl + klik (Cmd + klik na macOS-u) odabire više modova za skupne radnje
- Zadržite pokazivač na ikoni kopije moda za datum kopije i broj resursa
- Zadržite pokazivač na odabiru vrste za broj modova, spremanja i spremljenih objekata
- Pretražujte, poredajte i filtrirajte alatnom trakom; skupne radnje poštuju tekst pretrage i filtre
- Tipkovnica: Ctrl+F postavlja fokus na pretragu, F5 osvježava, Esc poništava odabir, Delete uklanja odabrani mod nakon potvrde

# Odabrani mod

Desna ploča navodi resurse odabranog moda grupirane po vrsti. Boje URL-ova:

- Crvena: datoteka resursa nedostaje
- Zelena: datoteka resursa je preuzeta
- Narančasta: provjera URL-a označila je URL kao neispravan
- Istaknuto: URL na koji ste zadnji put kliknuli

Radnje:

- Lijevi ili desni klik na URL otvara mogućnosti (otvori, kopiraj, preuzmi, zamijeni, izbriši datoteku)
- Dvoklik na sličicu PDF-a otvara datoteku
- Preuzmi sve: preuzima svaku datoteku resursa koja nedostaje
- Sigurnosna kopija: izrađuje kopiju iz preuzetih datoteka resursa
- Zvučni resursi mogu se globalno izuzeti u Postavke → Značajke, a za pojedini mod nadjačati iz njegova kontekstnog izbornika

# Sigurnosne kopije

- Sigurnosne kopije su `.ttsmod` arhive koje sadrže JSON moda, njegovu sliku i svaku preuzetu datoteku resursa.
- Stanje kopije uspoređuje kopiju s modom: ažurno, zastarjelo (JSON se promijenio nakon kopije) ili neusklađen broj resursa.
- Uvezi kopije na bočnoj traci vraća arhive u mapu Mods. Uvezi JSON dodaje mod iz JSON datoteke.
- Skupna kopija nudi preskakanje, zamjenu i zamjenu ako je zastarjela, uz neobavezno brisanje resursa nakon toga.

# Ažuriraj URL-ove

Značajka Ažuriraj URL-ove zamjenjuje početak URL-ova, ili čak cijele URL-ove, „starog prefiksa“ „novim prefiksom“.

Više starih prefiksa možete unijeti odvajajući ih znakom `|` (okomita crta). U Postavke → Predlošci URL-ova možete izraditi predloške koji se zatim nude u dijalogu Ažuriraj URL-ove.

S jednim starim prefiksom:

- Stari prefiks: `http://pastebin.com/raw.php?i=`
- Novi prefiks: `https://pastebin.com/raw/`

Ako vaš mod sadrži `http://pastebin.com/raw.php?i=1234` i `http://pastebin.com/raw.php?i=example`, bit će ažurirani u `https://pastebin.com/raw/1234` i `https://pastebin.com/raw/example`.

S više starih prefiksa:

- Stari prefiksi: `http://pastebin.com/raw.php?i=|http://pastebin.com/raw/|http://pastebin.com/`
- Novi prefiks: `https://pastebin.com/raw/`

Ako vaš mod sadrži `http://pastebin.com/raw.php?i=abcd`, `http://pastebin.com/raw/5678` i `http://pastebin.com/example2`, bit će ažurirani u `https://pastebin.com/raw/abcd`, `https://pastebin.com/raw/5678` i `https://pastebin.com/raw/example2`.

# Workshop

- Preuzmite Workshop modove prema Steam Workshop ID-u ili URL-u s bočne trake; može se unijeti više ID-ova odjednom.
- Ažuriranje s Workshopa ponovno preuzima JSON moda koji već postoji. Opcija prisilnog ažuriranja prepisuje noviju lokalnu datoteku.

# Rješavanje problema

- Ploča dnevnika ispod popisa bilježi svaku radnju s njezinim pogreškama; proširite je da filtrirate po razini i izvoru, pretražujete, kopirate zapise ili je očistite. Klik na zapis odabire njegov mod.
- Datoteka dnevnika `vault.log` nalazi se uz bazu podataka. Otvorite je iz zaglavlja ploče dnevnika ili s kartice O programu; priložite je prijavama pogrešaka.
- Ništa se ne prikazuje nakon promjene mape? Pritisnite Osvježi. I dalje ništa? Provjerite putanje mapa u Postavke → Mape i izuzete podmape.
- Preuzimanja ispravnih URL-ova ne uspijevaju kad se mnogi izvode odjednom? Smanjite istodobna preuzimanja u Postavke → Mreža.
