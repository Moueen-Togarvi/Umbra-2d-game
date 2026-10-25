# Umbra puzzles: the catalogue

Every puzzle room in the campaign is drawn from this list. Repeated core
skills deliberately return with different terrain, danger or a second
solution; they are not limited to two appearances. Each chapter follows the
same shape: one easy warm-up, two or three medium, one hard, and one set
piece. Code: `lib/chapters/puzzle_route.dart` (`PuzzleKind`), the bot that
solves them: `test/support/route_pilot.dart`.

(Written in Roman Urdu, as agreed with the designer.)

## Achhe puzzle kaise hon (design ke usool)

1. **Ek "aha" lamha.** Har puzzle mein ek cheez ke do kaam hon. Misaal: crate jaal bhi band kare aur seedhi bhi bane.
2. **Pehle sikhao, phir mushkil.** Naya mechanic pehle surakshit jagah pe aaye, phir khatre ke saath, phir doosre mechanic se mil kar.
3. **Khatra saaf dikhe.** Maut khiladi ki ghalti lage, dhoka nahi. Checkpoint har room ke shuru mein ho.
4. **Mushkil ka matlab dimaag.** Ungliyon ki tezi kam ho, sochna zyada.
5. **Har chapter ka formula:**
   - 1 aasaan puzzle (warm-up);
   - 2–3 darmiyana;
   - 1 mushkil;
   - 1 yaadgaar set piece (peecha, dhehti gufa, baadh).
6. **Khaali chalna na ho.** Do puzzles ke beech chhote mahaul wale lamhe hon: chamgadad, andhere mein aankhein, door vampire ki jhalak.
7. **Repeat ho to naya sawaal ho.** Wohi skill dobara aaye to terrain, pressure, enemy, darkness, water ya doosra hal badle.

## 100 puzzles ki list

**Nishaan:**
- **Mushkil:** A = aasaan, D = darmiyana, M = mushkil.
- **Mechanic:** ✓ = game mein maujood hai, ✚ = naya banana hoga.

### A. Dhakelna, kheenchna, wazan

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 1 | Crate seedhi | Crate deewar tak dhakel kar us pr chadho | A | ✓ |
| 2 | Do crate ka minar | Ek crate doosre pr chadhao, tab oonchi deewar chadhi jaye | M | ✚ |
| 3 | Kheench kar nikalo | Crate kone mein atka hai; E se peeche kheencho, phir istemal karo | D | ✓ |
| 4 | Jaal-saaf crate | Crate aage dhakelo, raste ke jaal band ho jayein | D | ✓ |
| 5 | Plate gate | Ek crate plate pr chhodo, doosra saath le jao | D | ✓ |
| 6 | Do plate, ek gate | Dono plates pr wazan chahiye: crate aur tum. Utro to gate band ho, us se pehle daud kar nikalo | M | ✚ |
| 7 | Taraazu gate | Bhaari crate taraazu mein, gate upar | A | ✓ |
| 8 | Barabar taraazu | Do taraazu barabar hon tabhi gate khule | M | ✚ |
| 9 | Barrel lurhkao | Barrel dhalaan se lurhak kar takhte tode ya plate dabaye | D | ✓ |
| 10 | Gaadi ki sawari | Cart dhakel kar us pr baith jao; dhalaan se khaayi ke paar | M | ✓ |
| 11 | Coffin ki dhaal | Coffin dhakelte hue uske peeche chhup kar vampire ke paas se guzro | D | ✓ |
| 12 | Lattha pul | Sookha darakht dhakel kar khaayi pr girao | D | ✚ |
| 13 | Almaari pul | Oonchi almaari gira kar pul banao | D | ✓ |
| 14 | Mez ki seedhi | Mez kheench kar oonchi khidki tak le jao | A | ✓ |
| 15 | Bhaari pathar | Pathar dhalaan se lurhkao, neeche ka kamzor farsh toot jaye | D | ✚ |

