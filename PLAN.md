# Potpurri – grundplan

> Status: **godkänd** 2026-10-24. Planen kan fortfarande justeras under arbetet.

## Vision

En enkel, snabb och stabil iPad-app för en solomusiker som spelar från PDF/bild-låtblad.
Gör få saker – men gör dem pålitligt på scen. Ersätter OnSong för dagligt bruk.

**Principer**
1. Stabilitet före funktioner. Appen får aldrig hänga sig under en spelning.
2. Få knappar, stor text, tydligt scenläge.
3. Originalfiler ändras aldrig – alla ändringar sparas separat och kan ångras.

## Målgrupp
- I nuläget endast för användaren själv (installeras via Mac/TestFlight).
- Kan bli publik på App Store senare – därför byggs appen så att det inte kräver
  omskrivning (t.ex. utbytbar låttextkälla, inga hårdkodade personliga uppgifter).

## Plattform

- Endast iPad (användarens: iPad 13"), senaste iPadOS.
- Fungerar på både iPad 13" och vanlig iPad 11" (1180 × 820 punkter). Layouten anpassar sig:
  på 11" blir förslagsrutan lägre, lapparna hålls inom låtbladet och dialoger krymper så de
  får plats. Skissen har en växlare iPad 13″ / 11″ under förstoringsglaset.
- Utvecklas i Xcode (senaste) på användarens MacBook Pro.
- Swift + SwiftUI, PDFKit för visning, SwiftData för data, iCloud (CloudKit) för synk/backup.

## Funktioner i version 1

### 1. Bibliotek
- Import av PDF och bilder (JPG/PNG/HEIC) via Filer-appen (där Dropbox finns). Flera filer åt gången.
- Låtens namn = filnamnet (kan byta namn i appen).
- Sök på namn.
- Listan scrollas med fingret. Vid sidan av biblioteket finns ett **alfabet (A–Ö)** att dra
  fingret längs: bokstäverna närmast fingret förstoras som Dock på en Mac, en stor bokstav
  visas bredvid och listan hoppar direkt till bokstaven. (iPad har ingen vibrationsmotor,
  så en "tick" i fingret går inte – den stora bokstaven ger i stället en liten studs vid
  varje byte.) Bokstäver utan låtar är nedtonade.
- Sortering: namn, tillagd datum, senast spelad, mest spelad.
- **Färgfilter:** tryck på en eller flera färger. Låtar med någon av de valda färgerna
  visas, och de som har flest av färgerna hamnar först.
- **Anteckningar (t.ex. quizmanus):** textfiler (.txt) kan importeras från Filer eller
  delas direkt från Apples Anteckningar till Potpurri. De ligger i biblioteket med en
  egen ikon och kan läggas i Lådan (se nedan).
- Bilder behandlas som en sida i en låt.
- **Inga typikoner på låtarna** – om en låt är PDF, bild eller textlåt spelar ingen roll.
  Bara anteckningar (t.ex. quizmanus) har en liten ikon.
- **Statusfält vid import och indexering:** medan låtar importeras (eller låttext indexeras)
  visas ett fält längst ner i listan med förloppsstapel, "12 av 80", namnet på filen som
  hanteras just nu och ungefärlig tid kvar ("Ca 2 min kvar"). Tiden uppdateras varje
  sekund så man ser att appen inte har hängt sig. Appen går att använda under tiden.

### 1b. Import från OnSong-backup
- Potpurri kan öppna en OnSong-backupfil (.backup) från Filer/Dropbox. Filen är ett
  zip-arkiv med OnSongs databas (OnSong.sqlite3) och de PDF:er/bilder som lagts in.
- Efter inläsning visas en lista över alla låtar i backupen med kryssrutor. Låtar som redan
  finns i Potpurri (samma namn) är urkryssade från början. "Markera alla / inga".
- Låtar som är PDF/bild i OnSong blir vanliga låtar. Låtar skrivna direkt i OnSong
  (text med ackord, ChordPro) blir **textlåtar** med ackorden ovanför texten, som i OnSong.
- **Låtlistorna** från OnSong följer med (bara med de låtar som importeras).
- **Tonart och anteckningar** följer med där det går (tonart → låtens tonart, anteckningar
  → en gul lapp på låten).
- Så ser backupen ut (undersökt 2026-10-25, ~920 låtar varav ~320 borttagna):
  - Tabellen `Song`: `title`, `key`, `content` (låttext med ackord), `filename` + `usefile`
    (låten visar en fil: PDF, bild eller .txt), `notes` (JSON med OnSongs lappar och
    markeringar), `deleted` (hoppas över), `duration`.
  - Filerna ligger i arkivets rot med samma namn som `filename`. Varje PDF har också en
    `….maintain.inverted.pdf` (OnSongs mörka kopia) som hoppas över.
  - `.txt`-filerna är quizmanus i UTF-16 → blir **anteckningar** (till Lådan).
- **Textlåtar ser ut som låtbladen:** vanligt (proportionellt) typsnitt, titel överst,
  tonart, rubriker i versaler och ackord i fetstil ovanför ordet de hör till. Ackord på
  en egen rad ovanför texten placeras om till rätt ord.
- **Allt syns alltid:** textlåtar och anteckningar bryter raderna (ackorden följer med sitt
  ord) och textstorleken följer vyns bredd – större när biblioteket är stängt, mindre när
  det är öppet. Text utan ackord från OnSong räknas som anteckning (quizmanus).
- **Quizmanus formateras automatiskt** (textfiler saknar formatering): rader med nummer
  och versaler ("1 VÄLKOMMEN OMBORD") blir stora feta rubriker, frågor ("A)", "B)", "A:")
  vanlig text, svar ("C  Mausoleum") rosa och feta med en bock, "LÅT Benjamin" nedtonat.
  - Låtlistor: `SongSet` (titel) + `SongSetItem` (låt, ordning, `divider` = setgräns).
  - Filnamn med å/ä/ö är UTF-8 i decomposed form och normaliseras vid import.
- Statusfältet visas under hela inläsningen (packa upp, läsa databasen, kopiera filer).

### 2. Låtlistor
- Fliken Låtlistor visar alla listor. **Plustecknet** skapar en ny lista som man döper själv.
- **Lägga till låtar:** en vy med färgfilter (samma som i biblioteket) och kryssrutor.
  Välj "Markera alla" för att ta med alla som matchar, eller kryssa i bara några,
  och tryck "Lägg till".
- Byta namn på, **duplicera** och ta bort listor. En kopia (t.ex. av "Bröllop") blir en
  ny lista med samma låtar i samma ordning, som man döper om och ändrar fritt.
- Samma låt kan ligga i flera listor.
- Egen ordning: dra i handtaget ≡ längst till vänster på raden (låt eller setgräns) –
  raden följer fingret och en rosa linje visar var den hamnar. Håll in en låt och välj
  "Ta bort ur listan" för att ta bort den.
- **Dra och släpp mellan listorna:** håll in en låt (eller dra den åt höger) så lossnar
  den och följer fingret. Den kan släppas:
  - **i låtlistan** – en rosa linje visar var den hamnar, även i ett annat set. Kom den
    från samma lista flyttas den, annars läggs den in på platsen.
  - **i förslagsrutan** – rutan får en rosa ram; låten fästs överst bland förslagen för
    kvällen (med en nål som tar bort den igen). Fungerar från låtlistan och biblioteket.
  - **i lådan** (se Lådan).
  Från förslagsrutan kan låtar dras till låtlistan och lådan.
- **Set:** en låtlista kan delas in i Set 1, 2, 3, 4 … med **setgränser** – en tydlig linje
  med rubrik ("Set 2 · 5 låtar · 18 min"). Knappen "+ Set" lägger till en gräns.
  Både låtar och setgränser dras upp och ner tills man är nöjd; × tar bort en gräns.
  Varje set har en **svag egen färgton** i bakgrunden så att seten syns tydligt isär.
  Numreringen börjar om i varje set, och varje set visar antal låtar och total speltid
  (från låtarnas autoscroll-längd).

### 3. Visningsläge (layout)
- **Liggande:** lista till vänster (bibliotek eller aktuell låtlista), låten till höger. Tryck i listan = byt låt direkt.
- **Stående:** låten i helskärm, listan dras fram som meny.
- Flersidiga låtar visas som en lång scrollbar vy.
- **All scroll glider vidare** en bit när man släpper fingret (mjuk inbromsning, som i
  vanliga iPad-listor) – i låten, förhandsrutan, låtlistor, biblioteket och lådan – så
  att man kan ta nytt tag utan att det stannar tvärt. Ett nytt tryck stoppar glidningen.
- **Studs vid kanten:** när man når början eller slutet studsar innehållet lite (som i
  iPadens egna listor) – drar man förbi kanten följer det med som ett gummiband och
  fjädrar tillbaka när man släpper. Då syns det tydligt att man nått slutet och att
  scrollen inte har fastnat.
- Både huvudlåten och låten i förhandsrutan kan scrollas var för sig med fingret.
- **Zoom:** huvudlåten och förhandsrutan zoomas var för sig med två fingrar (nyp),
  50–200 %, så att man själv väljer hur mycket som syns i varje fönster.
  Inga zoomknappar – bara nyp (PDF:er, bilder och textlåtar). **Appen kommer ihåg zoomen per låt** (både i huvudvyn
  och i förhandsrutan) och återställer den när låten öppnas igen. Notes, markeringar och ackord
  följer med i zoomen.
- Nästa låt i listan förladdas så att byten går direkt.

### 2b. Statistik
- En statistikvy (nås från ⋯-menyn) som bygger på kvällsloggarna:
  - **Mest spelade låtar** (antal gånger och senast spelad).
  - **Mest körda färgkoder** – hur stor andel av det spelade som var t.ex. Upptempo eller Allsång.
- Kan visas för valfri period (senaste månaden, året, allt).

### 3b. Klocka
- En **tydlig digital klocka** (TT:MM, 24-timmars, stora siffror) i sidospaltens topp.
- När sidospalten är dold visas klockan i en liten etikett överst i mitten av låtvyn.
- **Nedräkningstimer** (upp till 60 min) under klockan, t.ex. för att hålla koll på setet:
  tryck "Timer", välj 5–60 min (snabbval eller reglage). Tiden kvar visas under klockan och
  blir rosa när den når noll. Tryck igen för att stoppa.

### 4. Autoscroll (som i OnSong)
- En egen rund knapp **längst ner i högra hörnet** – ingen meny behövs.
  Knappen visar låtens längd (t.ex. 3:20) och en ring runt kanten som fylls på i takt
  med hur långt låten har kommit.
- **Tryck** = starta / pausa.
- **Håll inne** = ett reglage för **låtens längd** visas (0:30–10:00). **Dra åt höger för
  längre**, åt vänster för kortare. Scrollen går sedan så att hela låten passerar på
  exakt den tiden.
- Längden **sparas per låt**. Reglaget går 0:30–5:00 i steg om en sekund (mjukt att dra).

### 4b. Scen-trygghet
- **Scenlås:** håll inne LP-loggan → appen låses så att fingrarna bara kan scrolla, byta
  låt, starta/pausa autoscroll och spela ljud. Ackord, notes och markeringar kan inte
  flyttas av misstag. Håll inne igen för att låsa upp. En tydlig "Scenlås"-etikett visas.
- **Skärmen släcks aldrig** medan Potpurri är öppen.
- **Ångra:** de senaste ändringarna av ackord, markeringar, notes och grupper kan ångras
  (och göras om).
- **Kvällslogg:** varje spelning sparas som en logg med vilka låtar som spelades, i ordning.
  "Ny spelning" startar en ny logg som automatiskt heter datum och tid (t.ex.
  "Lör 24 okt 21:15") – ingen fråga om namn. Loggen kan döpas om i efterhand. Gamla loggar kan bläddras
  igenom, t.ex. för att se vad som spelades senast på samma ställe.
- **Säkerhetskopia till fil:** en knapp sparar hela biblioteket (låtar, listor, notes,
  ackord, ljud, inställningar) som en fil i Filer – och kan läsa in den igen, t.ex. på en
  ny iPad. Utöver iCloud.

### 4c. Hopplinjer (långa texter och medleyn)
- Upp till **10 hopplinjer** per låt, numrerade 1–10. Läggs till under ⋯ → Hopplinjer →
  "+ Linje" (hamnar längst ner på skärmen, dvs. där stycket man ser slutar) och dras sedan
  i sitt nummer till rätt plats. Tryck på numret för att byta nummer eller ta bort linjen.
- **Ett tryck på skärmen**, pedalen eller **AirTurn** (piltangenter/Page Down) hoppar så att
  nästa linje hamnar nära toppen, med lite av texten ovanför kvar som sammanhang. Ordningen följer numren (1, 2, 3 …), inte var linjerna
  ligger – så man kan hoppa tillbaka till t.ex. en refräng eller mellan text och ackord.
- Efter sista linjen går pedalen vidare till nästa låt. Bakåt hoppar till förra linjen.
- Fungerar ihop med zoom: zooma så att ett stycke fyller skärmen, sätt en linje längst ner.

### 5. Bläddringspedal (kompatibilitet)
- Stöd för vanliga Bluetooth-pedaler (som skickar piltangenter/Page Down).
- Framåt: bläddra en skärmsida ner; i slutet av låten → nästa låt i listan.
- Bakåt (om två pedaler): motsvarande bakåt.
- Fungerar även med externt tangentbord.

### 6. Sticky notes
- Knapp skapar ny note. Flera notes per låt.
- **Flytta:** dra i noten. **Storlek:** dra i hörnet nere till höger (bredd/höjd fritt).
- **Redigera:** ett tryck på noten → ruta med text, färg, förankring och "Ta bort".
- Text skrivs med skärmtangentbord eller Bluetooth-tangentbord.
- **Textanpassning:** användarens radbrytningar behålls, och teckenstorleken
  räknas om automatiskt så att all text alltid får plats i noten
  (mindre note → mindre text, mer text → mindre text).
- **Textstorlek:** i redigeringsrutan väljer man "Anpassa texten efter lappen" (standard)
  eller en låst storlek med ett reglage (10–72 pt).
- Typiskt innehåll är korta rader, t.ex. "REF: E G A B". Vanligt typsnitt räcker.
- Färgval (t.ex. gul, rosa, blå, grön, orange, vit).
- Per note väljs förankring:
  - *Följer sidan* – sitter på en plats i låten och scrollar med.
  - *Fast på skärmen* – ligger still medan låten scrollar.
- Visa/dölj alla notes med en knapp.
- **Notes hör till den låt de skapades i** – både de som följer sidan och de som sitter
  fast på skärmen – och visas bara när den låten är öppen.

### 7. Redigera (textlåtar)
- Byta låttitel i biblioteket (enkelt namnbyte).
- **"Gör redigerbar":** texten plockas ur en PDF (t.ex. gjord i Word) och låten
  blir en *textlåt* som kan redigeras fritt – samma princip som i OnSong.
  PDF:ens ursprungliga layout ersätts av appens textvisning.
- Originalfilen sparas alltid och låten kan återställas till PDF-visning.
- Textlåtar har samma funktioner som PDF-låtar: notes, autoscroll, mörkt läge.
  Dessutom justerbar textstorlek (sparas per låt).
- Bilder kan inte göras om till text, men kan ha notes.

### 8. Färgkoder och låtförslag
Syfte: att det aldrig ska bli tyst mellan låtarna – när en låt börjar ska det synas
vilka låtar som passar efter, eller som medley.

**Färgkoder**
- **Högst 5 färgkoder**, med egna namn, t.ex. "Upptempo".
- En låt kan ha flera färgkoder.
- **Sätta färger – tre sätt:**
  1. **Direkt i listan:** knappen "Färger" ovanför kolumnerna slår på färgläge. Då kan man
     trycka i en låts ruta under en kolumn för att tända/släcka färgen. (Av som standard,
     så att inget ändras av misstag under spelning.)
  2. **Inne i låten:** Redigera → Färgkoder visar fem stora knappar för låten som är öppen.
  3. **Många på en gång:** i färgläget kryssar man i flera låtar och trycker på en
     kolumnrubrik → alla markerade får färgen (har alla redan den tas den bort).
- **Byta namn på en färg:** håll in kolumnrubriken och skriv det nya namnet.
- **Bara färger som används får en kolumn** – gäller alla färger och varje lista för sig: har ingen låt i listan t.ex. lila syns inte den
  kolumnen (i färgläget visas alla fem så att man kan börja använda en ny färg).
- Färgkoderna har en fast, låst ordning och visas som **kolumner** i listorna: tunna
  linjer mellan kolumnerna och en liten rubrik (färgens namn) överst. Varje låt har en
  prick i de kolumner den hör till – lila alltid längst till höger, rosa näst längst.

**Förslagsruta (liggande läge)**
- Egen ruta i vänsterspalten, under låtlistan, alltid synlig.
- Överst i rutan visas låtens egna färgkoder som knappar. **Man väljer själv vilka
  färger som styr förslagen** (t.ex. bara lila, eller lila + gul).
- **Valet följer med** när man byter låt: nästa låt får automatiskt samma valda färger
  (de av dem som den låten har). Har den ingen av dem används alla dess färger.
- Förslagen är låtar som har någon av de valda färgerna. De som har flest av dem
  (t.ex. både lila och gul) kommer först, sedan efter namn.
- **Låtar som redan spelats under kvällen visas aldrig igen i förslagen** (inte heller i
  lyckohjulet) förrän man trycker "Ny spelning". I biblioteket och låtlistorna gråmarkeras
  de i stället, men kan fortfarande väljas där.
- En låt räknas som spelad – och gråmarkeras – först när den varit huvudlåt i 30 sekunder
  i sträck. Byter man innan dess blir den inte grå.
- Knappen "Ny spelning" nollställer gråmarkeringarna och de fästa förslagen. **Efter 12
  timmar** börjar en ny spelning automatiskt.
- Förslagsrutan heter **Next** och har **samma färgrubriker som låtlistan**; man trycker på en rubrik för att
  välja vilka färger som styr förslagen (valda är markerade).

**Förhandsruta**
- Tryck på ett förslag → låten öppnas i en förhandsruta under huvudlåten.
- **Förslagsrutan kan dras större/mindre** i handtaget ovanför den (mindre ruta = fler låtar syns i listan).
- Förhandsrutan är mindre än huvudlåten och ändras i storlek genom att dra i dess
  överkant (fritt, mellan en min- och maxhöjd).
- Autoscroll i huvudlåten fortsätter medan förhandsrutan visas.
- Tryck på låten i förhandsrutan → förslaget ersätter huvudlåten (ingen separat knapp).
- Förhandsrutan kan stängas (t.ex. svep nedåt) utan att byta låt.
- Låtlistan ändras inte när ett förslag spelas. När ett förslag är huvudlåt
  bläddrar pedalen bara inom förslaget (går inte vidare till nästa låt i listan).

### 9. Markeringspennor
- Genomskinliga överstrykningspennor i flera färger (gul, grön, rosa, blå, orange).
- Ett drag med pennan blir alltid en rak, vågrät markering över textraden.
- Ritas med fingret när pennläget är på (av = vanlig scrollning).
- När pennan är på visas en tydlig knapp "Penna på · Stäng av" bredvid de flytande knapparna.
- Sudd för att ta bort markeringar.
- Markeringarna följer låten när den scrollar och sparas per låt.

### 10. Ackordstämplar
- Varje låt har en **tonart** (väljs i ackordpaletten, dur eller moll).
- Ackordpaletten kan **flyttas** genom att dra i dess handtag.
- **Transponera alla:** knapparna ♭/♯ i paletten sänker/höjer samtliga ackord på låten
  (och låtens tonart) ett halvt tonsteg per tryck, med rätt stavning för den nya tonarten.
- Ackordpaletten visar överst **ackorden i låtens tonart**, i ordning efter hur vanliga
  de är (i G: G, C, D, Em, Am, Bm, D7, F#dim) – färdiga att dra ut direkt.
  Under dem finns C-skalans toner C D E F G A B för allt annat.
- Dra ett ackord från paletten och släpp det på låten. **Ackorden lägger sig på en rak
  rad:** hamnar ett ackord nära höjden för andra ackord så snäpper det till samma rad
  (som markeringspennan). I PDF:er/textlåtar snäpper de även till raden ovanför textraden.
- **Håll inne** ett utplacerat ackord → en meny öppnas runt det. Dra fingret åt ett håll
  och släpp på ett val (eller släpp direkt och tryck i menyn):
  - **Vänster – förtecken:** ♯ höj, ♮ ingen, ♭ sänk.
  - **Höger – färgning:** vanligaste först (dur, m, 7, m7, maj7, sus4, sus2, add9);
    "Fler" visar ovanligare (6, m6, 9, m9, maj9, 7sus4, dim, dim7, m7b5, aug, 11, 13).
  - **Ner – bas:** ingen, eller C, C#, D, Eb, E, F, F#, G, G#, A, Bb, B (t.ex. D/F#).
  - **Kopiera / Ta bort** ligger längst ner, under basnoterna, så att de inte är i vägen.
- Kort drag flyttar ackordet.
- **Välj ackord:** knappen "Välj ackord" i paletten → tryck på de ackord som ska med
  (eller dra en ruta runt dem) → **Gruppera**, Dela upp, Kopiera eller Ta bort.
- **Kopiera sekvenser:** välj ackord → Kopiera → tryck där sekvensen ska klistras in
  (t.ex. i vers 2). Avstånden mellan ackorden behålls. Rutan försvinner direkt efter
  inklistringen.
- **Grupper:** en inklistrad sekvens blir automatiskt en grupp. Ackorden i en grupp sitter ihop och flyttas tillsammans,
  och "Kopiera" på ett grupperat ackord kopierar hela gruppen.
- **Lätt att få tag i grupper:** när ackordpaletten eller markeringsläget är öppet visas
  varje grupp som en tonad, streckad ram med en rosa flik "Grupp" ovanför. Man kan ta tag
  i fliken **eller var som helst i ramen** (även mellan ackorden) och dra hela gruppen.
- Ackordens tryckyta är minst 44 px hög, så de är lätta att träffa med fingret.
- Ackorden följer låten när den scrollar och sparas per låt.

### 11. Sök låttext och lägg till från webben
- **Sökfältet söker både på titel och låttext.** Texten i PDF:er läses in vid import
  (Word-PDF:er har riktig text). Bilder och inskannade blad textläses i iPaden
  (Apples inbyggda textigenkänning, utan internet), så även de blir sökbara.
- **Ingen träff → "Sök på webben".** Två vägar, utan att lämna appen:
  1. **Direktträffar** från en låttextdatabas (förslag: LRCLIB, gratis och utan konto)
     visas som en lista med titel och artist. Tryck → förhandsvisning → "Lägg till".
  2. **Inbyggd webbläsare**: välj **Google**, **AZLyrics** eller **Genius** (valet sparas).
     Knappen **"Hämta låttexten från sidan"** tar markerad text – eller, om inget är markerat,
     letar appen själv upp blocket som ser ut som en låttext (t.ex. Googles låttextruta).
     Texten visas för kontroll och kan rättas innan den läggs till som ny låt.
- Den nya låten blir en **textlåt** med titel/artist förifyllda och kan direkt få tonart,
  ackord, färgkoder och läggas i en låtlista.
- Endast låttext hämtas (inga ackord) – ackord läggs med ackordstämplarna.
- Låttexter är upphovsrättsskyddade. Appen är i nuläget för eget bruk, men kan bli
  publik senare. Därför byggs textkällan **utbytbar**: LRCLIB nu, och en licensierad
  tjänst (t.ex. Musixmatch) kan kopplas in utan att resten av appen ändras.

### 12. Animationer med LP:n
- **Start:** skivan snurrar upp i mitten (ca 1 s) och glider sedan upp till sin plats
  i sidospalten.
- **Under spelning:** LP:n i sidospalten snurrar långsamt medan autoscroll är igång och
  stannar mjukt vid paus.
- **Import:** egen animation – en pickup-arm som långsamt rör sig in över skivan från
  kanten mot mitten och fungerar som förloppsindikator ("57 av 200 låtar").
- **Ny spelning:** en snabb snurr när gråmarkeringarna nollställs.
- I sidospalten ersätter LP:n den runda duvloggan bredvid POTPURRI.
- **Tryck på LP-loggan – lyckohjul:** skivan snurrar snabbt, saktar in och markeringen
  hoppar mellan förslagen (med en lätt "tick" i fingret) tills den landar på en **slumpad
  låt** bland förslagen (med de valda färgerna; redan spelade låtar finns aldrig med). Låten
  öppnas direkt i förhandsrutan. Bra vid hjärnsläpp mellan två låtar.
- **Dubbeltryck – duvan flyger:** ikonduvan på etiketten lyfter, växer och **förvandlas
  till en riktig duva** (blågrå med skimrande hals, svartbandad stjärt) som flaxar i skurar
  och glider emellan i en båge över skärmen och lutar i svängarna. Den bromsar med
  vingarna uppåt, krymper, **smälter tillbaka till ikonens silhuett** och glider in i
  LP:ns etikett där den blir ikon igen. Ca 3,5 s. Ett påskägg. (`design/duva-flykt.png`
  visar vingslaget.)
- **Håll in** = scenlås (se ovan).

### 13. Soundboard (ljudklipp)
- Inspirerad av Soundboard Studio. Högtalarknapp bland de flytande knapparna öppnar en
  smal kolumn längs högerkanten med små färgade ljudknappar (ca 15 st, fler går att scrolla).
- **Tryck** = spela; tryck igen = stoppa direkt (ingen uttoning). Flera klipp kan spela samtidigt.
- En gemensam soundboard. Ljudens ordning ändras genom att dra dem i redigeringsläget.
  Knappen visar en förloppsrand medan klippet spelas. "Stoppa alla" längst ner.
- Ljuden importeras från **Filer** (mp3, m4a, wav, aiff m.fl.).
- **Redigera** (tydlig knapp "Redigera" överst i ljudkolumnen, tryck sedan på ett ljud):
  namn, färg (fast palett), **trimma** start/slut genom att dra i markörer på en
  vågform, **volym** −12 till +6 dB, förhandslyssna, byt ljudfil, ta bort.
- Originalfilen ändras aldrig – trim och volym sparas som inställningar.
- Ljudet går ut där iPaden spelar ljud (inbyggd högtalare, kabel eller Bluetooth till PA).

### 14. Lådan (låtar, quizmanus och anteckningar)
- Ett litet **handtag** i högerkanten av låtvyn. Dra ut det → en låda glider fram med
  innehållet: en anteckning (stor, lättläst text) eller **vilken låt som helst** ur
  biblioteket (låtbladet visas i lådan, går att scrolla och nypa-zooma). Skjut tillbaka den → lådan glider
  in och bromsar mjukt och långsamt i slutet. Ett tryck på handtaget öppnar/stänger.
- Lådan rymmer **en sak åt gången**; en ny ersätter den gamla.
- En låt eller anteckning i listan (bibliotek eller låtlista) **lossnar snabbt** – antingen
  genom att **dra den åt höger** (direkt, ingen väntan) eller hålla still ett kort ögonblick
  (ca 0,2 s). Lodrätt drag scrollar listan som vanligt. Den lossnade raden följer fingret
  och **släpps på lådan** – vid handtaget när lådan är stängd, eller var som helst på den
  öppna lådan (lådan lyser upp). Det nya innehållet ersätter det gamla. Anteckningar kan även läggas i lådan med ett tryck.
- **Skriva i lådan:** knappen "Skriv" i lådan.
  - För både **anteckningar** (t.ex. quizmanus) och **låtar** får man **välja** hur man vill
    skriva. För en anteckning: redigera texten direkt (poäng, svar …) eller gult fält.
    För en låt:
    - **Redigera låttexten** – en PDF med riktig text (t.ex. från Word) görs om till en
      textlåt som man skriver direkt i. Samma textlåt som i vanliga läget, så ändringen
      syns överallt; "Återställ PDF" går tillbaka. Går inte för bilder/inskannade blad
      utan text – det står då i valet.
    - **Skriv i gult fält** – egna anteckningar ("Mina anteckningar") ovanför låten;
      själva låten ändras inte.
  - "Klar" sparar. Det skrivna följer med låten/anteckningen och finns kvar nästa gång.
- När soundboarden är öppen lägger sig handtaget och lådan till vänster om den.

### 15. Spotify
- En knapp bland de flytande knapparna: **ett tryck spelar, ett tryck pausar** Spotify.
- Byggs med Spotifys officiella iOS-koppling (App Remote). Kräver att Spotify-appen är
  installerad och inloggad; första gången öppnas Spotify kort för att godkänna kopplingen.
  Spotify Premium rekommenderas (gratiskonton har begränsningar i vad som kan styras).
- Soundboard-ljud kan spelas samtidigt som Spotify (blandas, Spotify sänks inte).

### 16. Mörkt läge
- Låtar visas med mörk bakgrund och ljus text (PDF/bild inverteras, notes behåller sina färger).
- Kan slås av/på.

### 17. iCloud
- Låtfiler, notes, listor och inställningar synkas/säkerhetskopieras via iCloud.

### 18. Guide för nya användare
- Visas automatiskt första gången appen startas (efter LP-animationen).
- Steg för steg med en ljuskägla runt det som förklaras och ett kort bredvid: välkomst,
  låtlistor/bibliotek, sök, låtlistan, färgkoder, "Passar efter", låtbladet, autoscroll,
  fler funktioner (•••), ljudklipp, lådan, LP:n (slumpa/scenlås), Ny spelning, klart.
- Sök-steget berättar att låtar som inte finns i biblioteket hittas på nätet.
- "Passar efter"-steget berättar att ett valt förslag lägger sig i rutan under låtbladet
  och att man trycker på rutan när det är dags att byta låt.
- Prickar visar hur långt man kommit. Knappar: Nästa, Tillbaka och **Hoppa över guiden**.
- Tryck utanför kortet hoppar också över. Guiden kan visas igen under ••• → **Visa guiden**.
- Anpassar sig till skärmen (iPad 13" och 11").

## Utseende
- **Namn:** Potpurri (gammalt ord för medley). Undertitel "av Duva Event" (duvaevent.com).
- **Stil från hemsidan:** ren, luftig och minimalistisk. Vit bakgrund, svart text,
  tunt geometriskt sans-serif-typsnitt, rosa accentfärg.
- **Färger:** accent rosa `#FB91FF`, svart `#000000`, vit `#FFFFFF`.
  I mörkt läge: svart/mörkgrå bakgrund med rosa accent (påminner om scenljus).
- **Logga:** svart duva i profil i en cirkel med texten
  "TRUBADUR | BAND | QUIZ | KONFERENCIER" (`design/duva-logo.png`).
- **Ikon:** svart LP med spår, ljusreflex och tydlig kant mot mörk bakgrund; rosa etikett (`#FB91FF`) med duvan centrerad över mitthålet (hålet syns genom duvan) och texten POTPURRI nedtill (`design/potpurri-lp.svg`, animerad: `design/potpurri-lp.gif`).
- Menyer/bibliotek: följer iPaden, eller väljs ljust/mörkt i appen. Låtar har eget mörkt läge.
- **Vänsterspalt (liggande):** kan döljas med ett tryck och ändras i bredd.
  Innehåll uppifrån: flikar Bibliotek/Låtlistor → sökfält → låtlista → förslagsruta → "Ny spelning".
- Listrader: titel + färgkolumner med rubriker, normal textstorlek, inga miniatyrer.
- **Låtvy:** flytande knappar i ett hörn. Låtlisteknappen syns alltid under spelning;
  övriga funktioner ligger i en meny.
- Fem färgkoder. Notes och ljudklipp har en egen fast palett med 6–8 färger.
- Klickbar skiss tas fram och godkänns innan kodning.

## Utanför version 1
ChordPro-redigering, bandsynk, MIDI, metronom, backing tracks, Apple Pencil-ritning.

## Idéer på hyllan (kanske senare)
- **Ljusstyrning per låt:** när en låt väljs triggas en chase/preset i ljuset. Användarens
  Eurolite Bigfoot har ingen MIDI-ingång, så det kräver ny hårdvara. Två vägar:
  MIDI-signal per låt (kräver ljuskontroller med MIDI in) eller iPaden som ljusbord via en
  Art-Net-nod. Appen byggs så att en "skicka MIDI när låt väljs"-funktion kan läggas till
  utan omskrivning.

## Datamodell (översikt)
- **Song:** id, titel, tonart, längd (autoscroll), zoom (huvudvy/förhandsruta), typ (pdf/bild/text), originalfil, text (för textlåtar), textstorlek,
  tillagd, senast spelad, antal spelningar, scrollhastighet.
- **Setlist:** id, namn, ordnade poster (låt eller setgräns + position).
- **GigLog:** id, starttid (blir namnet), valfritt eget namn, spelade låtar med tid.
- **Document:** id, titel, text (importerade anteckningar/quizmanus).
- **ColorTag:** id, namn, färg, ordning (högst 5). Kopplas till låtar (många-till-många).
- Per låt sparas också vilka färger som styr förslagen.
- **SoundClip:** id, namn, färg, ljudfil, start, slut, volym (dB), ordning.
- **Highlight:** låt, sida, position, bredd, färg.
- **ChordStamp:** låt, sida, position, grundton, förtecken, färgning, basnot, grupp.
- **StickyNote:** låt, text, färg, rektangel, förankring (sida/skärm), sidnummer.

## Milstolpar
1. **Grund:** Xcode-projekt, struktur, import, bibliotek, visa PDF/bild.
2. **Layout & listor:** ✅ import från OnSong-backup, ✅ sidospalt med LP-logga, klocka och flikarna Låtlistor/Bibliotek, ✅ låtlistor (ny, byt namn, duplicera, ta bort, + Låtar, setgränser med färgton, dra för att ändra ordning), ✅ alfabet A–Ö, ✅ sortering, ✅ sök, ✅ liggande/stående (sidospalten dras fram i stående); kvar: dra låtar från biblioteket in i en lista (förslag och lådan kommer i milstolpe 4 och 7), lägga till via färgfilter (när färgkoderna finns i milstolpe 4).
3. **Spela:** ✅ autoscroll med låtlängd (rund knapp i hörnet, håll in för längd, sparas per låt), ✅ pedal/tangentbord, ✅ nästa/förra låt (följer listan man valde låten ur), ✅ förladdning, ✅ skärmen vaken, ✅ scenlås (håll in LP-loggan), ✅ klocka i låtvyn när sidospalten är dold, ✅ låt räknas som spelad efter 30 s.
4. **Färgkoder & förslag:** ✅ 5 färgkoder med egna namn (håll in rubriken), ✅ färgkolumner i listorna, ✅ färgläge (tryck i rutor, kryssa flera + tryck rubrik), ✅ färger inne i låten (palettknappen), ✅ färgfilter i biblioteket, ✅ förslagsruta "Passar efter" (valda färger följer med, spelade visas inte, fäst via håll in), ✅ förhandsruta (dra i kanten, Spela nu, svep ner = stäng), ✅ Ny spelning + antal spelade, ✅ spelade gråa i listorna. Kvar: dra låtar till förslagsrutan (fäst görs med håll in tills vidare).
5. **Notes, pennor & ackord:** steg 1 ✅ lappar (ny via pennknappen, dra, hörn = storlek, tryck = text/färg/förankring/ta bort, texten anpassar sig, dölj alla, OnSong-anteckningar blir lappar) och ✅ markeringspennor (5 färger, raka drag, sudd, två fingrar scrollar medan pennan är på); steg 2 ✅ ackordstämplar (⋯ → Ackord: palett med tonart och transponera ♭/♯, låtens ackord (C–B-raden borttagen), dra ut till låten – ackordet lyfts (rosa, större, skugga) medan det dras, snäpp till rad, tryck = meny med förtecken/färgning/bas/kopiera/ta bort, Välj ackord → gruppera/dela upp/kopiera/ta bort, klistra in med ett tryck, grupper med ram och flik – tryck på fliken "Grupp" för att dela upp, kopiera eller ta bort gruppen). Ackorden går bara att flytta när paletten är öppen. **Uppdatering:** ♭/♯ i paletten transponerar hela låten. Palettens tonart (t.ex. för refrängen) väljs i tonartsmenyn och ändrar inte ackord som redan ligger kvar – de har sin egen stavning (G i versen, Ab i refrängen). **Tonarten i listorna** är den låten börjar i (första ackordet). Ackord knuffas så att de aldrig överlappar, och "Jämna ut" (för valda ackord, en grupp eller en rad) fördelar dem jämnt. Storleken ställs med ett reglage eller "Som texten" (läser av textlåtens storlek eller PDF:ens vanligaste teckenstorlek). I "Välj ackord" kan man dra en ruta runt ackorden. Ursprungligt innehåll: notes (skapa/flytta/storlek/redigera/färg/förankring, textanpassning, dölj),
   markeringspennor, ackordstämplar (radsnäpp, grupper, kopiera, transponera).
6. **Redigera & webben:** ✅ sök i titel och låttext (PDF-text läses ut, bilder/inskannade textigenkänns i bakgrunden med statusfält), ✅ "Sök på webben" (LRCLIB-träffar med förhandsvisning + inbyggd Google-webbläsare där markerad text blir en ny låt), ✅ byt namn (håll in i listorna eller ⋯), ✅ Gör redigerbar / Återställ PDF, ✅ Redigera texten (textstorlek = nyp-zoom). Ursprungligt: sök i låttext, lägg till låt från webben, namnbyte, "Gör redigerbar" (PDF → textlåt), redigera text, textstorlek, återställ.
7. **Soundboard, Lådan, Spotify & animationer:** steg 1 ✅ soundboard (högtalarknapp, kolumn i högerkanten, spela/stoppa, Stoppa alla, Redigera: namn, färg, trimma på vågform, volym −12…+6 dB, lyssna, byt fil, ta bort, ordning), ✅ Lådan (handtag, dra ut/tryck, låt eller anteckning, dra dit från listorna eller "Lägg i lådan", Skriv: redigera texten eller gult fält), ✅ LP-animationer (start, snurr under autoscroll, snabb snurr vid Ny spelning, tryck = lyckohjul, dubbeltryck = duvan flyger, pickup-arm vid import). Steg 2: Spotify (kräver registrering hos Spotify). Ursprungligt: ljudklipp, anteckningar i Lådan, Spotify-knapp, LP-animationer.
8. **iCloud & säkerhet:** synk, säkerhetskopia till fil, ångra, kvällslogg.
9. **Finputs:** guide för nya användare, prestandatest med 200 låtar, scenläge, testning på iPad via Xcode.

Varje milstolpe ska gå att köra och testa på iPad innan nästa påbörjas.

## Sparas per låt
Allt som läggs på eller ställs in för en låt följer med låten och finns kvar nästa gång
den öppnas: notes, markeringar, ackord och grupper, tonart, zoom (huvudvy och
förhandsruta), autoscroll-längd, textstorlek (textlåtar), och färgkoder.
(Valet av förslagsfärger följer däremot med från låt till låt.)

## Underlag
- Biblioteket: ca 200 låtar, mest PDF:er gjorda i Word, några få bilder.

## Beslut
- PDF-redigering görs genom konvertering till textlåt (som OnSong), inte genom redigering ovanpå PDF:en.

## Öppna frågor
- Inga just nu.
