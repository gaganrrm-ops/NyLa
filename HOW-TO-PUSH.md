# How to publish this so friends can install it

Everything in this directory is ready to push to a fresh GitHub repo
and have your friends scan a QR code to install NyLa. Here's the
checklist, in order.

## 1. Create the GitHub repo

On github.com, create a new **public** repository. Name suggestion:
`NyLa`. Don't initialize it with a README or .gitignore (we have
our own). You'll get a URL like `https://github.com/gaganrrm-ops/NyLa`.

## 2. Push this directory

From your phone, in Termux:

```sh
cd /sdcard/Download/NyLa     # or wherever you put it
# OR, if you copied the files out of /root/NyLa into a Termux-
# accessible location like /data/data/com.termux/files/home/NyLa:
cd ~/NyLa

git init -b main
git add .
git commit -m "Initial NyLa distribution: install script, APK, README, QR"
git remote add origin https://github.com/gaganrrm-ops/NyLa.git
git push -u origin main
```

(You'll need a GitHub personal access token or the GitHub CLI
authenticated. Run `gh auth login` once if you haven't.)

## 3. Regenerate the QR code with the real URL

```sh
cd ~/NyLa
bash make-qr.sh https://github.com/gaganrrm-ops/NyLa
```

This overwrites `setup-qr.png` with one that points at the real repo.
Commit and push it:

```sh
git add setup-qr.png
git commit -m "QR points at real repo"
git push
```

## 4. Build the APK once, sign it once

The APK in this directory was built as a proof-of-concept, but its
keystore was generated on a different machine. To be safe, build it
fresh on your phone (it takes ~30 seconds):

```sh
cd ~/NyLa/apk
rm -rf build out keystore       # clean any old artifacts
bash build.sh                    # produces out/ny-la.apk
```

The `out/ny-la.apk` is ready to share. It will be self-signed with a
fresh debug key, generated on your phone, valid for 25 years.

## 5. Publish the APK as a GitHub Release

The install script pulls `install.sh` directly from the repo, but the
APK is a binary that should be uploaded as a Release asset (so the
`Releases` page link in the README works).

On github.com → your repo → **Releases** → **Draft a new release** →
tag: `v0.1.0`, target: `main`, title: `NyLa 0.1.0` → attach
`apk/out/ny-la.apk` → **Publish release**.

Now `https://github.com/gaganrrm-ops/NyLa/releases` has a
downloadable APK, and the README's "Releases page" link in Step 6
works.

## 6. Test the QR end-to-end (recommended)

Before sharing the QR with anyone:

- Open your phone's camera
- Point it at `setup-qr.png`
- It should open a browser to your GitHub repo's README
- From there, follow the README's steps in order

If anything fails at the README step (broken link, missing file, etc.),
fix it and re-push before sharing.

## 7. Share the QR

Ways to give the QR to a friend:
- **Text/chat**: send the `setup-qr.png` as an image attachment
- **In person**: print it (a 5cm × 5cm sticker is plenty)
- **Web**: embed it in a blog post or social media

Tell the friend: **"Point your phone camera at the QR; it'll open a
setup page; follow the steps in order; if anything looks scary, stop
and text me."** The README is honest about what's required, but a
human-friendly nudge helps.

## What if a friend's install fails

The most common failure points, in order of likelihood:
1. **They installed Termux from Play Store instead of F-Droid.**
   The install script detects this and warns + aborts. Tell them to
   uninstall Play Termux and install F-Droid Termux.
2. **They declined the storage permission dialog.** Tell them to
   re-run `termux-setup-storage` and accept.
3. **The proot Ubuntu download is slow / times out** (~500 MB).
   Have them retry with a faster network.
4. **Their phone is Android 6 or older.** The APK requires Android 7+.

The script logs to stdout, and the service logs go to
`/data/data/com.termux/files/usr/var/log/sv/ny-la-web/current`. Tell
them to share the last 50 lines of either when asking for help.