### B. Rassi aur jhoolna

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 16 | Rassi jhoola | Khaayi ke paar jhoolo | A | ✓ |
| 17 | Do rassi | Ek rassi se doosri pr koodo | D | ✓ |
| 18 | Rassi chadhna | Rassi pr chadh kar oonchi ledge | A | ✓ |
| 19 | Rassi se drawbridge | Rassi kheencho, pul neeche aaye | D | ✓ |
| 20 | Jalti rassi | Jhoolte hi rassi jalne lage; jaldi chhodo | M | ✚ |
| 21 | Rassi ke neeche jaal | Sahi waqt pr chhodo, warna jaal mein giro | D | ✓ |
| 22 | Pendulum sawari | Jhoolte pendulum pr chadh kar paar | D | ✓ |
| 23 | Pinjre se pinjra | Latakte pinjron pr koodte jao | D | ✓ |
| 24 | Winch se upar | Crate pinjre mein rakho, ghuma kar upar kheencho | M | ✓ |
| 25 | Kapdon ki rassi | Rassi pr latak kar sarakte hue paar | A | ✚ |

### C. Paani

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 26 | Lakdi ka raft | Raft pr baith kar paani paar | A | ✓ |
| 27 | Drain pedal | Pedal dabao, paani nikle, raasta khule | D | ✓ |
| 28 | Paani se upar | Paani bharo, crate tair kar upar aaye, us pr chadh kar ledge | M | ✚ |
| 29 | Doobta raft | Raft pr zyada der ruko to doob jaye; jaldi paar | D | ✚ |
| 30 | Tez bahaav | Bahaav mein raft roko, rassi pakdo | D | ✓ |
| 31 | Gota | Paani ke neeche se tair kar guzro; saans ki had | M | ✚ |
| 32 | Pan-chakki lift | Paani chalao, pahiya ghoome, platform upar aaye | M | ✓ |
| 33 | Sluice ka kram | Do darwaze sahi kram mein kholo | M | ✓ |
| 34 | Barrel tairao | Barrel paani mein dhakel kar us pr chadho | A | ✓ |
| 35 | Baadh se bhaago | Paani tezi se badhe, upar chadhte jao | M | ✚ |

### D. Roshni aur andhera

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 36 | Chaand ki khidki | Khidki kholo; roshni mein vampire nahi aata | D | ✓ |
| 37 | Lantern gaadi | Lantern wali gaadi saath dhakelte chalo | D | ✓ |
| 38 | Tel ka chiraag | Chiraag girao, aag vampire ko roke | D | ✓ |
| 39 | Mashaalein jalao | Ek mashaal se doosri jalao, raasta roshan | D | ✓ |
| 40 | Aaine ki kiran | Aaina ghuma kar chaand ki kiran vampire pr dalo | M | ✚ |
| 41 | Bijli ki chamak | Toofan mein sirf chamak ke waqt raasta dikhe aur vampire ruke | M | ✓ |
| 42 | Jugnu ka raasta | Andheri gufa mein jugnu ke peeche chalo | D | ✚ |
| 43 | Jhoomar girao | Rassi kaato, jhoomar vampire pr gire | D | ✓ |
| 44 | Subah ki kiran | Pehli roshni tak pahuncho, vampire jal jaye | M | ✓ |
| 45 | Lantern upar le jao | Lantern rassi se upar kheencho, upar ka raasta roshan ho | D | ✚ |

### E. Chhupna aur jaanwar

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 46 | Jhuk kar guzro | Neechi chhat ke neeche se | A | ✓ |
| 47 | Jhaadi mein chhupo | Vampire ke patrol se chhup kar | D | ✓ |
| 48 | Do vampire | Ulti dishaon mein ghoomte do vampire; beech mein chhupo | M | ✚ |
| 49 | Chamgadad jhund | Ruko, jhund guzar jane do | A | ✓ |
| 50 | Ullu ki aankh | Ullu ki aankh band ho tab chalo | D | ✚ |
| 51 | Sota vampire | Dheere aur jhuk kar chalo; daude to jaag jayega | M | ✚ |
| 52 | Ghanti se bhatkao | Ghanti bajao, vampire us taraf jaye, tum doosri taraf | M | ✚ |
| 53 | Coffin ke haath | Coffin se haath nikalte hain; waqt dekh kar guzro | D | ✚ |
| 54 | Bachche saath | Bachchon ko chhupa kar saath le chalo | M | ✓ |
| 55 | Kauwe | Kauwe ud kar vampire ko jaga dete hain; dheere chalo | D | ✚ |

