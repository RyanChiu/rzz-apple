# RZZ Static Landing Page (DMG Trial)

This folder contains the static landing page for the direct DMG trial channel.

## What Changed

- Bilingual page: English (default) + Chinese switch.
- Key highlights moved to the top: `App Lock` and `Import/Export Backup`.
- External variables are no longer embedded in `index.html`; they are read from `config.js`.

## Files

- `index.html`: page shell only (no hardcoded URLs).
- `styles.css`: page styles.
- `app.js`: language switch + text rendering + link binding.
- `config.js`: runtime variables (edit this file for deployment).
- `config.example.js`: template for `config.js`.

## Configure Links (Do This Before Publishing)

Edit `config.js`:

- `dmgUrl`
- `releasesUrl`
- `donateUrl` (PayPal)
- `feedbackEmail`
- `issuesUrl`
- `defaultLanguage` (`en` or `zh`)

## Deploy

Upload these files to your web path:

```bash
scp index.html styles.css app.js config.js user@your-server:/var/www/html/rzz/
```

## Git-Only Sync For `site/` On Server

If you want the server to pull only this directory via git:

```bash
mkdir -p /srv/rzz-site && cd /srv/rzz-site
git init
git remote add origin <YOUR_REPO_URL>
git config core.sparseCheckout true
printf "site/\n" > .git/info/sparse-checkout
git pull origin main
```

Then serve `/srv/rzz-site/site/` as web root (or copy its files to your public path).

To update later:

```bash
cd /srv/rzz-site
git pull origin main
```

## Compliance Note

- This page is for DMG direct distribution.
- For App Store build/channel, keep external donation links out of the app binary.
