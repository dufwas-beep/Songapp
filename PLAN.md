# Potpurri – grundplan

> Status: under diskussion. Ingen kod skrivs förrän planen är godkänd.

## Vision

En enkel, snabb och stabil iPad-app för en solomusiker som spelar från PDF/bild-låtblad.
Gör få saker – men gör dem pålitligt på scen. Ersätter OnSong för dagligt bruk.

**Principer**
1. Stabilitet före funktioner. Appen får aldrig hänga sig under en spelning.
2. Få knappar, stor text, tydligt scenläge.
3. Originalfiler ändras aldrig – alla ändringar sparas separat och kan ångras.

## Plattform

- Endast iPad (användarens: iPad 13"), senaste iPadOS.
- Utvecklas i Xcode (senaste) på användarens MacBook Pro.
- Swift + SwiftUI, PDFKit för visning, SwiftData för data, iCloud (CloudKit) för synk/backup.

## Funktioner i version 1

### 1. Bibliotek
- Import av PDF och bilder (JPG/PNG/HEIC) via Filer-appen (där Dropbox finns). Flera filer åt gången.
- Låtens namn = filnamnet (kan byta namn i appen).
- Sök på namn.
- Sortering: namn, tillagd datum, senast spelad, mest spelad.
- Bilder behandlas som en sida i en låt.

### 2. Låtlistor
- Skapa, byta namn på, ta bort listor.
- Samma låt kan ligga i flera listor.
- Egen ordning genom att dra låtar.

### 3. Visningsläge (layout)
- **Liggande:** lista till vänster (bibliotek eller aktuell låtlista), låten till höger. Tryck i listan = byt låt direkt.
- **Stående:** låten i helskärm, listan dras fram som meny.
- Flersidiga låtar visas som en lång scrollbar vy.
- Både huvudlåten och låten i förhandsrutan kan scrollas var för sig med fingret.
- Nästa låt i listan förladdas så att byten går direkt.

### 4. Autoscroll
- Startas/stoppas med knapp.
- Hastighet justerbar och **sparas per låt**.

### 5. Bläddringspedal (kompatibilitet)
- Stöd för vanliga Bluetooth-pedaler (som skickar piltangenter/Page Down).
- Framåt: bläddra en skärmsida ner; i slutet av låten → nästa låt i listan.
- Bakåt (om två pedaler): motsvarande bakåt.
- Fungerar även med externt tangentbord.

### 6. Sticky notes
- Knapp skapar ny note. Flera notes per låt.
- Rektangel som kan flyttas och ändras i storlek (bredd/höjd fritt).
- Text skrivs med skärmtangentbord eller Bluetooth-tangentbord.
- **Textanpassning:** användarens radbrytningar behålls, och teckenstorleken
  räknas om automatiskt så att all text alltid får plats i noten
  (mindre note → mindre text, mer text → mindre text).
- Typiskt innehåll är korta rader, t.ex. "REF: E G A B". Vanligt typsnitt räcker.
- Färgval (t.ex. gul, rosa, blå, grön, orange, vit).
- Per note väljs förankring:
  - *Följer sidan* – sitter på en plats i låten och scrollar med.
  - *Fast på skärmen* – ligger still medan låten scrollar.
- Visa/dölj alla notes med en knapp.

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
- Egna färgkoder med namn, t.ex. "Röd = upptempo".
- En låt kan ha flera färgkoder.
- Biblioteket kan filtreras på färgkod.
- Färgkoderna har en fast, låst ordning. I listorna har varje
  färgkod alltid samma plats, så att prickarna bildar raka kolumner – t.ex. lila alltid
  längst till höger, rosa näst längst. Saknas en färgkod lämnas platsen tom.

**Förslagsruta (liggande läge)**
- Egen ruta i vänsterspalten, under låtlistan, alltid synlig.
- Visar låtar som delar minst en färgkod med låten som spelas – en enda lista,
  sorterad på namn. Varje låt visar sina färgkoder som färgmarkeringar.
- Låtar som redan spelats under kvällen gråmarkeras men kan fortfarande väljas.
- En låt räknas som spelad när den varit huvudlåt i minst 30 sekunder.
- Knappen "Ny spelning" nollställer gråmarkeringarna.

**Förhandsruta**
- Tryck på ett förslag → låten öppnas i en förhandsruta under huvudlåten.
- Förhandsrutan är mindre än huvudlåten och ändras i storlek genom att dra i dess
  överkant (fritt, mellan en min- och maxhöjd).
- Autoscroll i huvudlåten fortsätter medan förhandsrutan visas.
- Tryck på förhandsrutan → förslaget ersätter huvudlåten.
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
- Ackordpaletten visar överst **ackorden i låtens tonart**, i ordning efter hur vanliga
  de är (i G: G, C, D, Em, Am, Bm, D7, F#dim) – färdiga att dra ut direkt.
  Under dem finns C-skalans toner C D E F G A B för allt annat.
- Dra ett ackord från paletten och släpp det var som helst på låten.
- **Håll inne** ett utplacerat ackord → en meny öppnas runt det. Dra fingret åt ett håll
  och släpp på ett val (eller släpp direkt och tryck i menyn):
  - **Vänster – förtecken:** ♯ höj, ♮ ingen, ♭ sänk.
  - **Höger – färgning:** vanligaste först (dur, m, 7, m7, maj7, sus4, sus2, add9);
    "Fler" visar ovanligare (6, m6, 9, m9, maj9, 7sus4, dim, dim7, m7b5, aug, 11, 13).
  - **Ner – bas:** ingen, eller C, C#, D, Eb, E, F, F#, G, G#, A, Bb, B (t.ex. D/F#).
  - **Upp – kopiera / ta bort.**
- Kort drag flyttar ackordet.
- **Kopiera sekvenser:** "Markera och kopiera" → dra en ruta runt flera ackord (eller tryck
  på dem) → Kopiera → tryck där sekvensen ska klistras in (t.ex. i vers 2). Avstånden
  mellan ackorden behålls. Kan klistras in flera gånger.
- Ackorden följer låten när den scrollar och sparas per låt.

### 11. Mörkt läge
- Låtar visas med mörk bakgrund och ljus text (PDF/bild inverteras, notes behåller sina färger).
- Kan slås av/på.

### 12. iCloud
- Låtfiler, notes, listor och inställningar synkas/säkerhetskopieras via iCloud.

## Utseende
- **Namn:** Potpurri (gammalt ord för medley). Undertitel "av Duva Event" (duvaevent.com).
- **Stil från hemsidan:** ren, luftig och minimalistisk. Vit bakgrund, svart text,
  tunt geometriskt sans-serif-typsnitt, rosa accentfärg.
- **Färger:** accent rosa `#FB91FF`, svart `#000000`, vit `#FFFFFF`.
  I mörkt läge: svart/mörkgrå bakgrund med rosa accent (påminner om scenljus).
- **Logga:** svart duva i profil i en cirkel med texten
  "TRUBADUR | BAND | QUIZ | KONFERENCIER" (`design/duva-logo.png`).
- **Ikon:** rosa duva (`#FB91FF`) på svart bakgrund, utan texten runt om.
- Menyer/bibliotek: följer iPaden, eller väljs ljust/mörkt i appen. Låtar har eget mörkt läge.
- **Vänsterspalt (liggande):** kan döljas med ett tryck och ändras i bredd.
  Innehåll uppifrån: flikar Bibliotek/Låtlistor → sökfält → låtlista → förslagsruta → "Ny spelning".
- Listrader: titel + färgmarkeringar, normal textstorlek, inga miniatyrer.
- **Låtvy:** flytande knappar i ett hörn. Låtlisteknappen syns alltid under spelning;
  övriga funktioner ligger i en meny.
- Fast palett med ca 10 tydliga färger för färgkoder och notes.
- Klickbar skiss tas fram och godkänns innan kodning.

## Utanför version 1
Transponering, ChordPro-redigering, bandsynk, MIDI, metronom, backing tracks, Apple Pencil-ritning.

## Datamodell (översikt)
- **Song:** id, titel, tonart, typ (pdf/bild/text), originalfil, text (för textlåtar), textstorlek,
  tillagd, senast spelad, antal spelningar, scrollhastighet.
- **Setlist:** id, namn, ordnade poster (låt + position).
- **ColorTag:** id, namn, färg. Kopplas till låtar (många-till-många).
- **Highlight:** låt, sida, position, bredd, färg.
- **ChordStamp:** låt, sida, position, grundton, förtecken, färgning, basnot.
- **StickyNote:** låt, text, färg, rektangel, förankring (sida/skärm), sidnummer.

## Milstolpar
1. **Grund:** Xcode-projekt, struktur, import, bibliotek, visa PDF/bild.
2. **Layout & listor:** delad vy liggande/stående, låtlistor, dra-och-släpp, sök, sortering.
3. **Spela:** autoscroll per låt, pedal/tangentbord, nästa låt, förladdning.
4. **Färgkoder & förslag:** färgkoder, filter, förslagsruta, förhandsruta.
5. **Notes, pennor & ackord:** notes (skapa/flytta/storlek/färg/förankring, textanpassning, dölj),
   markeringspennor, ackordstämplar.
6. **Redigera:** namnbyte, "Gör redigerbar" (PDF → textlåt), redigera text, textstorlek, återställ.
7. **iCloud:** synk och backup.
8. **Finputs:** prestandatest med 200 låtar, scenläge, testning på iPad via Xcode.

Varje milstolpe ska gå att köra och testa på iPad innan nästa påbörjas.

## Underlag
- Biblioteket: ca 200 låtar, mest PDF:er gjorda i Word, några få bilder.

## Beslut
- PDF-redigering görs genom konvertering till textlåt (som OnSong), inte genom redigering ovanpå PDF:en.

## Öppna frågor
- Synpunkter på den klickbara skissen.