### F. Jaal aur khatre

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 56 | Jaalon ka maidan | Kood kar ya crate se jaal band karte hue paar | D | ✓ |
| 57 | Khoonton ka gaddha | Kood kar paar | A | ✓ |
| 58 | Girti chattanein | Lurakte pattharon pr se koodo | M | ✓ |
| 59 | Toot-ta pul | Qadam rakhte hi charcharaye, daud kar paar | D | ✓ |
| 60 | Girta farsh | Takhte ek ek kar ke girte hain, ruko mat | D | ✚ |
| 61 | Kuchalne wala pathar | Upar se girta-uthta pathar; waqt dekh kar neeche se nikalo | D | ✚ |
| 62 | Ghoomta hathoda | Hathode ke waaron ke beech se guzro | D | ✓ |
| 63 | Teer ka jaal | Taar chhoote to teer chalein; jhuko ya crate se roko | M | ✚ |
| 64 | Jhoolti dhaar | Pendulum blade ke beech waqt dekh kar | M | ✚ |
| 65 | Lurhakte barrel | Dhalaan se aate barrels pr se koodo | D | ✚ |
| 66 | Daldal | Ruke to dhanso; koodte raho | D | ✚ |
| 67 | Girte nukeele pathar | Gufa ki chhat se girte stalactite | D | ✚ |
| 68 | Aag ki lapat | Zameen se nikalti aag, waqt dekh kar | D | ✚ |
| 69 | Pathar ka gola | Bada gola peecha kare, bhaago | M | ✚ |

### G. Mashine aur lever

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 70 | Lift + counterweight | Chest utaro, lift upar | D | ✓ |
| 71 | Lift waapsi | Upar control, neeche raasta | M | ✓ |
| 72 | Gear roko | Crate se gear rok kar hathoda band karo | M | ✓ |
| 73 | Ghadi ki sui | Ghoomti sui pr chadh kar upar | D | ✓ |
| 74 | Seesaw | Seesaw pr se paar | A | ✓ |
| 75 | Seesaw gulail | Bhaari crate gira kar khud uchhlo | M | ✚ |
| 76 | Lever ka kram | Teen lever sahi kram mein kheencho | M | ✚ |
| 77 | Chalti patti | Ulti disha mein chalti patti pr | D | ✚ |
| 78 | Winch gate | Gate ghuma kar kholo; chhodo to band | D | ✓ |
| 79 | Chalta platform | Aate jaate platform pr waqt se | A | ✓ |
| 80 | Ghoomta pul | Pul ko ghuma kar sahi taraf lao | D | ✚ |
| 81 | Ghanta kheencho | Darwaza khule, lekin awaaz se vampire aaye | M | ✚ |
| 82 | Chain reaction | Paani → pahiya → gear → gate | M | ✓ |
| 83 | Pinjre wali lift | Pinjre mein baith kar winch se upar | D | ✓ |

### H. Peecha aur waqt

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 84 | Vampire ka peecha | Daud kar plate dabao, gate peeche gire | M | ✓ |
| 85 | Waqt pe darwaza | Plate dabao; gate band hone se pehle daud kar nikalo | D | ✚ |
| 86 | Girti seedhiyan | Seedhiyan peeche se girti jaayein | M | ✚ |
| 87 | Hathodon ke beech | Ghanton ki chot ke beech guzro | D | ✓ |
| 88 | Aag ka peecha | Peeche se aag badhe | M | ✓ |
| 89 | Dhehti gufa | Chhat girti jaaye, daudo | M | ✚ |
| 90 | Aakhri chhalaang | Lambi chhalaang aur rassi pakdo | M | ✚ |
| 91 | Bhediye | Jungle mein bhediye ka peecha | M | ✚ |
| 92 | Raft ka peecha | Vampire kinare pr daude, tum raft pr | M | ✚ |

### I. Dimaag wale (logic)

| # | Naam | Kaise khelte hain | Mushkil | Mechanic |
|---|---|---|---|---|
| 93 | Ulta raasta | Upar ja kar neeche ka raasta kholo, phir waapas aao | M | ✓ |
| 94 | Kaunsa crate kahan | Do crate; ghalat kram mein raasta band | M | ✚ |
| 95 | Parchhaai ka raasta | Platform sirf roshni mein dikhte hain | M | ✚ |
| 96 | Bachcha plate pr | Bachche ko plate pr khada karo, khud aage | M | ✚ |
| 97 | Gola aur plate | Gola lurhka kar door ki plate dabao | D | ✚ |
| 98 | Rassi jala kar bojh girao | Bojh plate pr gire | M | ✚ |
| 99 | Do kaam ek waqt | Crate plate pr aur lever ek saath | M | ✚ |
| 100 | Aakhri imtihaan | Chapter ke boss room mein us chapter ke 3 mechanics ek saath | M | ✚ |

