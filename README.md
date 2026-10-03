# Bezpečné QR

**Bezplatná aplikace, která u každého QR kódu vysvětlí, co dělá — dřív, než cokoli otevřete.**
iOS jako první, Android později. · 🇬🇧 [English version below](#-english)

Verze **0.0.3** · [Co je nového](CHANGELOG.md) · [Prototyp](prototype/) · Licence [AGPL-3.0](LICENSE) + [komerční licence](COMMERCIAL.md)

---

## Proč

V září 2026 upozornil Janek Rubeš (Kluci z Prahy) na podvodná „SMS předplatná“ za 99 Kč týdně, která se strhávají přes mobilního operátora. Lidé je často spustí naskenováním QR nálepky na lavičce, v obchodním centru nebo na parkovišti. Stejně fungují falešné nálepky na parkovacích automatech, „doplatky za zásilku“ nebo výzvy k převodu peněz „na bezpečný účet“.

Fotoaparát v telefonu otevře kód jedním klepnutím a nic nevysvětlí. Bezpečné QR to dělá jinak.

## Co aplikace dělá (plán verze 1)

- **Každý kód nejdřív zkontroluje** — přímo v telefonu, bez vlastního serveru.
- **Odkazy:**
  - ukáže skutečný cíl a cestu přes přesměrování;
  - ukáže, co po vás stránka chce (telefonní číslo, kartu, heslo);
  - upozorní na skryté předplatné.

  Stránku si aplikace načte sama, bez vašich cookies a bez spouštění skriptů. Před platební bránou operátora se zastaví, aby nevyzradila vaše číslo.
- **Platby:** ukáže částku, účet a banku. Umí QR Platbu, QR Fakturu, evropské platby (EPC), švýcarské QR faktury a kryptoměny. Upozorní, že jméno příjemce v kódu nikdo neověřuje.
- **Pasti v SMS a telefonech:** pozná prémiová čísla i jejich cenu a kódy pro přesměrování hovorů.
- **Citlivé kódy:** pozná přihlašovací kódy (WhatsApp, Telegram, Signal), export 2FA klíčů, obnovovací fráze kryptopeněženek a instalace profilů. Takové kódy nikam neukládá ani neodesílá.
- **Výsledek:** orientační skóre rizika 0–100, důvody („Proč?“) a popis toho, co se stane, když budete pokračovat.
- **Soukromí:** bez reklam, sledování a cizích SDK. Historie zůstává jen v telefonu.
- **Ochrana u operátora:** návod, jak si zablokovat platby třetím stranám.

## Stav projektu

Zatím je hotové:
- interaktivní HTML prototyp všech obrazovek ([`prototype/`](prototype/));
- sdílená pravidla ([`shared/rules/`](shared/rules/));
- testovací korpus s 80 vzorky ([`shared/testdata/`](shared/testdata/));
- **funkční iOS aplikace** ([`ios/`](ios/), testovací verze přes TestFlight): skenování kamerou i z Fotek, všechny typy kódů, kontrola odkazu (přesměrování, co stránka chce, Quad9 a stáří domény), skóre rizika s důvody, karty a akce podle typu, historie a nastavení.

Další kroky: rozšíření pro sdílení obrázků, kontrola textu vytištěného vedle kódu a ladění podle testování. Plán je v [`docs/roadmap.md`](docs/roadmap.md).

## 🤝 Hledáme partnery

Jsme otevření spolupráci s každým, kdo chce pomoci lidem chránit se před podvody:
- banky, mobilní operátoři, CZ.NIC, Whalebone / DNS4EU;
- bezpečnostní firmy, CSIRT.CZ, NÚKIB, Policie ČR;
- města a správci parkování, média.

Rádi probereme sdílení databází podvodných webů a účtů, varování i testování.

**Kontakt: [jakub@sejkora.cz](mailto:jakub@sejkora.cz)**

## Vyzkoušejte prototyp

Otevřete [`prototype/index.html`](prototype/index.html) v prohlížeči (funguje offline).
- Vlevo vyberte typ kódu, klepněte na kód ve scéně nebo na „Simulovat sken“.
- Nahoře přepínejte jazyk, tmavý režim, maskota × ikony, iOS 26 × iOS 18, iPhone SE, velké písmo a síť.
- Záložka „Testovací arch“ obsahuje skutečné kódy k vytištění.

## Jak projekt funguje

| Složka | Obsah |
|---|---|
| `shared/rules/` | Pravidla v JSON (váhy skóre, značky, parkování, prémiová čísla, texty signálů). Sdílí je iOS, Android i prototyp |
| `shared/testdata/` | Testovací korpus: kód → očekávaný typ, pole, pásmo a signály |
| `shared/content/` | Návody (ochrana u operátora, „Už jsem zadal údaje“) |
| `prototype/` | Interaktivní HTML prototyp |
| `ios/` | iOS aplikace a balíčky BQCore (analýza), BQServices (kontrola odkazu) a BQUI (obrazovky); sestavení popisuje [`ios/README.md`](ios/README.md) |
| `scripts/` | Generátory dat, referenční výpočet skóre, zvýšení verze, odeslání do TestFlightu |
| `docs/` | Architektura, výpočet rizika, soukromí, plán |

- Každá sada změn zvyšuje verzi o 0.0.1 a má záznam v [CHANGELOG.md](CHANGELOG.md).
- Vše testujeme lokálně. GitHub slouží jen jako úložiště; GitHub Actions nepoužíváme.

## Licence

- Kód je pod licencí **AGPL-3.0** ([LICENSE](LICENSE)).
- Firmy, které ho chtějí použít v uzavřeném nebo komerčním produktu, mohou získat [komerční licenci](COMMERCIAL.md).
- Příspěvky přijímáme pod [CLA](CLA.md); podrobnosti jsou v [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 🇬🇧 English

**Bezpečné QR (“Safe QR”) is a free app that explains what a QR code does before anything opens.** iOS first, Android later.

### Why
In September 2026 Czech journalist Janek Rubeš (Kluci z Prahy) exposed fake “SMS subscriptions” costing 99 CZK a week, charged through people's mobile operators. Victims often start them by scanning a QR sticker on a park bench, in a shopping centre or at a car park. Fake stickers on parking meters, “parcel surcharge” pages and “move your money to a safe account” scams work the same way. The phone camera opens a code with one tap and explains nothing.

### What the app does (V1 plan)
- **Checks every code first**, on the device, with no backend of our own.
- **Links:**
  - shows the real destination and the redirects it went through;
  - shows what the page asks for (phone number, card, password);
  - flags hidden subscriptions.

  The app loads the page itself, without your cookies and without running scripts. It stops before any mobile-operator payment gateway, so your number isn't exposed.
- **Payments:** shows the amount, account and bank for Czech QR Platba/QR Faktura, EPC, Swiss QR-bills and crypto. It warns that nobody verifies the recipient name inside a code.
- **SMS and phone traps:** detects premium-rate numbers (with their price) and call-forwarding codes.
- **Sensitive codes:** recognises login/device-link codes (WhatsApp, Telegram, Signal), 2FA exports, wallet seed phrases and profile installs. These are never stored or sent.
- **Result:** an indicative 0–100 risk score, the reasons behind it, and what will happen if you continue.
- **Privacy:** no ads, no tracking, no third-party SDKs. History stays on the phone.
- **Operator guide:** how to block third-party payments at Czech mobile operators.

### We're open to cooperation 🤝
We'd love to work with anyone who wants to help people avoid scams:
- banks, mobile operators, CZ.NIC, Whalebone / DNS4EU;
- security companies, CSIRT.CZ, NÚKIB, the Czech police;
- cities and parking operators, the media.

Topics include threat-intelligence and scam-account databases, warnings and testing. **Contact: [jakub@sejkora.cz](mailto:jakub@sejkora.cz)**

### Status
Done so far:
- an interactive HTML prototype of every screen;
- shared JSON rules;
- an 80-sample test corpus;
- **a working iOS app** ([`ios/`](ios/), on TestFlight for testers): camera and photo scanning, every code type, the link check (redirects, what the page asks for, Quad9 and domain age), the risk score with reasons, type cards and actions, history and settings.

Next: the image share extension, the printed-text-vs-QR check and tuning from testing. See [`docs/roadmap.md`](docs/roadmap.md).

### License
- The code is licensed under **AGPL-3.0**.
- A [commercial license](COMMERCIAL.md) is available on request.
- Contributions are accepted under the [CLA](CLA.md); see [CONTRIBUTING.md](CONTRIBUTING.md).
