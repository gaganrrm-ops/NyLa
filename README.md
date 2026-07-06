# NyLa

NyLa is a personal AI coding agent that runs on your Android phone. It
plugs into a Claude subscription or an Ollama Cloud API key, keeps
conversations locally, and can read your phone's storage and run shell
commands. The web UI is a single-page chat with streaming tool calls,
file attachments (APKs included), a `/` slash menu for installed
skills, and a settings panel for everything else.

This repo ships **two things**:
- `install.sh` — a one-shot setup that runs the NyLa server on your phone
- `ny-la.apk` — a small wrapper that turns the web UI into a real home-screen app

You need **both** for the full experience. Installing the APK without
running the script will leave you staring at a blank screen, because
the APK is a client — it talks to a server that has to be running
locally on your phone first.

## Before you start — the honest version

NyLa is a real piece of software that does real things on your phone.
Setting it up is more involved than installing an app from the Play
Store. Plan on **15–30 minutes** and on reading the steps below
carefully.

| Step | Time | Reversible? |
|------|------|-------------|
| Install F-Droid | 2 min | yes (uninstall) |
| Install Termux from F-Droid | 2 min | yes |
| Grant Termux storage permission | 30 sec | yes |
| Install Termux:API, Termux:Boot | 2 min | yes |
| Run `bash install.sh` | 5–10 min | yes (`--uninstall`) |
| Install the APK | 30 sec | yes |
| Set up the model provider (Claude OAuth or Ollama key) | 2 min | yes |

