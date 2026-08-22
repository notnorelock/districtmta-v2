# Stan projektu

Ten dokument opisuje, co jest **faktycznie zaimplementowane** w tej chwili -
zweryfikowane bezpośrednio w kodzie, nie na podstawie samych nazw zasobów.
Ma dwa cele: (1) dać jasny obraz tego, co już działa jako fundament, (2) jasno
pokazać, czego brakuje do realnej grywalności RP - żeby nie było złudzeń co
do zakresu pozostałej pracy.

**Ostatnia weryfikacja:** cały kod przejrzany zasób po zasobie (2026-08-22).

---

## Skrót sytuacji

Mamy solidny, poprawny technicznie **fundament** (konta, uprawnienia,
moderacja, pojazdy, ekwipunek, HUD, czat/głos) - ale **zero** systemów,
które realnie definiują rozgrywkę RP: brak frakcji, ekonomii, mieszkań,
biznesów, levelowania, tworzenia postaci, przestępczości. To, co jest,
to warstwa "serwer działa i można się zalogować i jeździć autem" - nie
"jest w co grać".

---

## Co jest zaimplementowane

### [core] - infrastruktura backendu

| Zasób | Co robi |
|---|---|
| **core** | MySQL + własny ORM (Model/QueryBuilder/Schema), konta (rejestracja/logowanie/bcrypt/premium), cache kontekstu konta gracza, system kar (ban/mute/warn/kick z parsowaniem czasu trwania), zgłoszenia (`/report`), tracking służby admina, system uprawnień bitmaskowych (7 rang: Player/Weteran/Pomocnik/Moderator/Administrator/RCON/Zarząd), serwis powiadomień. |
| **core_admin** | Natywny (dxGUI) panel admina: gracze, zgłoszenia, statystyki służby. Klawisze F6/F7/J na służbie. |
| **core_auth** | Logowanie/rejestracja przez CEF, wybór spawnu z 4 stałych punktów (Grove Street, Idlewood, Las Venturas Strip, San Fierro Downtown). **Brak edytora wyglądu postaci** - tylko wybór punktu spawnu, skin to gołe id. |
| **core_bootstrap** | Sekwencyjny starter zasobów - jedyny zasób ze `startup="1"`. |
| **core_loading** | Brama `LOADING_READY` (czeka aż CEF + cały łańcuch bootstrapu będą gotowe). |
| **core_shared** | Same stałe (Enums/Events/ErrorCodes/ValidationRules/ElementData) - zero logiki. |
| **core_ui** | Warstwa transportu CEF: FetchBridge, PushService, obfuskacja payloadów, dostęp do fontów. |

### [gameplay] - systemy widoczne dla gracza

| Zasób | Co robi | Ograniczenia |
|---|---|---|
| **gm_items** | Ekwipunek server-authoritative (limit wagi), przedmioty w świecie, podnoszenie/upuszczanie/użycie/ulubione, stackowanie. | **Tylko 4 przedmioty istnieją w ogóle**: mała/średnia/duża ryba (bez efektu użycia) i kluczyki do pojazdu. Brak craftingu, sklepów, waluty. |
| **gm_interactions** | Framework interakcji świata (menu kontekstowe w zasięgu). Aktywne dziś: naprawa/obrót/przywołanie pojazdu (admin, na służbie), podnoszenie przedmiotów, zamek/maska/bagażnik pojazdu (wymaga kluczyka). | Cienka zawartość - głównie akcje na pojazdach + narzędzia admina. |
| **gm_roleplay** | Spawn gracza po wyborze lokacji, lokalny czat IC (zasięg 30m, uwzględnia wyciszenie, kolor wg rangi/premium). | To jest "klej" łączący kilka rzeczy naraz, nie osobny system. |
| **gm_vehicles** | Trwałe pojazdy prywatne w bazie: autosave (30s) + zapis przy wyjściu, pełny stan (tuning/neon/lakier/silnik, stan drzwi/świateł/paneli/kół, 4-slot lakier, tablica, paliwo/przebieg, 5 ostatnich kierowców). Osobny koncept "pojazdów publicznych" (auto-despawn/respawn) - **lista punktów spawnu jest pusta, nic realnie nie działa**. | Własność przypięta do **konta**, nie do postaci (bo nie ma systemu postaci). |
| **gm_vehicles_interaction** | Radialne menu (Left Shift w jeździe): silnik/światła/zamek/hamulec ręczny dowolnego pojazdu, którym aktualnie jedziesz. | - |

**Komendy graczy (nie-admin):** `/veh <nazwa|id>`, `/fix`, `/flip` (gm_roleplay).
**Komendy admina:** `/duty`, `/report`, `/reports`, `/apanel`, `/goto`, `/gethere`, `/gotocar`, `/getcar`, `/heal`, `/jetpack`, `/setrole`, `/ban`, `/unban`, `/mute`, `/warn`, `/kick`, `/giveitem`, `/createvehicle`.

### [systems] - HUD i warstwy pomocnicze

