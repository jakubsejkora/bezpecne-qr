/* UI strings. Sample-specific texts live in shared/rules/signals.json and the corpus. */
window.BQ = window.BQ || {};

BQ.strings = {
  cs: {
    'catalog.title': 'Katalog kódů', 'catalog.search': 'Hledat typ, doménu, ID…',
    'group.links': 'Odkazy', 'group.payments': 'Platby', 'group.comms': 'SMS, telefon, kontakty', 'group.security': 'Zabezpečení a zařízení',
    'group.places': 'Kalendář a místa', 'group.other': 'Ostatní a symbologie', 'group.scenarios': 'Scénáře',

    'ctl.lang': 'Jazyk', 'ctl.theme': 'Motiv', 'ctl.light': 'Světlý', 'ctl.dark': 'Tmavý', 'ctl.style': 'Styl', 'ctl.icons': 'Ikony', 'ctl.mascot': 'Maskot',
    'ctl.glass': 'Sklo', 'ctl.device': 'Zařízení', 'ctl.text': 'Písmo', 'ctl.textNormal': 'Běžné', 'ctl.textLarge': 'Velké',
    'ctl.net': 'Síť', 'ctl.online': 'Online', 'ctl.slow': 'Pomalá', 'ctl.offline': 'Offline',
    'ctl.scan': 'Simulovat sken', 'ctl.reset': 'Reset', 'ctl.onboarding': 'Onboarding', 'ctl.camera': 'Kamera zamítnuta', 'ctl.senior': 'Seniorský test',

    'scan.title': 'Skenovat', 'scan.hint': 'Namiřte na QR kód', 'scan.hintSub': 'Odkaz nejdřív zkontrolujeme.', 'scan.settings': 'Nastavení',
    'scan.gallery': 'Vybrat z Fotek', 'scan.tapCode': 'Klepněte na kód nebo použijte „Simulovat sken“.',
    'scan.stickerTip': 'Přejeďte po kódu prstem — není to nálepka přes původní kód?',
    'denied.title': 'Kamera není povolená', 'denied.text': 'Bez kamery neumíme kód naskenovat. Kód ale můžete vybrat z fotek.',
    'denied.settings': 'Otevřít Nastavení', 'denied.gallery': 'Vybrat z Fotek',

    'check.title': 'Kontroluji…', 'check.sub': 'Web zatím neotevíráme v prohlížeči.', 'check.expand': 'Rozbaluji zkrácený odkaz…',
    'check.address': 'Kontroluji adresu…', 'check.domain': 'Ověřuji doménu (Quad9, registr domén)…', 'check.redirects': 'Sleduji přesměrování — zatím {n}',
    'check.page': 'Čtu, co stránka chce…', 'check.cancel': 'Zrušit',

    'band.safe': 'Bez známých hrozeb', 'band.caution': 'Buďte opatrní', 'band.danger': 'Nebezpečné', 'band.incomplete': 'Nelze ověřit',
    'band.safeSub': 'V provedených kontrolách jsme nenašli varovné znaky.', 'band.incompleteSub': 'Kontrola není úplná.',
    'band.infoChip': 'Bez varovných znaků', 'band.alertKicker': 'Pozor na následky',
    'meter.label': 'Orientační skóre rizika', 'meter.fraud': 'Riziko podvodu', 'meter.low': 'nízké', 'meter.mid': 'střední', 'meter.high': 'vysoké',
    'meter.note': 'Vyšší číslo = rizikovější. Není to procento pravděpodobnosti.', 'meter.muted': '{score}/100 — pouze dostupné kontroly',

    'sec.why': 'Proč?', 'sec.consequence': 'Co se stane, když budete pokračovat', 'sec.checked': 'Co jsme zkontrolovali', 'sec.details': 'Podrobnosti kontroly',
    'sec.more': 'Další zjištění', 'sec.raw': 'Všechna data v kódu', 'sec.diag': 'Diagnostika (pro vývoj)', 'sec.incomplete': 'Kontrola neúplná', 'sec.manual': 'Zkontrolovat přesto',
    'sec.noManual': 'U jednorázových odkazů kontrolu ručně nespouštíme.',

    'act.openWeb': 'Otevřít web', 'act.preview': 'Izolovaný náhled', 'act.openAnyway': 'Otevřít přesto', 'act.back': 'Zpět ke skenování',
    'act.hold': 'Podržet 2 s a otevřít přesto', 'act.holdAlt': 'Nebo otevřít přes potvrzení', 'act.next': 'Skenovat další', 'act.close': 'Zavřít',
    'act.copyAccount': 'Kopírovat účet', 'act.copyAmount': 'Kopírovat částku', 'act.copyVS': 'Kopírovat VS', 'act.saveQR': 'Uložit QR do Fotek',
    'act.saveQRHint': 'Bankovní aplikace (např. George, Fio) umí QR načíst z galerie.', 'act.prepareSms': 'Připravit SMS', 'act.holdSms': 'Podržet 2 s a připravit SMS',
    'act.call': 'Zavolat', 'act.holdCall': 'Podržet 2 s a zavolat', 'act.compose': 'Napsat e-mail', 'act.addContact': 'Přidat do kontaktů', 'act.contactSaved': 'Uloženo v Kontaktech',
    'act.join': 'Připojit k síti', 'act.copyPw': 'Kopírovat heslo', 'act.addEvent': 'Přidat do kalendáře', 'act.maps': 'Otevřít v Mapách',
    'act.passwords': 'Otevřít v aplikaci Hesla', 'act.understand': 'Rozumím', 'act.appStore': 'Otevřít App Store', 'act.openService': 'Otevřít {service}',
    'act.copyText': 'Kopírovat text', 'act.report': 'Nahlásit…', 'act.subscribe': 'Podržet 2 s a přihlásit odběr', 'act.install': 'Podržet 2 s a instalovat',
    'act.copyAddress': 'Kopírovat adresu', 'act.blocked': 'Platbu nelze provést', 'act.rescan': 'Naskenovat znovu', 'act.continueHold': 'Podržet 2 s a pokračovat',

    'toast.copied': 'Zkopírováno', 'toast.savedPhotos': 'Uloženo do Fotek', 'toast.opened': 'Otevřeno (simulace)', 'toast.joined': 'Připojování k síti {ssid}…',
    'toast.event': 'Přidáno do kalendáře', 'toast.cancelled': 'Kontrola zrušena', 'toast.noCode': 'Na obrázku jsme nenašli žádný kód', 'toast.manual': 'V aplikaci by se teď stránka načetla ručně.',
    'toast.sms': 'SMS připravena ve Zprávách (simulace)', 'toast.call': 'Volání (simulace)', 'toast.mail': 'Otevřeno v Mailu (simulace)', 'toast.reportSent': 'Hlášení odesláno',

    'rep.countdown': 'Hlášení odešleme za {n} s', 'rep.cancel': 'Zrušit odeslání', 'rep.photoGps': 'Fotka okolí + přesná poloha', 'rep.dataOnly': 'Údaje o kódu (bez fotky)',
    'rep.sending': 'Odesílám hlášení…', 'rep.sent': 'Hlášení odesláno', 'rep.details': 'Podrobnosti', 'rep.failed': 'Hlášení čeká na připojení', 'rep.cancelled': 'Odeslání zrušeno',
    'rep.previewTitle': 'Co odešleme', 'rep.previewSub': 'Hlášení pomáhá odhalovat podvodné kampaně. Nic se neodešle bez vašeho souhlasu.', 'rep.send': 'Odeslat hlášení',
    'rep.off': 'Sdílení je vypnuté — toto hlášení odešleme jen tentokrát.', 'rep.fields': 'Obsah hlášení',

    'prev.title': 'Výtah ze stránky', 'prev.note': 'Ukazujeme text z již načtené stránky. Nic dalšího nenačítáme a nic nelze odeslat.',
    'prev.claim': 'Stránka o sobě tvrdí', 'prev.fields': 'Stránka chce vyplnit', 'prev.none': 'Stránku jsme nenačetli, výtah proto není k dispozici.',

    'choose.title': 'Našli jsme 2 kódy', 'choose.sub': 'Který chcete zkontrolovat?', 'choose.tip': 'Více kódů na jednom místě může znamenat nálepku přes původní kód. Neznamená to ale jistý podvod.',

    'set.title': 'Nastavení', 'set.history': 'Historie skenování', 'set.historyOn': 'Ukládat historii', 'set.historyFoot': 'Historie je jen v tomto telefonu. Hodí se, když chce rodina zkontrolovat, co jste skenovali.',
    'set.checks': 'Kontroly přes internet', 'set.pageFetch': 'Kontrola odkazu (načtení stránky)', 'set.pageFetchSub': 'Aplikace si stránku sama načte bez cookies a skriptů — jako prohlížeč, ale bez vašich dat.',
    'set.domain': 'Veřejné kontroly domény', 'set.domainSub': 'Jen název domény pošleme bezpečnostnímu DNS Quad9 a registru domén (stáří domény).',
    'set.privacy': 'Soukromí a sdílení', 'set.help': 'Pomoc', 'set.operator': 'Ochrana u operátora', 'set.recovery': 'Už jsem zadal(a) údaje', 'set.about': 'O aplikaci',
    'set.version': 'Verze', 'set.changelog': 'Co je nového', 'set.source': 'Zdrojový kód (GitHub)', 'set.coop': 'Spolupráce', 'set.license': 'Licence',
    'set.licenseVal': 'AGPL-3.0 + komerční licence',

    'hist.title': 'Historie', 'hist.empty': 'Zatím jste nic neskenovali.', 'hist.disabled': 'Ukládání historie je vypnuté.', 'hist.clear': 'Vymazat historii',
    'hist.recheck': 'Zkontrolovat znovu', 'hist.checked': 'Zkontrolováno {time}', 'hist.redacted': 'Obsah neuložen (citlivý kód)', 'hist.now': 'právě teď', 'hist.min': 'před {n} min',

    'priv.title': 'Soukromí a sdílení',
    'priv.p1': 'Analýza probíhá v telefonu. Bez vašeho souhlasu nic neodesíláme našemu týmu.',
    'priv.p2': 'Kontroly přes internet (načtení stránky, Quad9, registr domén) můžete vypnout výše v Nastavení.',
    'priv.p3': 'Historie zůstává jen v telefonu.',
    'priv.share': 'Pomozte chránit ostatní', 'priv.age': 'Je mi alespoň 15 let',
    'priv.a': 'Sdílet údaje o podezřelých kódech', 'priv.aSub': 'Odkaz bez osobních údajů, cesta odkazu, signály a přibližná poloha (≈1 km). Plus souhrnné statistiky bez obsahu.',
    'priv.b': 'Automaticky hlásit nebezpečné kódy s fotkou a přesnou polohou', 'priv.bSub': 'Jen u nebezpečných kódů naskenovaných kamerou. Obličeje, SPZ a text na fotce zakryjeme.',
    'priv.consent': '„Souhlasím s automatickým odesíláním údajů o podezřelém kódu, oříznuté a upravené fotografie a přesné polohy telefonu při skenování provozovateli projektu Bezpečné QR pro výzkum hrozeb a ověření nálepky; po posouzení může nezbytné údaje předat policii.“',
    'priv.delay': 'Čas na zrušení odeslání', 'priv.manual': 'Posílat až po mém potvrzení', 'priv.pending': 'Čekající hlášení', 'priv.receipts': 'Odeslaná hlášení (lze smazat)',
    'priv.deleteAll': 'Smazat všechna moje hlášení', 'priv.policy': 'Zásady ochrany soukromí', 'priv.none': 'Žádná',
    'priv.retention': 'Fotky a přesnou polohu mažeme po 30 dnech. Data nikdy neprodáváme a nezveřejňujeme.',
    'priv.ageNeeded': 'Sdílení je dostupné od 15 let.',

    'op.title': 'Ochrana u operátora', 'op.unverified': 'ověřte u operátora', 'op.tips': 'Užitečné tipy',
    'about.title': 'O aplikaci', 'about.text': 'Bezpečné QR je bezplatná aplikace, která před otevřením každého kódu vysvětlí, co dělá. Hledáme partnery — banky, operátory, CZ.NIC, bezpečnostní firmy i města.',

    'onb.1.title': 'Každý kód nejdřív zkontrolujeme', 'onb.1.text': 'Než cokoli otevřete, uvidíte, kam kód vede, co po vás chce a co se stane.',
    'onb.1.b1': 'Kontrola probíhá přímo v telefonu', 'onb.1.b2': 'Odkazy načítáme bez vašich cookies a skriptů', 'onb.1.b3': 'U plateb vidíte částku, účet a banku',
    'onb.2.title': 'Povolte kameru', 'onb.2.text': 'Kameru potřebujeme jen ke čtení kódů. Fotky neukládáme. Kód můžete vybrat i z galerie.',
    'onb.3.title': 'Pomozte chránit ostatní', 'onb.3.text': 'Obojí je dobrovolné a můžete to kdykoli vypnout v Nastavení.',
    'onb.continue': 'Pokračovat', 'onb.allowCamera': 'Povolit kameru', 'onb.done': 'Hotovo', 'onb.notNow': 'Teď ne', 'onb.skip': 'Přeskočit',

    'alert.camTitle': '„Bezpečné QR“ chce přístup ke kameře', 'alert.camText': 'Kameru používáme jen ke čtení kódů.', 'alert.deny': 'Nepovolit', 'alert.allow': 'Povolit',
    'alert.locTitle': 'Povolit aplikaci „Bezpečné QR“ používat vaši polohu?', 'alert.locText': 'Poloha se přiloží jen k hlášením nebezpečných kódů, aby šlo nálepku najít.',
    'alert.locOnce': 'Povolit jednou', 'alert.locWhile': 'Při používání aplikace',
    'alert.wifiTitle': 'Připojit k síti „{ssid}“?', 'alert.join': 'Připojit', 'alert.cancel': 'Zrušit',
    'alert.openTitle': 'Otevřít nebezpečnou stránku?', 'alert.openText': 'Zjistili jsme silné varovné znaky. Pokud stránku otevřete, nic na ní nezadávejte.', 'alert.open': 'Otevřít přesto',

    'safari.done': 'Hotovo', 'safari.warn': 'Otevřeli jste stránku, kterou jsme vyhodnotili jako nebezpečnou.',
    'picker.title': 'Fotky', 'picker.noCode': 'bez kódu', 'picker.two': '2 kódy',
    'common.yes': 'Ano', 'common.no': 'Ne', 'common.unknown': 'neznámé', 'common.back': 'Zpět',

    'type.url': 'Webový odkaz', 'type.spd': 'QR Platba', 'type.sid': 'QR Faktura', 'type.epc': 'Platba v eurech (EPC)', 'type.spc': 'Švýcarská QR faktura',
    'type.crypto': 'Kryptoměny', 'type.paybysquare': 'PAY by square', 'type.sms': 'SMS zpráva', 'type.tel': 'Telefonní číslo', 'type.mailto': 'E-mail',
    'type.contact': 'Kontakt', 'type.wifi': 'Wi‑Fi síť', 'type.event': 'Událost', 'type.webcal': 'Odběr kalendáře', 'type.geo': 'Místo na mapě',
    'type.otpauth': 'Ověřovací kód (2FA)', 'type.otpauth-migration': 'Export 2FA účtů', 'type.login': 'Přihlašovací kód', 'type.fido': 'Passkey',
    'type.seed': 'Obnovovací fráze', 'type.walletconnect': 'WalletConnect', 'type.app-install': 'Instalace aplikace', 'type.store': 'Obchod s aplikacemi',
    'type.messenger': 'Chat', 'type.data-uri': 'Vložená stránka', 'type.js-uri': 'Skript', 'type.intent': 'Odkaz pro Android', 'type.emvco': 'Obchodní platba (EMVCo)',
    'type.gs1': 'Kód výrobku (GS1)', 'type.bcbp': 'Palubní vstupenka', 'type.hc1': 'EU certifikát', 'type.text': 'Text',

    'pay.oneoff': 'Jednorázová platba', 'pay.standing': 'Trvalý příkaz — každý měsíc', 'pay.debit': 'Souhlas s inkasem', 'pay.invoice': 'Faktura', 'pay.instant': 'Okamžitá platba',
    'pay.to': 'Komu', 'pay.rn': 'Jméno příjemce je převzaté z kódu', 'pay.formatOnly': 'Správný formát účtu nepotvrzuje, komu účet patří.', 'pay.noAmount': 'Částka není uvedena',
    'pay.msg': 'Zpráva pro příjemce', 'pay.due': 'Splatnost', 'pay.first': 'První platba', 'pay.until': 'Platné do', 'pay.limit': 'Limit inkasa', 'pay.foreign': 'Zahraniční účet',
    'pay.invalidAmount': 'Neplatná částka', 'pay.bankUnknown': 'Banka neznámá',
    'inv.number': 'Číslo faktury', 'inv.issued': 'Vystaveno', 'inv.taxPoint': 'DUZP', 'inv.issuer': 'Dodavatel (IČO / DIČ)', 'inv.base': 'Základ daně', 'inv.vat': 'DPH', 'inv.total': 'Celkem',

    'url.target': 'Cíl odkazu', 'url.original': 'Naskenovaný odkaz', 'url.journey': 'Cesta odkazu (co jsme viděli)', 'url.asks': 'Co stránka chce', 'url.smallPrint': 'Drobným písmem na stránce',
    'url.claim': 'Stránka o sobě tvrdí', 'url.unknownTarget': 'Konečný cíl se nepodařilo zjistit.', 'url.stoppedBilling': 'Nenačteno — platební brána operátora',
    'url.stoppedTimeout': 'Neodpověděl včas', 'url.redirect': 'přesměrování', 'url.shortener': 'zkracovač odkazů', 'url.https': 'HTTPS varianta',
    'url.nothing': 'nic nevyžaduje', 'url.userinfo': 'Část před zavináčem je jen klam.', 'url.inner': 'Skutečný cíl uvnitř odkazu',
    'ask.card': 'číslo karty', 'ask.phone': 'telefonní číslo', 'ask.password': 'heslo / PIN', 'ask.licencePlate': 'SPZ',

    'sms.to': 'Komu', 'sms.premium': 'Prémiové číslo', 'tel.premium': 'Placená linka', 'mail.to': 'Komu', 'mail.subject': 'Předmět',
    'wifi.security': 'Šifrování', 'wifi.open': 'bez hesla', 'wifi.hidden': 'Skrytá síť', 'wifi.operator': 'Provozovatele sítě neověřujeme.', 'wifi.show': 'Ukázat', 'wifi.hide': 'Skrýt',
    'contact.more': 'Další údaje', 'crypto.network': 'Síť', 'crypto.address': 'Adresa', 'crypto.recipient': 'Příjemce', 'crypto.token': 'Token',
    'otp.issuer': 'Služba', 'otp.account': 'Účet', 'otp.secretHidden': 'Tajný klíč nezobrazujeme ani neukládáme.', 'mig.accounts': 'Účty v exportu',
    'seed.words': '{n} slov — skryto', 'store.appId': 'ID aplikace', 'chat.target': 'S kým', 'code.content': 'Obsah kódu', 'intent.package': 'Aplikace (balíček)',
    'intent.fallback': 'Záložní adresa', 'emv.merchant': 'Obchodník', 'emv.city': 'Město', 'emv.amount': 'Částka', 'gs1.gtin': 'GTIN', 'gs1.batch': 'Šarže', 'gs1.expiry': 'Spotřebujte do',
    'bcbp.seat': 'Sedadlo', 'bcbp.flight': 'Let', 'bcbp.date': 'Datum', 'pbs.text': 'Slovenská platba. Podrobnosti zatím neumíme zobrazit — naskenujte ji v bankovní aplikaci.',
    'hc1.text': 'Kód obsahuje zdravotní certifikát. Údaje neukládáme ani nezobrazujeme.', 'text.label': 'Text v kódu', 'geo.coords': 'Souřadnice',
  },

  en: {
    'catalog.title': 'Code catalogue', 'catalog.search': 'Search type, domain, ID…',
    'group.links': 'Links', 'group.payments': 'Payments', 'group.comms': 'SMS, phone, contacts', 'group.security': 'Security & devices',
    'group.places': 'Calendar & places', 'group.other': 'Other & symbologies', 'group.scenarios': 'Scenarios',

    'ctl.lang': 'Language', 'ctl.theme': 'Theme', 'ctl.light': 'Light', 'ctl.dark': 'Dark', 'ctl.style': 'Style', 'ctl.icons': 'Icons', 'ctl.mascot': 'Mascot',
    'ctl.glass': 'Glass', 'ctl.device': 'Device', 'ctl.text': 'Text', 'ctl.textNormal': 'Default', 'ctl.textLarge': 'Large',
    'ctl.net': 'Network', 'ctl.online': 'Online', 'ctl.slow': 'Slow', 'ctl.offline': 'Offline',
    'ctl.scan': 'Simulate scan', 'ctl.reset': 'Reset', 'ctl.onboarding': 'Onboarding', 'ctl.camera': 'Camera denied', 'ctl.senior': 'Senior test',

    'scan.title': 'Scan', 'scan.hint': 'Point at a QR code', 'scan.hintSub': 'We check the link first.', 'scan.settings': 'Settings',
    'scan.gallery': 'Choose from Photos', 'scan.tapCode': 'Tap the code or use “Simulate scan”.',
    'scan.stickerTip': 'Run a finger over the code — is it a sticker on top of the original?',
    'denied.title': 'Camera access is off', 'denied.text': 'We can’t scan without the camera. You can still pick a code from your photos.',
    'denied.settings': 'Open Settings', 'denied.gallery': 'Choose from Photos',

    'check.title': 'Checking…', 'check.sub': 'Nothing opens in your browser yet.', 'check.expand': 'Expanding the short link…',
    'check.address': 'Checking the address…', 'check.domain': 'Checking the domain (Quad9, domain registry)…', 'check.redirects': 'Following redirects — {n} so far',
    'check.page': 'Reading what the page asks for…', 'check.cancel': 'Cancel',

    'band.safe': 'No known threats', 'band.caution': 'Be careful', 'band.danger': 'Dangerous', 'band.incomplete': 'Can’t verify',
    'band.safeSub': 'Our checks found no warning signs.', 'band.incompleteSub': 'The check isn’t complete.',
    'band.infoChip': 'No warning signs', 'band.alertKicker': 'Mind the consequences',
    'meter.label': 'Indicative risk score', 'meter.fraud': 'Fraud risk', 'meter.low': 'low', 'meter.mid': 'medium', 'meter.high': 'high',
    'meter.note': 'Higher = riskier. It is not a probability percentage.', 'meter.muted': '{score}/100 — available checks only',

    'sec.why': 'Why?', 'sec.consequence': 'What happens if you continue', 'sec.checked': 'What we checked', 'sec.details': 'Check details',
    'sec.more': 'More findings', 'sec.raw': 'All data in the code', 'sec.diag': 'Diagnostics (for development)', 'sec.incomplete': 'Check incomplete', 'sec.manual': 'Check anyway',
    'sec.noManual': 'We never check single-use links manually.',

    'act.openWeb': 'Open website', 'act.preview': 'Isolated preview', 'act.openAnyway': 'Open anyway', 'act.back': 'Back to scanning',
    'act.hold': 'Hold 2 s to open anyway', 'act.holdAlt': 'Or open with a confirmation', 'act.next': 'Scan another', 'act.close': 'Close',
    'act.copyAccount': 'Copy account', 'act.copyAmount': 'Copy amount', 'act.copyVS': 'Copy VS', 'act.saveQR': 'Save QR to Photos',
    'act.saveQRHint': 'Banking apps (e.g. George, Fio) can read a QR from the gallery.', 'act.prepareSms': 'Prepare SMS', 'act.holdSms': 'Hold 2 s to prepare the SMS',
    'act.call': 'Call', 'act.holdCall': 'Hold 2 s to call', 'act.compose': 'Write e-mail', 'act.addContact': 'Add to Contacts', 'act.contactSaved': 'Saved in Contacts',
    'act.join': 'Join network', 'act.copyPw': 'Copy password', 'act.addEvent': 'Add to Calendar', 'act.maps': 'Open in Maps',
    'act.passwords': 'Open in Passwords', 'act.understand': 'Got it', 'act.appStore': 'Open App Store', 'act.openService': 'Open {service}',
    'act.copyText': 'Copy text', 'act.report': 'Report…', 'act.subscribe': 'Hold 2 s to subscribe', 'act.install': 'Hold 2 s to install',
    'act.copyAddress': 'Copy address', 'act.blocked': 'This payment can’t be made', 'act.rescan': 'Scan again', 'act.continueHold': 'Hold 2 s to continue',

    'toast.copied': 'Copied', 'toast.savedPhotos': 'Saved to Photos', 'toast.opened': 'Opened (simulated)', 'toast.joined': 'Joining {ssid}…',
    'toast.event': 'Added to Calendar', 'toast.cancelled': 'Check cancelled', 'toast.noCode': 'No code found in this picture', 'toast.manual': 'The app would now load the page on request.',
    'toast.sms': 'SMS prepared in Messages (simulated)', 'toast.call': 'Calling (simulated)', 'toast.mail': 'Opened in Mail (simulated)', 'toast.reportSent': 'Report sent',

    'rep.countdown': 'Sending the report in {n} s', 'rep.cancel': 'Cancel sending', 'rep.photoGps': 'Photo of the surroundings + precise location', 'rep.dataOnly': 'Code details (no photo)',
    'rep.sending': 'Sending the report…', 'rep.sent': 'Report sent', 'rep.details': 'Details', 'rep.failed': 'Report waiting for a connection', 'rep.cancelled': 'Sending cancelled',
    'rep.previewTitle': 'What we’ll send', 'rep.previewSub': 'Reports help uncover scam campaigns. Nothing is sent without your consent.', 'rep.send': 'Send report',
    'rep.off': 'Sharing is off — we’ll send this one report only.', 'rep.fields': 'Report contents',

    'prev.title': 'Page extract', 'prev.note': 'We show text from the page we already loaded. Nothing else is loaded and nothing can be submitted.',
    'prev.claim': 'The page claims to be', 'prev.fields': 'The page wants you to fill in', 'prev.none': 'We didn’t load the page, so there’s no extract.',

    'choose.title': 'We found 2 codes', 'choose.sub': 'Which one do you want to check?', 'choose.tip': 'Several codes in one place can mean a sticker over the original. It doesn’t prove a scam, though.',

    'set.title': 'Settings', 'set.history': 'Scan history', 'set.historyOn': 'Keep history', 'set.historyFoot': 'History stays on this phone. Handy when family wants to check what you scanned.',
    'set.checks': 'Internet checks', 'set.pageFetch': 'Link check (load the page)', 'set.pageFetchSub': 'The app loads the page itself without cookies or scripts — like a browser, but without your data.',
    'set.domain': 'Public domain checks', 'set.domainSub': 'Only the domain name goes to the Quad9 security DNS and the domain registry (domain age).',
    'set.privacy': 'Privacy & sharing', 'set.help': 'Help', 'set.operator': 'Operator protection', 'set.recovery': 'I already entered my details', 'set.about': 'About',
    'set.version': 'Version', 'set.changelog': 'What’s new', 'set.source': 'Source code (GitHub)', 'set.coop': 'Cooperation', 'set.license': 'License',
    'set.licenseVal': 'AGPL-3.0 + commercial license',

    'hist.title': 'History', 'hist.empty': 'You haven’t scanned anything yet.', 'hist.disabled': 'History is turned off.', 'hist.clear': 'Clear history',
    'hist.recheck': 'Check again', 'hist.checked': 'Checked {time}', 'hist.redacted': 'Content not stored (sensitive code)', 'hist.now': 'just now', 'hist.min': '{n} min ago',

    'priv.title': 'Privacy & sharing',
    'priv.p1': 'Analysis runs on your phone. Nothing goes to our team without your consent.',
    'priv.p2': 'Internet checks (loading the page, Quad9, domain registry) can be turned off in Settings above.',
    'priv.p3': 'History stays on your phone.',
    'priv.share': 'Help protect others', 'priv.age': 'I am at least 15 years old',
    'priv.a': 'Share details of suspicious codes', 'priv.aSub': 'The link without personal data, its redirect chain, signals and approximate location (≈1 km). Plus content-free statistics.',
    'priv.b': 'Automatically report dangerous codes with a photo and precise location', 'priv.bSub': 'Only for dangerous codes scanned with the camera. We mask faces, number plates and text in the photo.',
    'priv.consent': '“I agree to the automatic sending of details of a suspicious code, a cropped and redacted photo and my phone’s precise location at the time of scanning to the operator of the Bezpečné QR project for threat research and sticker verification; after assessment, necessary details may be passed to the police.”',
    'priv.delay': 'Time to cancel sending', 'priv.manual': 'Send only after I confirm', 'priv.pending': 'Pending reports', 'priv.receipts': 'Sent reports (can be deleted)',
    'priv.deleteAll': 'Delete all my reports', 'priv.policy': 'Privacy policy', 'priv.none': 'None',
    'priv.retention': 'Photos and precise locations are deleted after 30 days. We never sell or publish the data.',
    'priv.ageNeeded': 'Sharing is available from age 15.',

    'op.title': 'Operator protection', 'op.unverified': 'confirm with the operator', 'op.tips': 'Useful tips',
    'about.title': 'About', 'about.text': 'Bezpečné QR is a free app that explains what every code does before anything opens. We’re looking for partners — banks, operators, CZ.NIC, security firms and cities.',

    'onb.1.title': 'Every code is checked first', 'onb.1.text': 'Before anything opens, you see where a code leads, what it asks for and what will happen.',
    'onb.1.b1': 'Checks run right on your phone', 'onb.1.b2': 'Links are loaded without your cookies or scripts', 'onb.1.b3': 'For payments you see amount, account and bank',
    'onb.2.title': 'Allow the camera', 'onb.2.text': 'We only use the camera to read codes. We don’t store photos. You can also pick a code from your gallery.',
    'onb.3.title': 'Help protect others', 'onb.3.text': 'Both are voluntary and can be turned off any time in Settings.',
    'onb.continue': 'Continue', 'onb.allowCamera': 'Allow camera', 'onb.done': 'Done', 'onb.notNow': 'Not now', 'onb.skip': 'Skip',

    'alert.camTitle': '“Bezpečné QR” would like to access the camera', 'alert.camText': 'The camera is only used to read codes.', 'alert.deny': 'Don’t Allow', 'alert.allow': 'Allow',
    'alert.locTitle': 'Allow “Bezpečné QR” to use your location?', 'alert.locText': 'Location is attached only to reports of dangerous codes, so the sticker can be found.',
    'alert.locOnce': 'Allow Once', 'alert.locWhile': 'Allow While Using App',
    'alert.wifiTitle': 'Join the “{ssid}” network?', 'alert.join': 'Join', 'alert.cancel': 'Cancel',
    'alert.openTitle': 'Open a dangerous page?', 'alert.openText': 'We found strong warning signs. If you open it, don’t enter anything.', 'alert.open': 'Open anyway',

    'safari.done': 'Done', 'safari.warn': 'You opened a page we assessed as dangerous.',
    'picker.title': 'Photos', 'picker.noCode': 'no code', 'picker.two': '2 codes',
    'common.yes': 'Yes', 'common.no': 'No', 'common.unknown': 'unknown', 'common.back': 'Back',

    'type.url': 'Web link', 'type.spd': 'QR Platba', 'type.sid': 'QR Faktura', 'type.epc': 'Euro payment (EPC)', 'type.spc': 'Swiss QR-bill',
    'type.crypto': 'Crypto', 'type.paybysquare': 'PAY by square', 'type.sms': 'SMS message', 'type.tel': 'Phone number', 'type.mailto': 'E-mail',
    'type.contact': 'Contact', 'type.wifi': 'Wi‑Fi network', 'type.event': 'Event', 'type.webcal': 'Calendar subscription', 'type.geo': 'Place on a map',
    'type.otpauth': 'Verification code (2FA)', 'type.otpauth-migration': '2FA account export', 'type.login': 'Login code', 'type.fido': 'Passkey',
    'type.seed': 'Recovery phrase', 'type.walletconnect': 'WalletConnect', 'type.app-install': 'App install', 'type.store': 'App store',
    'type.messenger': 'Chat', 'type.data-uri': 'Embedded page', 'type.js-uri': 'Script', 'type.intent': 'Android link', 'type.emvco': 'Merchant payment (EMVCo)',
    'type.gs1': 'Product code (GS1)', 'type.bcbp': 'Boarding pass', 'type.hc1': 'EU certificate', 'type.text': 'Text',

    'pay.oneoff': 'One-off payment', 'pay.standing': 'Standing order — every month', 'pay.debit': 'Direct debit consent', 'pay.invoice': 'Invoice', 'pay.instant': 'Instant payment',
    'pay.to': 'To', 'pay.rn': 'The recipient name comes from the code', 'pay.formatOnly': 'A valid account format doesn’t confirm who owns the account.', 'pay.noAmount': 'No amount given',
    'pay.msg': 'Message for recipient', 'pay.due': 'Due date', 'pay.first': 'First payment', 'pay.until': 'Valid until', 'pay.limit': 'Debit limit', 'pay.foreign': 'Foreign account',
    'pay.invalidAmount': 'Invalid amount', 'pay.bankUnknown': 'Unknown bank',
    'inv.number': 'Invoice number', 'inv.issued': 'Issued', 'inv.taxPoint': 'Tax point', 'inv.issuer': 'Supplier (company ID / VAT)', 'inv.base': 'Tax base', 'inv.vat': 'VAT', 'inv.total': 'Total',

    'url.target': 'Link destination', 'url.original': 'Scanned link', 'url.journey': 'The link’s path (what we saw)', 'url.asks': 'What the page asks for', 'url.smallPrint': 'Small print on the page',
    'url.claim': 'The page claims to be', 'url.unknownTarget': 'We couldn’t determine the final destination.', 'url.stoppedBilling': 'Not loaded — operator payment gateway',
    'url.stoppedTimeout': 'Didn’t respond in time', 'url.redirect': 'redirect', 'url.shortener': 'link shortener', 'url.https': 'HTTPS variant',
    'url.nothing': 'nothing', 'url.userinfo': 'The part before the @ is only a decoy.', 'url.inner': 'The real destination inside the link',
    'ask.card': 'card number', 'ask.phone': 'phone number', 'ask.password': 'password / PIN', 'ask.licencePlate': 'number plate',

    'sms.to': 'To', 'sms.premium': 'Premium number', 'tel.premium': 'Premium line', 'mail.to': 'To', 'mail.subject': 'Subject',
    'wifi.security': 'Encryption', 'wifi.open': 'no password', 'wifi.hidden': 'Hidden network', 'wifi.operator': 'We don’t verify who runs the network.', 'wifi.show': 'Show', 'wifi.hide': 'Hide',
    'contact.more': 'More details', 'crypto.network': 'Network', 'crypto.address': 'Address', 'crypto.recipient': 'Recipient', 'crypto.token': 'Token',
    'otp.issuer': 'Service', 'otp.account': 'Account', 'otp.secretHidden': 'We never show or store the secret key.', 'mig.accounts': 'Accounts in the export',
    'seed.words': '{n} words — hidden', 'store.appId': 'App ID', 'chat.target': 'With', 'code.content': 'Code content', 'intent.package': 'App (package)',
    'intent.fallback': 'Fallback address', 'emv.merchant': 'Merchant', 'emv.city': 'City', 'emv.amount': 'Amount', 'gs1.gtin': 'GTIN', 'gs1.batch': 'Batch', 'gs1.expiry': 'Use by',
    'bcbp.seat': 'Seat', 'bcbp.flight': 'Flight', 'bcbp.date': 'Date', 'pbs.text': 'A Slovak payment. We can’t show the details yet — scan it in your banking app.',
    'hc1.text': 'This code holds a health certificate. We don’t store or show its data.', 'text.label': 'Text in the code', 'geo.coords': 'Coordinates',
  },
};

BQ.lang = 'cs';
BQ.t = function (key, args) {
  const table = BQ.strings[BQ.lang] || BQ.strings.cs;
  let s = table[key] ?? BQ.strings.cs[key] ?? key;
  if (args) s = s.replace(/\{(\w+)\}/g, (_, k) => (args[k] !== undefined ? BQ.pick(args[k]) : `{${k}}`));
  return s;
};
/** Pick a localized value from {cs, en} objects; pass through plain values. */
BQ.pick = function (v) {
  if (v && typeof v === 'object' && !Array.isArray(v) && ('cs' in v || 'en' in v)) return v[BQ.lang] ?? v.cs;
  return v;
};