What you need:
- An Android 7.0+ phone
- ~1.5 GB of free storage (Ubuntu container + bun + NyLa)
- A Claude **subscription** login, **or** an Ollama Cloud API key
  (get one at [ollama.com/settings/keys](https://ollama.com/settings/keys))
- Comfort running shell commands (copy-paste, type a few `y`s)

## Step 1: Install F-Droid

F-Droid is a free app store for open-source Android apps. NyLa needs
Termux from F-Droid, not the Play Store version (the Play build is
outdated and has known issues with the storage permission that NyLa
depends on).

- Install F-Droid from [f-droid.org](https://f-droid.org/)
- Open F-Droid, let it finish its initial repo sync (a few minutes)

## Step 2: Install Termux and friends from F-Droid

In F-Droid, install these three apps:

- **Termux** (the terminal emulator)
- **Termux:API** (lets the NyLa server access the file picker, mic, TTS)
- **Termux:Boot** (auto-starts NyLa when your phone reboots)

⚠️ **Do not install Termux from the Play Store.** It is broken. The
F-Droid build is the supported one.

Open Termux. You'll see a command prompt like `~ $`. That's where the
rest of this guide happens.

## Step 3: Grant Termux storage permission

Run this command in Termux:

```sh
termux-setup-storage
```

A system dialog will pop up asking for "Allow Termux to access photos
and media" (or "All files access" on newer Android). Accept it. This
is what lets NyLa see your phone's `/sdcard` storage and read attached
APKs.

If the dialog doesn't appear, open **Android Settings → Apps → Termux →
Permissions → Files and media** and toggle it on, then re-run the
command.

## Step 4: Run the installer

In the Termux command prompt, paste this one line and press Enter:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/gaganrrm-ops/NyLa/main/install.sh)
```

The script will:
- Update Termux's package index
- Install `proot-distro` and `termux-services`
- Download the Ubuntu container (~500 MB — this is the slowest step)
- Install Bun (the JavaScript runtime NyLa uses)
- Clone the NyLa web source from this repo
- Install the background-service script and the boot-time auto-start hook
- Start the server

When the script finishes, you should see:

```
  ✓ NyLa is installed and running.

  Open the web UI in Chrome:
      http://127.0.0.1:7317
```

If you see any red `✗` lines, scroll up and look at the corresponding
step's output. The most common issue is storage permission not being
granted (re-run `termux-setup-storage` and re-run the install script).

## Step 5: Verify the web UI

Open **Chrome** on your phone and go to:

```
http://127.0.0.1:7317
```

You should see the NyLa chat UI with the lion icon. If you see a blank
page or "connection refused", the server isn't running. Check the
logs:

```sh
tail -f /data/data/com.termux/files/usr/var/log/sv/ny-la-web/current
```

(press Ctrl-C to stop tailing.)

For a proper home-screen icon, in Chrome tap the menu (three dots) →
**Add to Home screen**. Now NyLa has a lion icon that opens directly to
the chat.

## Step 6: Install the NyLa APK

This is optional — the PWA from Step 5 is fully functional. But if
you want a real APK with a real launcher icon:

1. Download `ny-la.apk` from the [Releases page](../../releases) on
   this repo onto your phone.
2. Open the file. Android will ask you to allow installs from this
   source — accept it (Settings → Apps → Special access → Install
   unknown apps → your file manager → Allow).
3. Tap **Install**.

The NyLa app appears in your app drawer with the lion icon. Tapping it
opens the NyLa web UI in a Chrome-backed WebView (no browser chrome,
no URL bar, fullscreen chat).

⚠️ The APK is signed with a self-generated debug key, not a Google
Play key. That's fine for personal use and side-loading to a few
friends, but it means **Android will warn on every install/update**
and **Google Play Protect may flag the file**. If you want to share
the APK widely, you'll need to either set up your own signing key or
publish through a channel that accepts debug-signed APKs.

## Step 7: Set up the model provider

NyLa defaults to needing either:
- A **Claude** subscription login (your existing Anthropic account), or
- An **Ollama Cloud** API key

To set it up: open the NyLa app (or PWA), tap the **⚙** button in the
top bar → **Model** badge in the top bar (or the model badge shows
"Claude" or the current model). Follow the prompts:

- For Claude: nothing to do — it's the default. (The SDK uses your
  existing Anthropic OAuth session if you've logged in via the NyLa
  CLI before; otherwise it'll prompt you to log in the first time you
  send a message.)
- For Ollama Cloud: paste your API key, tap **Sync models**, pick one,
  tap **Use selected model**. The key is stored locally in
  `~/.omp/agent/models.yml` with `0600` permissions.

## What's in the settings panel

Tap the **⚙** gear icon in the top bar:

- **Device storage** — shows the live status of your phone's shared
  storage mount. NyLa can read and write to it directly.
- **Skills** — paste a GitHub or Hugging Face URL, tap **Configure**.
  NyLa will clone the repo, install any dependencies, and register the
  skill globally. Use the `/` menu in the chat composer to invoke it.
- **Kill app** — stops the NyLa server. To bring it back, tap the
  lion icon on your home screen (your launcher should run
  `ny-la-start` to do that — see the "Kill and relaunch" section
  in `ny-la-web/README.md` for the wiring).

## What if the app or phone misbehaves?

- **NyLa shows "stopped" instead of the chat**: the server is down. In
  Termux run `sv up ny-la-web`. If that doesn't help, check the log
  with `tail -50 /data/data/com.termux/files/usr/var/log/sv/ny-la-web/current`.
- **The chat hangs or the model "regenerates" answers**: your mobile
  network is flapping. The NyLa web app is designed to handle this
  without duplicating answers — let it finish reconnecting.
- **An APK upload fails**: the file is over 200MB. NyLa caps uploads
  at 200MB; real APKs are usually under 100MB but split-APK bundles
  can be larger.
- **You see an Anthropic / Claude auth error**: open the **⚙ → Model
  panel → Claude** and re-authenticate.
- **You want to start over**: `bash <(curl ...) --uninstall`.

## Uninstalling

In Termux:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/gaganrrm-ops/NyLa/main/install.sh) --uninstall
```

Then uninstall Termux, Termux:API, Termux:Boot, and the NyLa APK from
Android's app settings.

## Files on your phone after install

- Termux home: `/data/data/com.termux/files/home/`
- Service config: `/data/data/com.termux/files/usr/var/service/ny-la-web/`
- Service log: `/data/data/com.termux/files/usr/var/log/sv/ny-la-web/current`
- NyLa web app: `/root/ny-la-web/` (inside the Ubuntu container)
- NyLa data: `/root/ny-la-workspace/` (inside the Ubuntu container)
  - `.access-token` — random auth token (auto-injected into the page)
  - `uploads/` — files you've attached
  - `sessions/` — conversation history
- NyLa skills: `/root/.omp/agent/skills/`
- NyLa config: `/root/.omp/agent/config.yml`, `models.yml`
