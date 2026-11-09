# RealFaceAI: versioning & release process

How desktop app versions work, how to ship a new one, and how to force users
to update. Covers the Django backend and the Flutter desktop app.

---

## 1. Version numbers

- **Format:** `MAJOR.MINOR.PATCH`, e.g. `1.2.0`. Up to four number parts are
  allowed. Suffixes like `-beta` or `+45` are ignored when versions are
  compared.
- **Versions compare as numbers, not text**, so `1.0.10` is newer than
  `1.0.9`.
- **Where a build's version lives:** `kAppVersion` in
  `lib/config/app_version.dart`. The app sends it with every API request
  (`X-App-Version` header), so this is the value the backend checks.
- If you also set `version:` in `pubspec.yaml` (it's what macOS and Windows
  display), keep it identical.
- **When to bump:**
  - **PATCH** (`1.1.0 → 1.1.1`): bug fixes only.
  - **MINOR** (`1.1.1 → 1.2.0`): new features, or a new Decart SDK in
    `rt.js`.
  - **MAJOR** (`1.x → 2.0.0`): breaking changes, e.g. the app needs a new
    backend API.

---

## 2. Shipping a new desktop version

1. **Bump the version:** set `kAppVersion`, and `pubspec.yaml` if you use it.

2. **If you're updating the Decart SDK**, rebuild `assets/js/rt.js`:

   ```bash
   npm i @decartai/sdk@<version> esbuild
   echo "export { createDecartClient, models } from '@decartai/sdk';" > entry.js
   npx esbuild entry.js --bundle --format=esm --platform=browser \
     --target=chrome100,safari15 --minify --outfile=rt.js
   ```

   Copy the result to `assets/js/rt.js`. The app adds a fingerprint of the
   file to its address, so the WebView can't keep using an old cached copy.

3. **Build:**

   ```bash
   flutter build macos
   flutter build windows
   ```

   Then sign/notarize as usual.

4. **Upload the installers** to the website's download page
   (`downloads/mac/` and `downloads/windows/`, served at `/download/file/`).

5. **Publish the release:** in Django admin → **App releases** → **Add**,
   create one row per platform:

   | Field | What to enter |
   |---|---|
   | Platform | Windows or macOS |
   | Version | Exactly the same as `kAppVersion` |
   | Download URL | e.g. `https://realfaceai.app/download?platform=macos` |
   | Release notes | Users see these in the update prompt |
   | Mandatory | See section 3 |
   | Published / Published at | Set a future time to schedule the release |

6. **Check it worked:**

   ```bash
   curl "https://realfaceai.app/api/v1/app/latest-version/?platform=macos&current_version=1.0.5"
   ```

   The response should show the new `version`, plus `update_available` and
   `force_update`.

---

## 3. Optional vs forced updates

- **Optional** (Mandatory unticked): users on older builds see a notice they
  can dismiss.
- **Forced** (Mandatory ticked): everyone below that version gets a
  full-screen "Update required" page they can't dismiss. The API also refuses
  their requests with HTTP 426, and any live stream stops at its next
  10-second credit heartbeat.
- **Rule:** the minimum supported version is the **newest published release
  marked Mandatory**. Anyone below it must update. Anyone at or above it but
  below the latest version gets the optional notice.

  | Releases published | User on | Sees |
  |---|---|---|
  | 1.1.0 (Mandatory), 1.2.0 | 1.0.5 | Forced update |
  | 1.1.0 (Mandatory), 1.2.0 | 1.1.0 | Optional notice |
  | 1.1.0 (Mandatory), 1.2.0 | 1.2.0 | Nothing (up to date) |

- **When users see a change:**
  - The app checks at launch, every 30 minutes and when it comes back to the
    foreground.
  - A forced update also kicks in on the next API request.
  - The backend caches release data for up to 60 seconds.

---

## 4. Pulling or fixing a bad release

- **Pull a release:** untick **Published** on its row. Its forced update is
  lifted within about a minute.
- **Downgrade from forced to optional:** select it in the list and use the
  action *Make selected releases optional*.
- **Emergency off-switch:** set `APP_UPDATE_ENFORCE=false` in `.env` and
  restart. The backend then stops refusing old builds (no 426 errors), but the
  app's own update prompts still follow the Mandatory flag.

---

## 5. Older builds (1.0.x)

- Builds before 1.1.0 don't send their version, so the server can't block
  them. When a mandatory release exists, they only show their old notice that
  can't be dismissed.
- To cut them off completely, set `APP_UPDATE_BLOCK_UNVERSIONED_CLIENTS=true`
  in `.env` and restart. Only do this once most users are on 1.1.0 or later,
  because it refuses every API request that has no version.

---

## 6. Changing the streaming model

- The backend chooses the model with `STREAM_MODEL_ID` in `.env` (currently
  `lucy-2.5`). The app never hard-codes one.
- Before switching to a model the shipped `rt.js` doesn't know:
  1. Ship a build with an updated `rt.js` (section 2, step 2).
  2. Mark that build **Mandatory** so everyone moves to it.
  3. Then change `STREAM_MODEL_ID` and restart.

  If you switch first, users on the old build get "Please update the app"
  when they start a stream.

---

## 7. Settings reference (`.env`)

| Key | Default | Meaning |
|---|---|---|
| `APP_UPDATE_ENFORCE` | `true` | Backend refuses outdated builds with 426 |
| `APP_UPDATE_BLOCK_UNVERSIONED_CLIENTS` | `false` | Also refuse 1.0.x builds (no version header) |
| `APP_UPDATE_POLICY_CACHE_SECONDS` | `60` | How long each worker caches release data |
| `STREAM_MODEL_ID` | `lucy-2.5` | Streaming model the app uses |
| `STREAM_MODEL_NAME` | `Lucy 2.5` | Display name for that model |

---

## 8. Release checklist

- [ ] `kAppVersion` bumped (and `pubspec.yaml`)
- [ ] `rt.js` rebuilt, if the SDK changed
- [ ] macOS and Windows built, signed and uploaded
- [ ] Admin release rows added for both platforms, with versions matching exactly
- [ ] Mandatory decided
- [ ] `latest-version` check with `curl` passes
- [ ] Tested with an older build: it shows the notice or the forced update screen as expected