# Potpurri

En enkel och stabil iPad-app för låtblad på scen. Se [PLAN.md](PLAN.md) för hela planen.

## Köra appen på din iPad

1. Öppna **GitHub Desktop** och tryck **Fetch origin / Pull** så att du har senaste koden.
2. Dubbelklicka på **Potpurri.xcodeproj** för att öppna projektet i Xcode.
3. Första gången: klicka på projektet **Potpurri** längst upp i vänsterspalten →
   fliken **Signing & Capabilities** → välj ditt namn under **Team**.
4. Anslut iPaden med kabel, välj den överst i Xcode-fönstret och tryck **▶** (⌘R).
5. Första gången på iPaden:
   - Inställningar → Integritet och säkerhet → **Utvecklarläge** → på (iPaden startar om).
   - Inställningar → Allmänt → VPN och enhetshantering → **Lita på** dig själv.

Med ett gratis Apple-ID behöver appen köras om från Xcode var 7:e dag.

## Milstolpe 1 – vad som finns

- Importera PDF:er och bilder från **Filer** (där Dropbox finns) med **+**. Flera filer åt gången.
- Låtens namn = filnamnet. Filerna kopieras in i appen, originalen rörs inte.
- Biblioteket till vänster med **sök** och svensk sortering (Å, Ä, Ö sist).
- Låten visas till höger: PDF:er som en lång scrollbar vy, bilder anpassade till bredden.
- Svep åt vänster på en låt för att ta bort den.
- Appikonen (LP:n) och rosa accentfärg.

## Import från OnSong

1. Gör en backup i OnSong (**Utilities → Backup**) och spara den i Dropbox eller Filer.
2. Tryck **+ → OnSong-backup** i Potpurri och välj filen.
3. Kryssa i vilka låtar som ska med (låtar som redan finns är urkryssade) och tryck **Importera**.

PDF:er och bilder blir vanliga låtar, låtar skrivna i OnSong blir textlåtar med ackorden
ovanför texten, textfiler (quizmanus) blir anteckningar och låtlistorna följer med.

## Automatisk kontroll

Varje gång kod pushas bygger GitHub appen på en Mac i molnet
(fliken **Actions** i repot). Grön bock = koden går att bygga.
