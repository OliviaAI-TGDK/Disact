# Disact.sh

**Disact.sh** is the SteelOx diagnostic resolver for accumulated Android project faults. It is designed to inspect, report, back up, normalize, and safely amend the project surface so UI, WebView, asset, XML, manifest, and scripting faults can be resolved with full diagnostic coverage.

Disact.sh does not blindly overwrite the project. It creates timestamped reports and backups first, then applies compatible resolver patches where safe.

---

## Purpose

Disact.sh provides a single diagnostic resolver pass for the SteelOx Android project.

It covers:

- Java source files
- Kotlin source files
- Android XML layouts
- AndroidManifest.xml
- HTML assets
- JavaScript assets
- CSS assets
- WebView bootstrap compatibility
- device requirement gates
- duplicate IDs
- manifest permission and feature checks
- scripting collisions
- traceback discovery
- merge conflict discovery
- accumulated source snapshots
- version-safe backup output

The tool is intended to help identify and resolve faults that prevent the SteelOx UI from working correctly or degrade the UX.

---

## Canonical Script Name

The generated resolver script is:

```bash
steelox_accumulated_diagnostic_resolver.sh
```

The operational tool name is:

```bash
Disact.sh
```

You may install it as `Disact.sh` for direct use.

---

## What Disact.sh Does

Disact.sh performs a full accumulated diagnostic pass over:

```text
~/SteelOx/app/src/main
```

It scans and processes:

```text
*.java
*.kt
*.xml
*.html
*.htm
*.js
*.css
```

It then generates:

```text
/sdcard/Download/steelox/accumulated-diagnostic-resolution-YYYYMMDD-HHMMSS/
```

and backups under:

```text
~/SteelOx/.steelox_backups/accumulated-diagnostic-resolution-YYYYMMDD-HHMMSS/
```

---

## Core Coverage

### 1. Project File Discovery

Disact.sh finds all supported Android project files and writes the complete file list to:

```text
all-project-files.txt
```

This allows the resolver to operate from a known project inventory instead of guessing.

---

### 2. Cat-Based Source Snapshotting

Every discovered file is copied into a timestamped diagnostic snapshot using `cat`.

Each snapshot is written as:

```text
cat-<safe-file-name>.txt
```

This gives you a complete readable capture of project state before resolver logic is applied.

---

### 3. Grep-Based Fault Detection

Disact.sh uses `grep` to locate important project signals, including:

- `MainActivity`
- `WebView`
- `loadUrl`
- `loadData`
- `evaluateJavascript`
- `addJavascriptInterface`
- `onCreate`
- `setContentView`
- asset usage
- script references
- stylesheet references
- SteelOx/Joy/Olivia markers

Output:

```text
grep-scripting-mainactivity.txt
```

It also detects collision and traceback markers:

- merge conflict markers
- TODO
- FIXME
- Traceback
- Exception
- Error
- FATAL
- crash
- NullPointerException
- ClassNotFoundException
- unresolved references
- cannot find symbol

Output:

```text
grep-collisions-tracebacks.txt
```

Device requirement and XML manifest data are also scanned:

```text
grep-device-requirements-xml.txt
grep-layout-ids.txt
```

---

### 4. Sed-Based Safe Normalization

Disact.sh uses `sed` only for low-risk normalization:

- trims trailing whitespace
- normalizes duplicate spacing in `<script>` tags
- normalizes duplicate spacing in `<link>` tags

It does **not** silently delete merge-conflicted content.

If conflict markers are found, it reports them here:

```text
files-with-merge-conflicts.txt
```

---

### 5. Python Accumulated Resolver

The embedded Python resolver performs deeper compatibility work.

It detects:

- MainActivity candidates
- unmatched JavaScript files
- unmatched CSS files
- HTML asset include gaps
- duplicate XML IDs
- duplicate manifest names
- device feature gates
- manifest compatibility gaps
- WebView bootstrap gaps

It then creates accumulated compatibility assets:

```text
app/src/main/assets/steelox_accumulated_bootstrap.js
app/src/main/assets/steelox_accumulated_styles.css
```

These files safely gather unmatched JS and CSS into compatible loader files.

---

## WebView Compatibility

If a `MainActivity` candidate is found, Disact.sh attempts to add a safe WebView bootstrap helper.

The helper enables:

- JavaScript
- DOM storage
- database storage
- file access
- content access
- media playback without gesture requirement

It then injects the accumulated bootstrap and stylesheet into the WebView after load.

This helps repair cases where HTML, JS, or CSS exists in the project but is not properly loaded by the app UI.

---

## HTML Compatibility

Each HTML or HTM file is amended once with:

```html
<link rel="stylesheet" href="steelox_accumulated_styles.css">
<script src="steelox_accumulated_bootstrap.js"></script>
```

Disact.sh deduplicates these resolver includes so repeated runs do not keep appending duplicate tags.

---

## Manifest Compatibility

