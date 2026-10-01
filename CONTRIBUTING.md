# Contributing to Bezpečné QR

Thanks for helping protect people from QR scams! Czech or English is fine for issues and PRs.

## Ground rules
- **Privacy first.** Never add analytics, advertising or third-party SDKs. Sensitive codes (2FA secrets, login tokens, Wi‑Fi passwords, seed phrases) must never be stored, logged or sent.
- **Shared rules and data live in `shared/`.** The prototype, the iOS app and the future Android app read the same JSON. If you change scoring or texts, change them there, not in a platform.
- **Honest wording.** We never promise "safe". The score is an *orientační skóre rizika* (indicative risk index), not a probability.
- **Only redistributable data sources.** Check the license before bundling any list. CERT.PL, Unicode data, the Public Suffix List and CC BY-SA lists (with attribution) are fine; non-redistributable feeds are not.

## Workflow
1. Branch from `main` and make your change.
2. Run the checks locally. There is **no CI and no GitHub Actions**; everything is tested on a developer machine.
   - `node scripts/gen-prototype-data.mjs` validates the corpus against the reference engine.
   - Open `prototype/index.html` and review affected screens.
   - Once the iOS app exists: `swift test` in `ios/Packages/*` and `xcodebuild test`.
3. **Bump the version by +0.0.1** with `scripts/bump-version.sh "Short summary"`. Every change set that touches the app, prototype, rules or data gets a bump (0.0.9 → 0.0.10). It also creates a `CHANGELOG.md` entry; edit it so people can follow what changed.
4. Open a pull request against `main`. The maintainer reviews and merges.

## Adding a new code type or rule
- Add samples to `shared/testdata/samples.json`: payload, parsed fields, expected band and signal IDs.
- Add signal texts (CZ + EN) to `shared/rules/signals.json` and weights to `shared/rules/weights.json`.
- Use fictional, unregistered domains and synthetic account numbers in samples. Real ones only for official allowlist examples.

## Contributor License Agreement
By opening a pull request you agree to the [CLA](CLA.md). Please confirm in the PR with:
> I have read the CLA (CLA.md, v1.0) and I agree to its terms.

## Security issues
Please don't open public issues for vulnerabilities. E-mail **jakub@sejkora.cz**.
