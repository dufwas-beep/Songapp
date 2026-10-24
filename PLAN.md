# Songapp – grundplan (UTKAST)

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
- Färgval (t.ex. gul, rosa, blå, grön, orange, vit).
- Per note väljs förankring:
  - *Följer sidan* – sitter på en plats i låten och scrollar med.
  - *Fast på skärmen* – ligger still medan låten scrollar.
- Visa/dölj alla notes med en knapp.

### 7. Redigera PDF
- Byta låttitel i biblioteket (enkelt namnbyte).
- Ändra text i PDF:en, t.ex. tryckt titel eller textrader:
  - För PDF:er med riktig text (t.ex. gjorda i Word): tryck på en rad → befintlig
    text fylls i → redigera → appen täcker gammal text och ritar den nya i liknande
    storlek på samma plats.
  - För inskannade PDF:er/bilder: rita en ruta och skriv ny text ovanpå.
- Ändringarna är ett lager ovanpå originalet – kan ångras när som helst.
- (Valfritt) Exportera låt som ny PDF med ändringarna inbakade.

### 8. iCloud
- Låtfiler, notes, listor och inställningar synkas/säkerhetskopieras via iCloud.

## Utanför version 1
Transponering, ChordPro-redigering, bandsynk, MIDI, metronom, backing tracks, Apple Pencil-ritning.

## Datamodell (översikt)
- **Song:** id, titel, fil, tillagd, senast spelad, antal spelningar, scrollhastighet.
- **Setlist:** id, namn, ordnade poster (låt + position).
- **StickyNote:** låt, text, färg, rektangel, förankring (sida/skärm), sidnummer.
- **TextEdit:** låt, sida, rektangel, ny text, teckenstorlek, täckfärg.

## Milstolpar
1. **Grund:** Xcode-projekt, struktur, import, bibliotek, visa PDF/bild.
2. **Layout & listor:** delad vy liggande/stående, låtlistor, dra-och-släpp, sök, sortering.
3. **Spela:** autoscroll per låt, pedal/tangentbord, nästa låt, förladdning.
4. **Notes:** skapa/flytta/storlek/färg/förankring, automatisk textanpassning, dölj.
5. **Redigera:** namnbyte, textredigering i PDF, ångra.
6. **iCloud:** synk och backup.
7. **Finputs:** prestandatest med 200 låtar, scenläge, testning på iPad via Xcode.

Varje milstolpe ska gå att köra och testa på iPad innan nästa påbörjas.

## Öppna frågor
Se diskussionen – fylls på tills planen är godkänd.