**Hisaab:**
- Maujooda (✓): ~45; naye (✚): ~55.
- Mushkil ke hisaab se: aasaan ~14, darmiyana ~45, mushkil ~41.

## Kaunsa chapter, kaunse puzzles

| Ch | Jagah | Puzzles (# upar ki list se) |
|---|---|---|
| 1 | Home | 1, 49, 46, 5 |
| 2 | Old Orchard | 7, 16, 57, 9, 74 |
| 3 | Hunters' Road | 56, 25, 12, 59, 91 |
| 4 | Graveyard | 47, 11, 55, 3, 84 |
| 5 | Night Forest | 42, 59, 66 |
| 6 | Cage | 23, 18 |
| 7 | Chainworks | 24, 19, 62, 76, 17 |
| 8 | Caves | 67, 26 |
| 9 | Sluice Tunnels | 27, 33, 34, 31, 46 |
| 10 | Drowned Quarry | 28, 30, 29, 58, 89 |
| 11 | Crypt | 61, 53, 2 |
| 12 | Coffin Gallery | 11, 47, 51, 94, 26 |
| 13 | Bone Pit | 60, 15, 65 |
| 14 | Floodworks | 35, 32, 27, 92, 8 |
| 15 | Lower Castle | 7, 70, 13, 68, 10 |
| 16 | Chase | 86, 85 |
| 17 | Servants' Passage | 46, 14, 37, 52, 3 |
| 18 | Halls | 36, 48, 88 |
| 19 | Shadow Gallery | 37, 95, 40, 50, 36 |
| 20 | Chandeliers | 43, 22, 64 |
| 21 | Organ Loft | 81, 76, 17, 63, 6 |
| 22 | Clock Tower | 73, 72, 87 |
| 23 | Bell Foundry | 52, 81, 68, 75, 99 |
| 24 | Watchers' Walk | 41, 50, 63, 60, 90 |
| 25 | Children | 54, 96, 23 |
| 26 | Abandoned Ward | 51, 94, 45, 55, 14 |
| 27 | Drainways | 31, 34, 77, 33, 67 |
| 28 | Mill | 32, 82, 77 |
| 29 | Broken Aqueduct | 12, 80, 30, 15, 90 |
| 30 | Black Reservoir | 28, 29, 92, 35, 49 |
| 31 | Furnace Passage | 39, 38, 98, 20, 88 |
| 32 | Outer Ramparts | 69, 75, 65, 9, 78 |
| 33 | Great Gate | 78, 19, 100 |
| 34 | Moat | 30, 31, 79, 97, 8 |
| 35 | Storm | 41, 58, 89 |
| 36 | Shattered Coast | 79, 66, 2, 93, 91 |
| 37 | Last Watch | 48, 64, 40, 71, 85 |
| 38 | Eastern Woods | 42, 57, 21, 56, 95 |
| 39 | Homeward Road | 10, 74, 16, 61, 100 |
| 40 | Dawn | 44, 84, 45 |

Haath se bane chapters ki kahani wale lamhe wahi rahenge. Yeh numbers unke puzzle rooms aur extension rooms ke hain.

## Code mein kaunsa number kaunsa `PuzzleKind` (ab tak)

| # | Naam | `PuzzleKind` | Chapters |
|---|---|---|---|
| 1 | Crate seedhi | `crate` (Home mein cart) | 1 |
| 3 | Kheench kar nikalo | `pullCrate` | 4 |
| 5 | Plate gate | `plateGate` | 1 |
| 7 | Taraazu gate | `weight` | 2 |
| 9 | Barrel lurhkao | `barrel` | 2 |
| 11 | Coffin ki dhaal | `coffin` | 4 |
| 12 | Lattha pul | `logBridge` | 3 |
| 16 | Rassi jhoola | `rope` | 2 |
| 25 | Rassi pr sarakna (zip-line) | `zipline` | 3 |
| 42 | Jugnu ka raasta | `fireflies` | 5 |
| 46 | Jhuk kar guzro | `crawl` | 1 |
| 47 | Jhaadi mein chhupo | `patrol` | 4 |
| 49 | Chamgadad jhund | `bats` | 1 |
| 55 | Kauwe | `crows` | 4 |
| 56 | Jaalon ka maidan | `traps` | 3 |
| 57 | Khoonton ka gaddha | `spikes` | 2 |
| 59 | Toot-ta pul | `bridge` | 3, 5 |
| 66 | Daldal | `bog` | 5 |
| 74 | Seesaw | `seesaw` | 2 |
| 84 | Vampire ka peecha | `chase` | 4 |
| 91 | Bhediye | `wolves` | 3 |
| 17 | Do rassi | `twoRopes` | 7 |
| 18 | Rassi chadhna | `ropeClimb` | 6 |
| 19 | Rassi se drawbridge | `drawbridge` | 7 |
| 23 | Pinjre se pinjra | `cages` | 6 |
| 24 / 83 | Pinjre wali lift (winch) | `cageLift` | 7 |
| 26 | Lakdi ka raft | `raft` | 8 |
| 27 | Drain pedal | `drain` | 9 |
| 28 | Paani se upar (crate tairta hai) | `floatCrate` | 10 |
| 29 | Doobta raft | `sinkingRaft` | 10 |
| 33 | Sluice ka kram | `sluice` | 9 |
| 34 | Lattha tairao | `logFloat` | 9 |
| 58 | Girti chattanein | `rockfall` | 10 |
| 62 | Ghoomta hathoda | `hammer` | 7 |
| 67 | Girte nukeele pathar | `stalactites` | 8 |
| 76 | Lever ka kram | `levers` | 7 |
| 89 | Dhehti gufa | `collapse` | 10 |

| 2 | Do crate ka minar | `twoCrates` | 11 |
| 13 | Almaari pul | `bookcase` | 15 |
| 15 | Bhaari pathar | `boulder` | 13 |
| 35 | Baadh se bhaago | `floodRise` | 14 |
| 51 | Sota vampire | `sleeper` | 12 |
| 53 | Coffin ke haath | `coffinHands` | 11 |
| 60 | Girta farsh | `fallingFloor` | 13 |
| 61 | Kuchalne wala pathar | `crusher` | 11 |
| 65 | Lurhakte barrel | `barrelRun` | 13 |
| 68 | Aag ki lapat | `fireJets` | 15 |
| 94 | Kaunsa crate kahan | `heavyLight` | 12 |

| 36 | Chaand ki khidki | `moonWindow` | 18, 19 |
| 43 | Jhoomar girao | `chandelier` | 20 |
| 50 | Deewar ki aankh (ullu ki jagah) | `watchEye` | 19 |
| 52 | Ghanti se bhatkao | `bell` | 17 |
| 85 | Waqt pe darwaza | `timedDoor` | 16 |
| 86 | Girti seedhiyan | `fallingStairs` | 16 |
| 88 | Aag ka peecha | `fireChase` | 18 |
| 6 / 99 | Do plate, ek gate | `twoPlates` | 21, 23 |
| 63 | Teer ka jaal | `tripwire` | 21, 24 |
| 81 | Ghanta kheencho | `bellGate` | 21, 23 |
| 90 | Aakhri chhalaang | `leapRope` | 24 |
| 20 | Jalti rassi | `burningRope` | 31 |
| 69 | Pathar ka gola (peecha) | `boulderChase` | 32 |
| 79 / 80 | Chalta platform | `movingPlatform` | 28, 34 |
Abhi nahi bane: #31 Gota (ladka tair nahi sakta, aur paani use upar uchhaal deta hai) aur #30 Tez bahaav (rassi chhoot jaye to wapas aane ka raasta nahi). Chapter 9 aur 10 mein in ki jagah 4-4 puzzle hain. Hissa 3 mein bhi #32 (pan-chakki lift), #92 (raft ka peecha), #8 (barabar taraazu) aur #10 (gaadi ki sawari) abhi nahi bane; un ki jagah maujooda puzzle hain. Hissa 4 mein #95 (parchhaai ka raasta), #40 (aaine ki kiran), #48 (do vampire), #64 (jhoolti dhaar) aur #14 (mez) abhi nahi bane. Hissa 5 mein #73 (ghadi ki sui: Clock Tower ki kahani mein pehle se), #75 (seesaw gulail), #41 (bijli), #54 aur #96 (bachche) abhi nahi bane. Chapters 26–35 mein #32, #82, #77, #31, #80 (ghoomta pul ki jagah chalta platform), #30, #92, #39, #98, #75, #78, #8, #41 aur #100 abhi nahi bane; un ki jagah pehle bane puzzle dobara aaye hain.
