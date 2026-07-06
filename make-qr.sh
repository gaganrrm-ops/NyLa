#!/data/data/com.termux/files/usr/bin/sh
# Generate a QR code that points at the GitHub repo's README. The README
# is the friend-facing setup guide; the QR just gets them there.
#
# Usage:
#   bash make-qr.sh <github-repo-url>
#
# Example (after you push this repo to GitHub):
#   bash make-qr.sh https://github.com/YOUR_USERNAME/omp-distro
#
# Output: setup-qr.png in the current directory. Encode it as the QR
# code in the README, or print it and hand it to a friend.

set -e
URL="${1:-https://github.com/REPLACE_WITH_YOUR_USERNAME/omp-distro}"
OUT=setup-qr.png

# Use a high error-correction level (~30% of the QR can be damaged and it
# still scans). -s 10 = 10px per module (a 25-character URL becomes a
# ~250px image, big enough to scan from a phone screen).
qrencode -l H -s 10 -m 4 -o "$OUT" "$URL"

echo
echo "QR code written to: $OUT"
echo "Encoded URL:        $URL"
echo
echo "Drop this PNG into the README wherever you want friends to scan it."
echo "Print it, send it in chat, or stick it on a business card."
