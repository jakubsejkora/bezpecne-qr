# Zásady ochrany soukromí — Bezpečné QR

> Popis interní verze **0.0.10**, aktualizováno **4. října 2026**. Před veřejným vydáním zbývá dokončit kontrolu zveřejněných podkladů a údajů v App Store Connect.
> 🇬🇧 [English below](#privacy-policy--english)

**Provozovatel a kontakt:** Jakub Sejkora, [jakub@sejkora.cz](mailto:jakub@sejkora.cz).

## Analýza a obrázky

Kódy rozpoznáváme a vyhodnocujeme v zařízení. Aplikace neobsahuje reklamy, sledovací ani analytické SDK. Týmu Bezpečné QR automaticky neodesílá kódy, obrázky, polohu ani statistiky. Hlášení podvodů a komunitní databáze nejsou součástí této verze.

Kameru používáme ke skenování. Z Fotek nebo systémového sdílení načteme pouze obrázek, který vyberete. Aplikace snímky ani výřezy neukládá do historie a neposílá je ke kontrole na server. Náhledy jsou dočasné; pokud některý rozpoznaný kód obsahuje citlivé údaje, zachycený obrázek zahodíme. Uložení nově vytvořeného platebního QR kódu do Fotek je samostatná akce, kterou musíte vybrat.

## Historie

Historie je místní databáze aplikace. Lze ji vypnout nebo smazat v Nastavení. U běžných kódů obsahuje původní obsah, datum, typ a výsledek kontroly; u rozbaleného odkazu také zjištěnou cílovou doménu. Při opětovné kontrole používáme původní kód, protože cíl se může změnit.

Obsah citlivých kódů (například přihlašovací tokeny, klíče 2FA, hesla Wi-Fi a obnovovací fráze) do historie neukládáme. Hlavní aplikace může uchovat omezený souhrn, například typ kódu, název sítě či služby a výsledek, bez hesla nebo tokenu. Rozšíření pro sdílení citlivé kódy do historie nepřenáší vůbec.

Necitlivé výsledky z rozšíření přecházejí do aplikace přes místní sdílené úložiště App Group. Neimportované záznamy mají platnost nejvýše sedm dní; při importu či další práci s úložištěm se prošlé záznamy odstraní. Smazání nebo vypnutí historie zneplatní i čekající zápisy. Aplikace historii nesynchronizuje přes CloudKit; zálohování dat zařízení řídí nastavení iOS.

Nové uložené kontroly mohou obsahovat také důvod nedokončení, stav zjištění cíle, zapnuté kontroly, časové údaje jednotlivých kroků, kategorii síťové chyby, HTTP stav, bezpečně omezené údaje o navštívených doménách a identifikátory zjištění. Tyto diagnostické údaje neobsahují text stránky, HTTP hlavičky, cesty ani parametry adres. Starší záznamy chybějící údaje nedoplňují automatickou kontrolou.

Interní testovací verze nabízí export historie. Před sdílením ukáže skutečný obsah JSON; běžné uložené odkazy, texty, kontakty a platby mohou obsahovat osobní údaje. Rozpoznaná tajemství a chráněné přístupové odkazy při exportu znovu skryje. Přidá verzi aplikace/iOS a omezený seznam stavů kamery bez snímků, obsahu kódů či trvalého identifikátoru zařízení. Soubor odešlete jen vlastní volbou příjemce v systémovém sdílení; automatické odesílání neexistuje. Dočasnou kopii po dokončení nebo zrušení sdílení odstraníme.

## Volitelné internetové kontroly

Při zachycení více kódů mohou způsobilé internetové kontroly proběhnout před výběrem konkrétního kódu. Do historie ukládáme pouze zvolené výsledky. Obě kontroly lze nezávisle vypnout v Nastavení. Při prvním použití vysvětlujeme jejich síťový provoz.

- **Kontrola odkazu:** aplikace načte způsobilou HTTPS adresu a její pozorovaná přesměrování bez cookies, přihlášení a spouštění JavaScriptu. Navštívené servery a DNS resolver mohou vidět údaje nutné k požadavku, například IP adresu; web vidí požadovanou cestu a parametry. Fragment za `#` se neposílá. Citlivé odkazy, tokeny, místní sítě a operátorské/platební brány chrání pravidla, která platí před každým požadavkem.
- **Veřejné kontroly domény:** názvy způsobilých veřejných hostitelů/domén předáváme DNS službě Quad9 a příslušnému RDAP registru pro kontrolu blokace a stáří domény. Nepředáváme jim cestu odkazu, parametry, obrázek ani obsah QR kódu. Služby vidí síťové údaje svého spojení.

Některé cíle nelze bez JavaScriptu, cookies nebo přihlášení zjistit. Výsledek takovou kontrolu označí jako nedokončenou. Zjištěná adresa není zárukou pozdějšího chování webu.

## Akce, které vyberete

Otevření odkazu, hovor, SMS, e-mail, připojení Wi-Fi, uložení kontaktu či události a kopírování jsou uživatelské akce. Vybraná data se mohou předat odpovídající systémové aplikaci nebo službě. Kopírovaná hesla nastavujeme pouze pro toto zařízení s vypršením po dvou minutách. Ostatní kopírovaný text používá běžnou systémovou schránku.

Dotazy k datům můžete poslat na uvedený kontakt. Máte právo podat stížnost u [Úřadu pro ochranu osobních údajů](https://uoou.gov.cz). Plány pro případný budoucí reporting jsou oddělené v [návrhu sběru dat](docs/data-collection.md) a nepopisují provoz této verze.

---

## Privacy policy — English

This describes internal version **0.0.10**, updated **4 October 2026**. Public-release materials and App Store Connect privacy declarations still require their final review.

**Operator and contact:** Jakub Sejkora, [jakub@sejkora.cz](mailto:jakub@sejkora.cz).

### Analysis and images

Codes are recognized and analyzed on your device. The app includes no advertising, tracking or analytics SDKs. It sends no codes, images, location or statistics automatically to the Bezpečné QR team. Scam reporting and a community database are not included in this version.

The camera is used for scanning. From Photos or the system share sheet, we read only the image you select. The app does not store images or crops in history or upload them for analysis. Previews are temporary; captured imagery is discarded when any detected candidate contains sensitive data. Saving a newly generated payment QR to Photos is a separate action you select.

### History

History is a local app database that you can disable or clear in Settings. Ordinary records include the original payload, date, type and check result; resolved links also include the destination domain. Rechecking uses the original code because destinations can change.

Sensitive payloads, including sign-in tokens, 2FA secrets, Wi-Fi passwords and recovery phrases, are not stored in history. The main app may retain a limited summary, such as the code type, network or service name and result, without the password or token. The share extension never transfers sensitive codes into history.

Non-sensitive extension results reach the app through local App Group storage. Pending entries expire after seven days and expired entries are removed when the inbox is read or maintained. Clearing or disabling history invalidates pending writes too. The app does not sync history through CloudKit; device backup is controlled by iOS settings.

New saved checks may also include the incomplete-check reason, destination-resolution state, enabled checks, stage timings, transport-error category, HTTP status, bounded public-domain observations and finding identifiers. These diagnostics contain no page text, HTTP headers, URL paths or queries. Older entries are not automatically rechecked to backfill missing diagnostics.

The internal testing build offers history export. It previews the actual JSON before sharing; ordinary saved links, text, contacts and payments may contain personal information. Detected secrets and protected access links are redacted again at export time. The export adds app/iOS versions and a bounded camera-state log, with no images, QR contents in that log or persistent device identifier. You choose the recipient in the system share sheet; nothing is uploaded automatically. The temporary local file is removed after completion or cancellation.

### Optional internet checks

When multiple codes are captured, eligible online checks may run before you select one. Only selected results enter history. Both checks can be disabled independently in Settings. Their network use is explained before first use.

- **Link check:** the app loads eligible HTTPS addresses and observed redirects without cookies, sign-in or JavaScript execution. Contacted servers and the DNS resolver may see connection data such as your IP address; websites see the requested path and query. URL fragments after `#` are not transmitted. Safety rules protect sensitive/token links, local networks and operator/carrier-billing hosts before every request.
- **Public domain checks:** eligible public host/domain names are sent to Quad9 and the relevant RDAP registry to check blocking and registration age. These services receive no URL paths, query parameters, images or QR payloads. They see their connection's network data.

Some destinations cannot be established without JavaScript, cookies or sign-in. Such checks are marked incomplete. An observed address does not guarantee what the website will do later.

### Actions you choose

Opening a link, calling, preparing a message, joining Wi-Fi, saving a contact/event and copying are user-selected actions. Relevant data may be passed to the corresponding system app or service. Copied passwords are device-local and expire after two minutes. Other text uses the ordinary system clipboard.

Contact us above with data questions. You may complain to the [Czech data protection authority](https://uoou.gov.cz). Future reporting proposals are kept separately in the [data-collection draft](docs/data-collection.md); they do not describe this version's operation.
