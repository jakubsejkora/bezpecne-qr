# Zásady ochrany soukromí — Bezpečné QR (NÁVRH)

> **Stav: návrh (verze 0.0.1).** Aplikace zatím není zveřejněná. Tento dokument popisuje plánované chování a před vydáním bude doplněn a zpřesněn.
> 🇬🇧 [English below](#-privacy-policy--draft)

**Správce:** Jakub Sejkora, [jakub@sejkora.cz](mailto:jakub@sejkora.cz)

## Co se děje v telefonu
- Kódy analyzujeme **přímo v telefonu**.
- Nepoužíváme reklamy, sledování ani analytické nástroje třetích stran.
- **Historie skenování** zůstává jen v telefonu. Můžete ji vypnout nebo smazat.
- **Citlivé kódy** (přihlašovací kódy, klíče 2FA, hesla k Wi‑Fi, obnovovací fráze, palubní vstupenky) neukládáme do historie a nikam je neodesíláme.

## Kontroly přes internet (lze vypnout v Nastavení)
- **Kontrola odkazu:** aplikace si stránku z kódu sama načte, podobně jako prohlížeč, ale bez vašich cookies, přihlášení a bez spouštění skriptů. Web se tím dozví totéž, co při otevření v prohlížeči (například vaši IP adresu).
- **Veřejné kontroly domény:** jen **název domény** posíláme bezpečnostnímu DNS **Quad9** (nezisková organizace ve Švýcarsku) a registru domén přes protokol RDAP, abychom zjistili stáří domény.

## Dobrovolné sdílení (plánováno, výchozí stav: vypnuto)
Sdílení je dostupné od 15 let. Obě volby jsou nezávislé a můžete je kdykoli vypnout.

1. **Sdílet údaje o podezřelých kódech:**
   - odkaz bez osobních údajů a tokenů, jeho přesměrování a zjištěné signály;
   - u podezřelých plateb banka, částka a číslo účtu (ukládáme jen jako zašifrovaný otisk, nikdy jméno příjemce);
   - přibližná poloha (≈ 1 km);
   - souhrnné statistiky bez obsahu kódů.
2. **Automaticky hlásit nebezpečné kódy s fotkou a přesnou polohou:**
   - jen u nebezpečných kódů naskenovaných kamerou;
   - fotka je oříznutá a obličeje, SPZ, jiné kódy a text na ní zakrýváme;
   - poloha ukazuje místo, kde stál telefon při skenování.

**Účel:** odhalování podvodných kampaní, zlepšování ochrany v aplikaci a dohledání podvodných nálepek. Databázi podvodů budujeme společně.

**Příjemci:**
- data zpracovává Cloudflare jako zpracovatel, s úložištěm v EU;
- po posouzení můžeme nezbytné údaje předat policii.

Data **neprodáváme** a nezveřejňujeme.

**Uchování:** fotky a přesnou polohu mažeme po 30 dnech, hlášení po 90 dnech, pokud není nutné je uchovat kvůli konkrétnímu případu.

**Vaše práva:**
- Každé hlášení má v telefonu soukromé „potvrzení“, se kterým ho můžete zobrazit, exportovat nebo smazat.
- Odvolání souhlasu smaže i odeslaná hlášení.
- Máte právo podat stížnost u Úřadu pro ochranu osobních údajů ([uoou.gov.cz](https://uoou.gov.cz)).

---

## 🇬🇧 Privacy policy — draft

> **Status: draft (version 0.0.1).** The app has not been released. This describes the planned behaviour and will be completed before release.

**Controller:** Jakub Sejkora, [jakub@sejkora.cz](mailto:jakub@sejkora.cz)

### On your phone
- Codes are **analysed on your phone**.
- No ads, no tracking, no third-party analytics.
- **Scan history** stays on your phone and can be turned off or cleared.
- **Sensitive codes** (login codes, 2FA keys, Wi‑Fi passwords, seed phrases, boarding passes) are never stored in history or sent anywhere.

### Internet checks (can be turned off in Settings)
- **Link check:** the app loads the page itself, like a browser but without your cookies or logins and without running scripts. The website learns what it would learn if you opened it (for example your IP address).
- **Public domain checks:** only the **domain name** is sent to the **Quad9** security DNS (a Swiss non-profit) and to the domain registry via RDAP, to learn the domain's age.

### Voluntary sharing (planned, off by default)
Sharing is available from age 15. The two options are independent and can be turned off at any time.

1. **Share details of suspicious codes:**
   - the link without personal data or tokens, its redirects and signals;
   - for suspicious payments, the bank, the amount and the account number (stored only as a keyed hash, never the payee's name);
   - approximate location (≈ 1 km);
   - content-free statistics.
2. **Automatically report dangerous codes with a photo and precise location:**
   - only for dangerous codes scanned with the camera;
   - the photo is cropped, and faces, number plates, other codes and text are masked;
   - the location is where the phone was when scanning.

**Purpose:** uncovering scam campaigns, improving protection in the app and locating scam stickers.

**Recipients:**
- Cloudflare processes the data, with storage in the EU;
- after assessment, necessary details may be passed to the police.

We **never sell** or publish the data.

**Retention:** photos and precise locations are deleted after 30 days, reports after 90 days, unless a specific case requires keeping them.

**Your rights:**
- Each report has a private receipt on your phone that lets you view, export or delete it.
- Withdrawing consent also deletes reports you've already sent.
- You may complain to the Czech data protection authority ([uoou.gov.cz](https://uoou.gov.cz)).