Disact.sh safely improves the Android manifest by adding basic network capability when absent:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

It also normalizes hardware feature declarations to avoid unnecessary device lockout:

```xml
android:required="false"
```

Common optional hardware features include:

- camera
- autofocus
- Bluetooth
- Bluetooth LE
- NFC
- telephony
- location
- GPS
- microphone
- touchscreen

Disact.sh does **not** add sensitive runtime permissions such as camera, microphone, or location permissions unless already present. It only makes hardware features optional so the app is not blocked on devices that lack them.

---

## Reports Produced

A full run creates a timestamped report folder containing diagnostic files such as:

```text
all-project-files.txt
cat-*.txt
grep-scripting-mainactivity.txt
grep-collisions-tracebacks.txt
grep-device-requirements-xml.txt
grep-layout-ids.txt
files-with-merge-conflicts.txt
```

The Python resolver also emits structured diagnostics for patched files, warnings, unmatched assets, duplicates, and collisions.

---

## Backups

Before modifying supported files, Disact.sh writes backups to:

```text
~/SteelOx/.steelox_backups/accumulated-diagnostic-resolution-YYYYMMDD-HHMMSS/
```

Backups are timestamped and safe-named so modified files can be restored manually.

---

## Installation

From inside Termux:

```bash
cd "$HOME/SteelOx" || exit 1

cp steelox_accumulated_diagnostic_resolver.sh Disact.sh
chmod +x Disact.sh
```

Optional global install:

```bash
mkdir -p "$PREFIX/bin"

cp Disact.sh "$PREFIX/bin/Disact.sh"
chmod +x "$PREFIX/bin/Disact.sh"
```

Then run:

```bash
Disact.sh
```

---

## Direct Run

From the SteelOx project root:

```bash
cd "$HOME/SteelOx" || exit 1
bash ./steelox_accumulated_diagnostic_resolver.sh
```

Or, after installing as Disact.sh:

```bash
cd "$HOME/SteelOx" || exit 1
./Disact.sh
```

---

## Recommended Build Pass

After running Disact.sh, build the APK again:

```bash
cd "$HOME/SteelOx" || exit 1
./gradlew clean :app:assembleDebug
```

Copy the debug APK with versioned output:

```bash
mkdir -p /sdcard/Download/steelox

STAMP="$(date +%Y%m%d-%H%M%S)"
cp -f app/build/outputs/apk/debug/app-debug.apk \
  "/sdcard/Download/steelox/SteelOx-disact-debug-$STAMP.apk"
```

---

## Recommended Full Diagnostic Cycle

```bash
cd "$HOME/SteelOx" || exit 1

bash ./Disact.sh

./gradlew clean :app:assembleDebug

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p /sdcard/Download/steelox

cp -f app/build/outputs/apk/debug/app-debug.apk \
  "/sdcard/Download/steelox/SteelOx-disact-debug-$STAMP.apk"

ls -lh /sdcard/Download/steelox/SteelOx-disact-debug-$STAMP.apk
```

---

## Safety Policy

Disact.sh follows a resolver-first policy:

1. Report before patching.
2. Back up before modifying.
3. Amend instead of overwrite.
4. Preserve conflicted files for human review.
5. Avoid adding sensitive runtime permissions.
6. Deduplicate generated includes.
7. Keep resolver assets isolated.
8. Write output to timestamped folders.
9. Keep source snapshots readable with `cat`.
10. Keep grep diagnostics available for manual trace review.

---

## When To Use

Use Disact.sh when SteelOx has:

- UI glitches
- WebView loading faults
- missing JS or CSS behavior
- broken HTML asset loading
- duplicate XML IDs
- manifest compatibility issues
- unexplained Android device requirement blocks
- unresolved tracebacks
- merge conflict leftovers
- Gradle build failures caused by source/layout collisions
- UX regressions caused by asset mismatch

---

## When Not To Use

Do not rely on Disact.sh as the only fix when:

- Java/Kotlin syntax is deeply broken
- Gradle files are malformed
- dependencies are missing
- package names are inconsistent
- merge conflicts require semantic choices
- Android permissions need legal/privacy review
- app logic must be manually redesigned

Disact.sh is a diagnostic resolver, not a replacement for final code review.

---

## Output Contract

A successful Disact.sh pass should leave the project with:

- timestamped diagnostics
- timestamped backups
- accumulated CSS compatibility file
- accumulated JS compatibility file
- amended HTML asset references
- safer manifest hardware requirements
- WebView bootstrap compatibility where possible
- duplicate/collision reports for follow-up repair

---

## SteelOx Diagnostic Resolver Principle

Disact.sh is built around accumulated resolution:

```text
cat     captures the project state
grep    finds the fault surfaces
sed     normalizes low-risk formatting
python  resolves compatible structural gaps
gradle  confirms build viability
```

The result is a full-coverage diagnostic resolver pass that can be repeated safely during SteelOx development.
