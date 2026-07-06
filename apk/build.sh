#!/data/data/com.termux/files/usr/bin/sh
# Build ny-la.apk from the source in apk/. Requires:
#   - JDK 17+ (this host has 17 and 25; we use 17 for source/target compat)
#   - Android SDK platform 34 (provides android.jar; aapt2 needs it)
#   - aapt2, d8, apksigner, zipalign on PATH (the Debian-packaged arm64
#     copies are what we use; the official 34.0.0 build-tools is x86_64
#     only and would refuse to run on this arm64 device)
#   - The system jar tool (used to inject classes.dex into the unsigned
#     APK, because the Debian aapt2 2.19 is too old to have an `add`
#     subcommand)
#
# Output: apk/out/ny-la.apk -- a release-mode APK signed with the v1+v2+v3
# schemes using a self-generated debug key (created on first run, reused
# thereafter). The user (you) signs the APK and uploads it to whichever
# distribution channel you use; the debug-key signature is fine for
# personal side-loading and friend-to-friend sharing.
#
# This script is intentionally self-contained so it can be re-run from
# any environment (the proot Ubuntu dev shell, a CI runner, or a
# friend's laptop if they want to rebuild the APK themselves).

set -e
cd "$(dirname "$0")"

APK_DIR=$PWD
SRC_DIR=$APK_DIR/src
RES_DIR=$APK_DIR/res
MANIFEST=$APK_DIR/AndroidManifest.xml
BUILD=$APK_DIR/build
OUT=$APK_DIR/out
KEYSTORE=${KEYSTORE_PATH:-$APK_DIR/keystore/debug.jks}
KEY_ALIAS=nyla
# keytool in modern JDKs requires a password of >= 6 chars; "omp" is too
# short. Use a longer dev-only password; this is debug-signed, not for
# Play Store distribution.
KEY_PASS=nyla-android

# Tool resolution. We prefer the cmdline-tools path for d8 (it's a JVM
# script so it works on any arch), and the apt /usr/bin copies for
# aapt2/apksigner/zipalign (those are arm64 on this device, the Google
# build-tools 34.0.0 download is x86_64).
SDK_ROOT=${ANDROID_SDK_ROOT:-/opt/android-sdk}
CT=$SDK_ROOT/cmdline-tools/latest
AAPT2=$(command -v aapt2 || echo /usr/bin/aapt2)
D8="$CT/bin/d8"
APKSIGNER=$(command -v apksigner || echo /usr/bin/apksigner)
ZIPALIGN=$(command -v zipalign || echo /usr/bin/zipalign)
JAVAC=${JAVAC:-/usr/lib/jvm/java-17-openjdk-arm64/bin/javac}
JAR=$(command -v jar)
ANDROID_JAR=${ANDROID_JAR:-$SDK_ROOT/platforms/android-34/android.jar}

# Sanity check
for t in "$AAPT2" "$D8" "$APKSIGNER" "$ZIPALIGN" "$JAVAC" "$JAR"; do
	[ -x "$t" ] || { echo "missing tool: $t" >&2; exit 1; }
done
[ -f "$ANDROID_JAR" ] || { echo "missing android.jar: $ANDROID_JAR" >&2; echo "  hint: install via sdkmanager 'platforms;android-34'" >&2; exit 1; }

mkdir -p "$BUILD" "$OUT"

# Keystore -- generated once, then reused for subsequent builds. The dname
# must have a valid 2-letter country code (C=US works) -- keytool rejects
# "C=NA" as an empty issuer.
if [ ! -f "$KEYSTORE" ]; then
	echo ">> generating debug keystore at $KEYSTORE"
	mkdir -p "$(dirname "$KEYSTORE")"
	keytool -genkeypair -v -keystore "$KEYSTORE" \
		-alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 \
		-validity 9125 \
		-storepass "$KEY_PASS" -keypass "$KEY_PASS" \
		-dname "CN=NyLa, OU=Personal, O=NyLa, L=Local, ST=NA, C=US" 2>&1 | tail -5
fi

# Step 1: compile resources
echo ">> aapt2 compile"
"$AAPT2" compile --dir "$RES_DIR" -o "$BUILD/res.zip"

# Step 2: link resources + manifest, emitting R.java so the next step
# (javac) can resolve the layout/widget IDs at compile time.
echo ">> aapt2 link"
GENS=$BUILD/gen
rm -rf "$GENS" && mkdir -p "$GENS"
"$AAPT2" link \
	-I "$ANDROID_JAR" \
	--manifest "$MANIFEST" \
	--java "$GENS" \
	-o "$BUILD/unsigned.apk" \
	"$BUILD/res.zip"

# Step 3: compile Java (R.java from step 2 is in the gen dir)
echo ">> javac"
CLASSES=$BUILD/classes
rm -rf "$CLASSES" && mkdir -p "$CLASSES"
find "$SRC_DIR" "$GENS" -name '*.java' > "$BUILD/sources.txt"
"$JAVAC" -source 1.8 -target 1.8 \
	-bootclasspath "$ANDROID_JAR" \
	-classpath "$ANDROID_JAR" \
	-d "$CLASSES" \
	@"$BUILD/sources.txt"

# Step 4: dex
echo ">> d8"
"$D8" --min-api 24 --output "$BUILD" "$CLASSES"/com/nyla/app/*.class

# Step 5: inject classes.dex into the unsigned APK. The Debian aapt2 2.19
# doesn't have an `add` subcommand (that landed in newer versions), so we
# use `jar` (or `zip`, if installed) to inject the dex at the right path.
# jar handles the deflate + STORED compression correctly for APK format.
echo ">> jar add classes.dex"
cd "$BUILD" && "$JAR" uf unsigned.apk classes.dex && cd - >/dev/null

# Step 6: zipalign (4-byte alignment for resources; -p for page-aligned
# native libs, which we don't have, but the flag is harmless).
echo ">> zipalign"
ALIGNED=$OUT/ny-la-aligned.apk
"$ZIPALIGN" -p -f 4 "$BUILD/unsigned.apk" "$ALIGNED"

# Step 7: sign with v1+v2+v3 schemes. All three for maximum compat:
#   v1 = old-style JAR signing (works on Android 1+)
#   v2 = APK Signature Scheme v2 (Android 7+)
#   v3 = APK Signature Scheme v3 (Android 9+; supports key rotation)
echo ">> apksigner sign"
"$APKSIGNER" sign \
	--ks "$KEYSTORE" \
	--ks-key-alias "$KEY_ALIAS" \
	--ks-pass "pass:$KEY_PASS" \
	--key-pass "pass:$KEY_PASS" \
	--v1-signing-enabled true \
	--v2-signing-enabled true \
	--v3-signing-enabled true \
	--out "$OUT/ny-la.apk" \
	"$ALIGNED"

# Step 8: verify
echo ">> apksigner verify"
"$APKSIGNER" verify --print-certs "$OUT/ny-la.apk" | head -10

# Final summary
ls -la "$OUT/ny-la.apk"
echo
echo "DONE: $OUT/ny-la.apk"