| Zasób | Co robi | Ograniczenia |
|---|---|---|
| **ui_hud** | Natywny HUD dxDraw: własny radar (bez GPS/tras), licznik FPS, pierścień zdrowia/tlenu/głosu, natywny stos powiadomień (toast). | **Głód i pragnienie to zahardkodowane stałe (zawsze 100)** - żadnej mechaniki za nimi nie ma. |
| **gm_blackout** | Zamiast śmierci: stan "nieprzytomny" (KO, 5 HP, 120s), automatyczne wybudzenie lub samo-ocucenie po czasie. | Brak systemu medyka (jawnie oznaczone jako TODO na przyszłość). |
| **gm_nametags** | Dymki nad graczami: nick/ranga/służba/afk/wyciszenie/premium. | Ma zahardkodowane pole `level = 1` - zero systemu poziomów za tym. |
| **gm_radio** | Radio w pojeździe: ~20 realnych stacji internetowych, sterowanie tylko przez kierowcę, słyszalne dla wszystkich pasażerów. | Brak zapisanej ulubionej stacji per konto. |
| **gm_scoreboard** | Lista graczy pod TAB (login/ranga/służba/status połączenia). | - |
| **gm_voice** | Głos proximity: 3 tryby (szept/mowa/krzyk, różne zasięgi), uwzględnia wyciszenie konta, respektuje interior/dimension. | - |

### [custom] - drobne narzędzia renderujące

| Zasób | Co robi |
|---|---|
| **markers** | Własne markery/corony (ring/corona/cylinder) z ikonami i etykietami tekstowymi. |
| **models** | Podmiana modeli pojazdów - obecnie 3 liberie SAPD (id 596/598/599) jako **assety**, bez żadnego systemu policyjnego, który by ich używał. |

---

## Czego kompletnie brakuje

Zweryfikowane wprost w kodzie - żadne z poniższych nie istnieje nawet w
formie zalążka. Wiele miejsc w kodzie ma komentarze w stylu *"nie
implementować, dopóki nie istnieje system X, od którego to zależy"*.

| System | Status | Dowód w kodzie |
|---|---|---|
| **Frakcje/gangi/organizacje** | ❌ Brak | `Enums.VehiclePurpose` wprost wymienia `GROUP`/`EVENT`/`EXCHANGE` jako nieistniejące; `gm_interactions` miało w oryginale role SAPD/SAMD/SAFD - świadomie wycięte przy porcie. |
| **Praca/ekonomia (pętla zarobkowa)** | ❌ Brak | Brak jakiegokolwiek zasobu z pracą. Komentarz w `ItemSchemes.lua` wprost mówi, że typ przedmiotu "wędka" nie został przeniesiony, bo zależał od nieistniejącego systemu pracy/rybołówstwa. |
| **Waluta/pieniądze** | ❌ Brak | Model `Account` nie ma kolumny z saldem - tylko id/serial/login/email/hasło/premium/rola. Zero waluty gdziekolwiek w schemacie. |
| **Mieszkania/nieruchomości** | ❌ Brak | Brak tabeli/zasobu/komendy związanej z własnością nieruchomości. |
| **Biznesy gracza** | ❌ Brak | `Enums.VehiclePurpose` wprost wymienia `SHOP` jako nieistniejący. |
| **Narkotyki/szara strefa** | ❌ Brak | W `ItemSchemes.lua` istnieją tylko 3 warianty ryby + kluczyk. |
| **Sklepy z bronią/przedmiotami** | ❌ Brak | Jedyny sposób zdobycia przedmiotu to `/giveitem` (admin), jedyny sposób zdobycia pojazdu to `/veh` (darmowy, tymczasowy) lub `/createvehicle` (admin). Zero przepływu zakupowego. |
| **Tworzenie/edycja postaci** | ❌ Brak | `core_auth` daje tylko wybór punktu spawnu z 4 stałych lokacji. Skin to gołe `ElementData.Player.SKIN`, bez edytora. Komentarz w `VehicleService.lua` wprost potwierdza brak systemu wyboru postaci - pojazdy/przedmioty są przypięte do konta, nie do postaci. |
| **Levelowanie/XP/progresja** | ❌ Brak | `gm_nametags` wysyła zahardkodowane `PLACEHOLDER_LEVEL = 1` z komentarzem "no level/xp system exists yet". |
| **Telefon/komunikacja poza głosem** | ❌ Brak | Komunikacja ograniczona do czatu IC (30m) i głosu proximity. Brak SMS/połączeń/aplikacji telefonu. |
| **Przestępczość/pościgi/policja (gameplay)** | ❌ Brak | Istnieją tylko narzędzia moderacyjne admina (ban/mute/kick/warn) - to nie gameplay. Brak aresztowania, poziomu poszukiwania, więzienia, służby policyjnej. Modele SAPD istnieją jako asset bez żadnego systemu za nimi. |
| **Animacje/emotki** | ❌ Brak | Jedyna animacja w kodzie to stała animacja KO w `gm_blackout` - nie system emotek dla gracza. |
| **Meble/rozmieszczanie wnętrz** | ❌ Brak | Brak tabeli/zasobu/komendy. |

---

## Wniosek

To co działa dziś, to **plac budowy z solidnymi fundamentami**: logowanie,
uprawnienia, moderacja, pojazdy, ekwipunek (szkieletowy), HUD, czat, głos.
Żaden z systemów definiujących typową rozgrywkę RP (frakcje, ekonomia,
progresja, postacie, przestępczość, mieszkania) nie istnieje nawet
częściowo - są to osobne, duże projekty do zbudowania od zera, każdy
wymagający własnego schematu bazy, serwisu, UI i integracji z tym co już
istnieje (głównie z systemem kont, bo nie ma jeszcze systemu postaci, na
którym większość z nich normalnie by się opierała).
