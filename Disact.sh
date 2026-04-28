cat > steelox_accumulated_diagnostic_resolver.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -u

cd "$HOME/SteelOx" || exit 1

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="/sdcard/Download/steelox"
REPORT_DIR="$OUT_DIR/accumulated-diagnostic-resolution-$STAMP"
BACKUP_DIR="$HOME/SteelOx/.steelox_backups/accumulated-diagnostic-resolution-$STAMP"

mkdir -p "$OUT_DIR" "$REPORT_DIR" "$BACKUP_DIR"

APP_DIR="app/src/main"
ASSET_DIR="$APP_DIR/assets"
JAVA_DIR="$APP_DIR/java"
KOTLIN_DIR="$APP_DIR/kotlin"
RES_DIR="$APP_DIR/res"
MANIFEST="$APP_DIR/AndroidManifest.xml"

mkdir -p "$ASSET_DIR"

echo "=== SteelOx Accumulated Diagnostic Resolution ==="
echo "Stamp: $STAMP"
echo "Report: $REPORT_DIR"
echo "Backup: $BACKUP_DIR"
echo

echo "=== 1. Find project files ==="
find "$APP_DIR" -type f \
  \( -name '*.java' -o -name '*.kt' -o -name '*.xml' -o -name '*.html' -o -name '*.htm' -o -name '*.js' -o -name '*.css' \) \
  | sort > "$REPORT_DIR/all-project-files.txt"

cat "$REPORT_DIR/all-project-files.txt"

echo
echo "=== 2. Cat accumulated source snapshots ==="
while IFS= read -r FILE; do
  [ -z "$FILE" ] && continue
  SAFE="$(echo "$FILE" | tr '/ ' '__')"
  {
    echo "============================================================"
    echo "FILE: $FILE"
    echo "STAMP: $STAMP"
    echo "============================================================"
    cat "$FILE"
  } > "$REPORT_DIR/cat-$SAFE.txt"
done < "$REPORT_DIR/all-project-files.txt"

echo
echo "=== 3. Grep diagnostics: scripting, duplicates, collisions, tracebacks ==="

grep -RIn \
  -E 'MainActivity|WebView|loadUrl|loadData|evaluateJavascript|addJavascriptInterface|onCreate|setContentView|assets|\.js|\.css|script|stylesheet|steelox|olivia|joy' \
  "$APP_DIR" 2>/dev/null \
  | tee "$REPORT_DIR/grep-scripting-mainactivity.txt" || true

grep -RIn \
  -E '<<<<<<<|=======|>>>>>>>|TODO|FIXME|Traceback|Exception|Error:|FATAL|crash|NullPointerException|ClassNotFoundException|Unresolved reference|cannot find symbol' \
  . 2>/dev/null \
  | tee "$REPORT_DIR/grep-collisions-tracebacks.txt" || true

grep -RIn \
  -E 'android.permission|uses-feature|uses-sdk|supports-screens|queries|provider|activity|service|receiver|exported|hardware|camera|bluetooth|nfc|telephony|location|microphone' \
  "$APP_DIR" 2>/dev/null \
  | tee "$REPORT_DIR/grep-device-requirements-xml.txt" || true

grep -RIn \
  -E 'android:id="@\+id/|@id/|id="' \
  "$RES_DIR" 2>/dev/null \
  | tee "$REPORT_DIR/grep-layout-ids.txt" || true

echo
echo "=== 4. Sed quick normalizations before Python resolver ==="

# Keep backups before sed changes.
find "$APP_DIR" -type f \( -name '*.xml' -o -name '*.html' -o -name '*.htm' -o -name '*.js' -o -name '*.css' \) \
  | while IFS= read -r FILE; do
      SAFE="$(echo "$FILE" | tr '/ ' '__')"
      cp -f "$FILE" "$BACKUP_DIR/$SAFE.bak"
    done

# Remove obvious merge conflict markers into report but do not silently delete conflicted content.
grep -RIl -E '<<<<<<<|=======|>>>>>>>' "$APP_DIR" 2>/dev/null > "$REPORT_DIR/files-with-merge-conflicts.txt" || true

if [ -s "$REPORT_DIR/files-with-merge-conflicts.txt" ]; then
  echo "WARNING: Merge conflict markers found. Listed in:"
  echo "$REPORT_DIR/files-with-merge-conflicts.txt"
fi

# Normalize accidental duplicate asset include whitespace only.
find "$ASSET_DIR" -type f \( -name '*.html' -o -name '*.htm' \) 2>/dev/null \
  | while IFS= read -r HTML; do
      sed -i \
        -e 's/[[:space:]]\+$//' \
        -e 's/<script[[:space:]][[:space:]]*/<script /g' \
        -e 's/<link[[:space:]][[:space:]]*/<link /g' \
        "$HTML"
    done

echo
echo "=== 5. Python accumulated resolver ==="
python3 <<'PY'
from pathlib import Path
import re
import json
import shutil
from collections import Counter, defaultdict

stamp = "$STAMP"
app = Path("app/src/main")
assets = app / "assets"
res = app / "res"
manifest = app / "AndroidManifest.xml"
report = Path("$REPORT_DIR")
backup = Path("$BACKUP_DIR")

assets.mkdir(parents=True, exist_ok=True)

def read(p):
    return p.read_text(errors="ignore")

def write(p, s):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s)

def backup_file(p, suffix="pybak"):
    if not p.exists():
        return
    safe = str(p).replace("/", "__").replace(" ", "_")
    dst = backup / f"{safe}.{suffix}"
    if not dst.exists():
        shutil.copy2(p, dst)

def unique_keep_order(items):
    seen = set()
    out = []
    for x in items:
        if x not in seen:
            out.append(x)
            seen.add(x)
    return out

all_files = [p for p in app.rglob("*") if p.is_file()]
html_files = [p for p in all_files if p.suffix.lower() in [".html", ".htm"]]
js_files = [p for p in all_files if p.suffix.lower() == ".js" and "build" not in p.parts]
css_files = [p for p in all_files if p.suffix.lower() == ".css" and "build" not in p.parts]
xml_files = [p for p in all_files if p.suffix.lower() == ".xml"]
java_files = [p for p in all_files if p.suffix.lower() == ".java"]
kt_files = [p for p in all_files if p.suffix.lower() == ".kt"]

diag = {
    "html_files": [str(p) for p in html_files],
    "js_files": [str(p) for p in js_files],
    "css_files": [str(p) for p in css_files],
    "xml_files": [str(p) for p in xml_files],
    "mainactivity_candidates": [],
    "unmatched_js": [],
    "unmatched_css": [],
    "duplicates": {},
    "xml_collisions": {},
    "patched": [],
    "warnings": [],
}

# ------------------------------------------------------------
# Locate MainActivity.
# ------------------------------------------------------------
main_candidates = []
for p in java_files + kt_files:
    s = read(p)
    score = 0
    if "class MainActivity" in s:
        score += 100
    if "WebView" in s:
        score += 40
    if "onCreate" in s:
        score += 30
    if "loadUrl" in s or "loadData" in s:
        score += 20
    if "setContentView" in s:
        score += 10
    if score:
        main_candidates.append((score, p))

main_candidates.sort(reverse=True, key=lambda x: x[0])
diag["mainactivity_candidates"] = [{"score": s, "path": str(p)} for s, p in main_candidates]
main_activity = main_candidates[0][1] if main_candidates else None

# ------------------------------------------------------------
# Detect HTML asset includes.
# ------------------------------------------------------------
html_join = "\n".join(read(p) for p in html_files)
referenced_assets = set()

for m in re.finditer(r'''(?:src|href)\s*=\s*["']([^"']+)["']''', html_join, flags=re.I):
    referenced_assets.add(Path(m.group(1)).name)

own_generated = {
    "steelox_accumulated_bootstrap.js",
    "steelox_accumulated_styles.css",
}

for p in js_files:
    if p.name in own_generated:
        continue
    if p.name not in referenced_assets:
        diag["unmatched_js"].append(str(p))

for p in css_files:
    if p.name in own_generated:
        continue
    if p.name not in referenced_assets:
        diag["unmatched_css"].append(str(p))

# ------------------------------------------------------------
# Create accumulated CSS/JS bootstrap from unmatched scripts.
# This does not move source files. It creates a compatible loader.
# ------------------------------------------------------------
acc_css = assets / "steelox_accumulated_styles.css"
acc_js = assets / "steelox_accumulated_bootstrap.js"

css_parts = [
    "/* SteelOx accumulated compatible CSS resolver. Generated safely. */",
    ":root{--steelox-accumulated-ready:1;}",
    ".steelox-accumulated-diagnostic{display:none!important;}",
]
for item in diag["unmatched_css"]:
    p = Path(item)
    css_parts.append(f"\n/* ===== accumulated css: {p} ===== */\n")
    css_parts.append(read(p))

backup_file(acc_css)
write(acc_css, "\n".join(css_parts))
diag["patched"].append(str(acc_css))

js_parts = [
    "/* SteelOx accumulated compatible JS resolver. Generated safely. */",
    "(function SteelOxAccumulatedBootstrap(){",
    '  "use strict";',
    "  window.SteelOxAccumulatedBootstrap = window.SteelOxAccumulatedBootstrap || {};",
    "  const BOOT = window.SteelOxAccumulatedBootstrap;",
    "  BOOT.loadedAt = new Date().toISOString();",
    "  BOOT.sources = BOOT.sources || [];",
    "  BOOT.trace = BOOT.trace || [];",
    "  BOOT.errors = BOOT.errors || [];",
    "  window.addEventListener('error', function(e){ BOOT.errors.push({type:'error', message:e.message, source:e.filename, line:e.lineno, col:e.colno}); });",
    "  window.addEventListener('unhandledrejection', function(e){ BOOT.errors.push({type:'promise', message:String(e.reason)}); });",
    "  function run(name, fn){ try { BOOT.sources.push(name); fn(); } catch(e) { BOOT.errors.push({source:name, message:String(e && e.stack || e)}); } }",
]
for item in diag["unmatched_js"]:
    p = Path(item)
    content = read(p)
    js_parts.append(f"\n  /* ===== accumulated js: {p} ===== */")
    js_parts.append(f"  run({json.dumps(str(p))}, function(){{")
    js_parts.append(content)
    js_parts.append("\n  });")
js_parts.append("})();\n")

backup_file(acc_js)
write(acc_js, "\n".join(js_parts))
diag["patched"].append(str(acc_js))

# ------------------------------------------------------------
# Amend every HTML with accumulated CSS/JS once.
# ------------------------------------------------------------
for p in html_files:
    backup_file(p)
    s = read(p)
    changed = False

    css_tag = '<link rel="stylesheet" href="steelox_accumulated_styles.css">'
    js_tag = '<script src="steelox_accumulated_bootstrap.js"></script>'

    if "steelox_accumulated_styles.css" not in s:
        if "</head>" in s:
            s = s.replace("</head>", f"  {css_tag}\n</head>", 1)
        else:
            s = css_tag + "\n" + s
        changed = True

    if "steelox_accumulated_bootstrap.js" not in s:
        if "</body>" in s:
            s = s.replace("</body>", f"  {js_tag}\n</body>", 1)
        else:
            s = s + "\n" + js_tag + "\n"
        changed = True

    # Deduplicate exact repeated include lines.
    lines = s.splitlines()
    seen_include = set()
    new_lines = []
    for line in lines:
        key = None
        if "steelox_accumulated_styles.css" in line:
            key = "acc-css"
        elif "steelox_accumulated_bootstrap.js" in line:
            key = "acc-js"

        if key:
            if key in seen_include:
                continue
            seen_include.add(key)

        new_lines.append(line)

    s2 = "\n".join(new_lines) + ("\n" if s.endswith("\n") else "")
    if s2 != s:
        s = s2
        changed = True

    if changed:
        write(p, s)
        diag["patched"].append(str(p))

# ------------------------------------------------------------
# Patch MainActivity with safe WebView asset compatibility.
# It adds a method and calls it after loadUrl/loadData when possible.
# ------------------------------------------------------------
if main_activity:
    backup_file(main_activity)
    s = read(main_activity)
    original = s
    suffix = main_activity.suffix.lower()

    if suffix == ".java":
        if "steeloxEnsureAccumulatedBootstrap" not in s:
            method = r'''
    private void steeloxEnsureAccumulatedBootstrap(android.webkit.WebView webView) {
        if (webView == null) return;
        try {
            android.webkit.WebSettings settings = webView.getSettings();
            settings.setJavaScriptEnabled(true);
            settings.setDomStorageEnabled(true);
            settings.setDatabaseEnabled(true);
            settings.setAllowFileAccess(true);
            settings.setAllowContentAccess(true);
            settings.setMediaPlaybackRequiresUserGesture(false);

            webView.postDelayed(new Runnable() {
                @Override public void run() {
                    try {
                        webView.evaluateJavascript(
                            "(function(){"
                            + "if(window.SteelOxAccumulatedBootstrap){return 'already-loaded';}"
                            + "var s=document.createElement('script');"
                            + "s.src='steelox_accumulated_bootstrap.js';"
                            + "document.documentElement.appendChild(s);"
                            + "var c=document.createElement('link');"
                            + "c.rel='stylesheet';"
                            + "c.href='steelox_accumulated_styles.css';"
                            + "document.head&&document.head.appendChild(c);"
                            + "return 'loaded';"
                            + "})();",
                            null
                        );
                    } catch (Throwable ignored) {}
                }
            }, 350L);
        } catch (Throwable ignored) {}
    }
'''
            idx = s.rfind("}")
            if idx != -1:
                s = s[:idx] + method + "\n" + s[idx:]

        # Try to call after common WebView load methods.
        if "steeloxEnsureAccumulatedBootstrap(" in s:
            # Find webview variable names from load calls.
            vars_found = []
            for m in re.finditer(r'([A-Za-z_][A-Za-z0-9_]*)\.load(?:Url|DataWithBaseURL|Data)\s*\(', s):
                vars_found.append(m.group(1))
            vars_found = unique_keep_order(vars_found)

            for v in vars_found:
                call = f"steeloxEnsureAccumulatedBootstrap({v});"
                if call not in s:
                    s = re.sub(
                        rf'({re.escape(v)}\.load(?:Url|DataWithBaseURL|Data)\s*\([^;]+;\s*)',
                        rf'\1\n        {call}\n',
                        s,
                        count=1
                    )

    elif suffix == ".kt":
        if "steeloxEnsureAccumulatedBootstrap" not in s:
            method = r'''
    private fun steeloxEnsureAccumulatedBootstrap(webView: android.webkit.WebView?) {
        if (webView == null) return
        try {
            val settings = webView.settings
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = true
            settings.allowContentAccess = true
            settings.mediaPlaybackRequiresUserGesture = false

            webView.postDelayed({
                try {
                    webView.evaluateJavascript(
                        """
                        (function(){
                          if(window.SteelOxAccumulatedBootstrap){return 'already-loaded';}
                          var s=document.createElement('script');
                          s.src='steelox_accumulated_bootstrap.js';
                          document.documentElement.appendChild(s);
                          var c=document.createElement('link');
                          c.rel='stylesheet';
                          c.href='steelox_accumulated_styles.css';
                          document.head&&document.head.appendChild(c);
                          return 'loaded';
                        })();
                        """.trimIndent(),
                        null
                    )
                } catch (_: Throwable) {}
            }, 350L)
        } catch (_: Throwable) {}
    }
'''
            idx = s.rfind("}")
            if idx != -1:
                s = s[:idx] + method + "\n" + s[idx:]

        vars_found = []
        for m in re.finditer(r'([A-Za-z_][A-Za-z0-9_]*)\.load(?:Url|DataWithBaseURL|Data)\s*\(', s):
            vars_found.append(m.group(1))
        vars_found = unique_keep_order(vars_found)

        for v in vars_found:
            call = f"steeloxEnsureAccumulatedBootstrap({v})"
            if call not in s:
                s = re.sub(
                    rf'({re.escape(v)}\.load(?:Url|DataWithBaseURL|Data)\s*\([^\n]+)',
                    rf'\1\n        {call}',
                    s,
                    count=1
                )

    if s != original:
        write(main_activity, s)
        diag["patched"].append(str(main_activity))
else:
    diag["warnings"].append("No MainActivity candidate found.")

# ------------------------------------------------------------
# AndroidManifest device requirement compatibility.
# Safe policy:
# - Adds INTERNET and ACCESS_NETWORK_STATE if absent.
# - Converts hardware uses-feature to required=false.
# - Adds optional features for common device gates.
# - Does not add sensitive runtime permissions like location/camera/mic.
# ------------------------------------------------------------
if manifest.exists():
    backup_file(manifest)
    s = read(manifest)
    original = s

    if "xmlns:android=" not in s:
        s = s.replace("<manifest", '<manifest xmlns:android="http://schemas.android.com/apk/res/android"', 1)

    def add_permission(text, perm):
        if perm in text:
            return text
        return text.replace("<application", f'    <uses-permission android:name="{perm}" />\n\n    <application', 1)

    s = add_permission(s, "android.permission.INTERNET")
    s = add_permission(s, "android.permission.ACCESS_NETWORK_STATE")

    # Ensure activities with intent-filters have exported explicitly where missing.
    def exported_activity_fix(match):
        block = match.group(0)
        if "<intent-filter" in block and "android:exported=" not in block:
            block = block.replace("<activity", '<activity android:exported="true"', 1)
        return block

    s = re.sub(r'<activity\b[\s\S]*?</activity>', exported_activity_fix, s)

    optional_features = [
        "android.hardware.camera",
        "android.hardware.camera.autofocus",
        "android.hardware.bluetooth",
        "android.hardware.bluetooth_le",
        "android.hardware.nfc",
        "android.hardware.telephony",
        "android.hardware.location",
        "android.hardware.location.gps",
        "android.hardware.microphone",
        "android.hardware.touchscreen",
    ]

    # Convert existing uses-feature to required=false if required is not explicitly set.
    def normalize_feature(match):
        tag = match.group(0)
        if "android:required=" not in tag:
            tag = tag.rstrip("/>") + ' android:required="false" />'
        return tag

    s = re.sub(r'<uses-feature\b[^>]*?/>', normalize_feature, s)

    for feat in optional_features:
        if feat not in s:
            insert = f'    <uses-feature android:name="{feat}" android:required="false" />\n'
            s = s.replace("<application", insert + "\n    <application", 1)

    if "<supports-screens" not in s:
        supports = (
            '    <supports-screens\n'
            '        android:anyDensity="true"\n'
            '        android:smallScreens="true"\n'
            '        android:normalScreens="true"\n'
            '        android:largeScreens="true"\n'
            '        android:xlargeScreens="true" />\n\n'
        )
        s = s.replace("<application", supports + "    <application", 1)

    if s != original:
        write(manifest, s)
        diag["patched"].append(str(manifest))
else:
    diag["warnings"].append("AndroidManifest.xml not found.")

# ------------------------------------------------------------
# XML duplicate/collision diagnostics.
# ------------------------------------------------------------
id_pattern = re.compile(r'android:id\s*=\s*["\']@\+id/([^"\']+)["\']')
name_pattern = re.compile(r'android:name\s*=\s*["\']([^"\']+)["\']')
manifest_perm_pattern = re.compile(r'<uses-permission\b[^>]*android:name\s*=\s*["\']([^"\']+)["\'][^>]*/?>')
feature_pattern = re.compile(r'<uses-feature\b[^>]*android:name\s*=\s*["\']([^"\']+)["\'][^>]*/?>')

id_occ = defaultdict(list)
name_occ = defaultdict(list)

for p in xml_files:
    s = read(p)
    for m in id_pattern.finditer(s):
        id_occ[m.group(1)].append(str(p))
    for m in name_pattern.finditer(s):
        name_occ[m.group(1)].append(str(p))

duplicate_ids = {k: v for k, v in id_occ.items() if len(v) > 1}
duplicate_names = {k: v for k, v in name_occ.items() if len(v) > 1}

diag["xml_collisions"]["duplicate_ids"] = duplicate_ids
diag["xml_collisions"]["duplicate_android_names"] = duplicate_names

if manifest.exists():
    s = read(manifest)
    perms = manifest_perm_pattern.findall(s)
    feats = feature_pattern.findall(s)
    diag["duplicates"]["manifest_permissions"] = {k: v for k, v in Counter(perms).items() if v > 1}
    diag["duplicates"]["manifest_features"] = {k: v for k, v in Counter(feats).items() if v > 1}

    # Deduplicate exact duplicate permission and feature lines safely.
    backup_file(manifest, "dedupebak")
    lines = s.splitlines()
    seen_perm = set()
    seen_feat = set()
    out = []
    removed = []
    for line in lines:
        pm = manifest_perm_pattern.search(line)
        fm = feature_pattern.search(line)

        if pm:
            val = pm.group(1)
            if val in seen_perm:
                removed.append(line)
                continue
            seen_perm.add(val)

        if fm:
            val = fm.group(1)
            if val in seen_feat:
                removed.append(line)
                continue
            seen_feat.add(val)

        out.append(line)

    if removed:
        write(manifest, "\n".join(out) + ("\n" if s.endswith("\n") else ""))
        diag["patched"].append(str(manifest))
        (report / "removed-duplicate-manifest-lines.txt").write_text("\n".join(removed))

# ------------------------------------------------------------
# Build tracebacks and compile-risk scan.
# ------------------------------------------------------------
trace_files = []
for p in Path(".").rglob("*"):
    if not p.is_file():
        continue
    if p.suffix.lower() not in [".log", ".txt", ".out", ".err"]:
        continue
    try:
        txt = read(p)
    except Exception:
        continue
    if re.search(r'Traceback|Exception|FAILURE: Build failed|cannot find symbol|Unresolved reference|NullPointerException|FATAL', txt, re.I):
        trace_files.append(str(p))

diag["traceback_files"] = trace_files

(report / "diagnostic-summary.json").write_text(json.dumps(diag, indent=2))
(report / "patched-files.txt").write_text("\n".join(unique_keep_order(diag["patched"])))
(report / "unmatched-js.txt").write_text("\n".join(diag["unmatched_js"]))
(report / "unmatched-css.txt").write_text("\n".join(diag["unmatched_css"]))
(report / "duplicate-ids.json").write_text(json.dumps(duplicate_ids, indent=2))
(report / "duplicate-android-names.json").write_text(json.dumps(duplicate_names, indent=2))

print("MainActivity:", main_activity)
print("Patched files:")
for p in unique_keep_order(diag["patched"]):
    print("  " + p)
print("Warnings:")
for w in diag["warnings"]:
    print("  " + w)
PY

echo
echo "=== 6. Sed/cat post-patch verification ==="

echo "--- patched files ---"
cat "$REPORT_DIR/patched-files.txt" 2>/dev/null || true

echo
echo "--- unmatched JS accumulated ---"
cat "$REPORT_DIR/unmatched-js.txt" 2>/dev/null || true

echo
echo "--- unmatched CSS accumulated ---"
cat "$REPORT_DIR/unmatched-css.txt" 2>/dev/null || true

echo
echo "=== 7. Grep after patch ==="
grep -RIn \
  -E 'steelox_accumulated_bootstrap|steelox_accumulated_styles|steeloxEnsureAccumulatedBootstrap|INTERNET|ACCESS_NETWORK_STATE|uses-feature|supports-screens|android:exported|Traceback|<<<<<<<|>>>>>>>' \
  "$APP_DIR" 2>/dev/null \
  | tee "$REPORT_DIR/grep-after-accumulated-resolution.txt" || true

echo
echo "=== 8. XML duplicate report ==="
cat "$REPORT_DIR/duplicate-ids.json" 2>/dev/null || true
echo
cat "$REPORT_DIR/duplicate-android-names.json" 2>/dev/null || true

echo
echo "=== 9. Build APK and copy with versioning ==="

BUILD_FILE=""
if [ -f "app/build.gradle" ]; then
  BUILD_FILE="app/build.gradle"
elif [ -f "app/build.gradle.kts" ]; then
  BUILD_FILE="app/build.gradle.kts"
fi

if [ -n "$BUILD_FILE" ]; then
  cp -f "$BUILD_FILE" "$BACKUP_DIR/$(basename "$BUILD_FILE").bak"

  python3 <<PY
from pathlib import Path
import re

p = Path("$BUILD_FILE")
s = p.read_text()
stamp = "$STAMP"

m = re.search(r'versionCode\s*(?:=)?\s*(\d+)', s)
current = int(m.group(1)) if m else 0
next_code = max(current + 1, 1)
next_name = f"1.0.{next_code}-accumulated-diagnostic-{stamp}"

if m:
    s = re.sub(
        r'versionCode\s*(=)?\s*\d+',
        lambda x: f"versionCode {next_code}" if x.group(1) is None else f"versionCode = {next_code}",
        s,
        count=1
    )
else:
    s = re.sub(r'(defaultConfig\s*\{)', r'\1\n        versionCode ' + str(next_code), s, count=1)

if re.search(r'versionName\s*(=)?\s*[\"\'][^\"\']*[\"\']', s):
    s = re.sub(
        r'versionName\s*(=)?\s*[\"\'][^\"\']*[\"\']',
        lambda x: f'versionName "{next_name}"' if x.group(1) is None else f'versionName = "{next_name}"',
        s,
        count=1
    )
else:
    s = re.sub(r'(defaultConfig\s*\{)', r'\1\n        versionName "' + next_name + '"', s, count=1)

p.write_text(s)
print(f"versionCode={next_code}")
print(f"versionName={next_name}")
PY
fi

VARIANT="${BUILD_VARIANT:-debug}"
VARIANT_CAP="$(python3 - <<PY
v="$VARIANT"
print(v[:1].upper() + v[1:])
PY
)"

BUILD_LOG="$OUT_DIR/steelox-accumulated-diagnostic-build-$STAMP.log"

if [ -x "./gradlew" ]; then
  GRADLE="./gradlew"
else
  GRADLE="gradle"
fi

set +e
"$GRADLE" clean ":app:assemble$VARIANT_CAP" 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

echo
echo "=== 10. Extract build tracebacks ==="
grep -nE \
  'FAILURE: Build failed|Traceback|Exception|Error:|cannot find symbol|Unresolved reference|duplicate|Duplicate|Manifest merger failed|AAPT|resource .* not found' \
  "$BUILD_LOG" \
  | tee "$REPORT_DIR/build-tracebacks.txt" || true

APK_DIR="app/build/outputs/apk/$VARIANT"

echo
echo "=== 11. Copy APK outputs ==="
if [ -d "$APK_DIR" ]; then
  VERSION_CODE="$(grep -E 'versionCode' "$BUILD_FILE" 2>/dev/null | head -n 1 | grep -oE '[0-9]+' | head -n 1 || echo 0)"
  VERSION_NAME="$(grep -E 'versionName' "$BUILD_FILE" 2>/dev/null | head -n 1 | sed -E 's/.*versionName[[:space:]]*(=)?[[:space:]]*["'\''"]([^"'\'']+)["'\''"].*/\2/' || echo "unknown")"
  SAFE_VERSION_NAME="$(echo "$VERSION_NAME" | tr -c 'A-Za-z0-9._-' '-')"

  find "$APK_DIR" -type f -name '*.apk' | sort | while IFS= read -r APK; do
    BASE="$(basename "$APK" .apk)"
    DEST="$OUT_DIR/SteelOx-$VARIANT-vc$VERSION_CODE-$SAFE_VERSION_NAME-$STAMP-$BASE.apk"
    cp -f "$APK" "$DEST"
    chmod 644 "$DEST" 2>/dev/null || true
    echo "Copied: $DEST"
    sha256sum "$DEST" > "$DEST.sha256" 2>/dev/null || true
  done
else
  echo "APK directory not found: $APK_DIR"
fi

echo
echo "=== 12. Final manifest ==="
MANIFEST_OUT="$OUT_DIR/steelox-accumulated-diagnostic-resolution-manifest-$STAMP.txt"

cat > "$MANIFEST_OUT" <<EOF
SteelOx Accumulated Diagnostic Resolution
Stamp: $STAMP
Variant: $VARIANT
BuildStatus: $BUILD_STATUS
BackupDir: $BACKUP_DIR
ReportDir: $REPORT_DIR
BuildLog: $BUILD_LOG

Actions:
- cat snapshots of Java/Kotlin/XML/HTML/JS/CSS contenders.
- grep scripting, collisions, duplicates, tracebacks, WebView and XML requirements.
- sed normalized HTML include whitespace.
- found unmatched JS/CSS and accumulated them into:
  app/src/main/assets/steelox_accumulated_bootstrap.js
  app/src/main/assets/steelox_accumulated_styles.css
- amended HTML files with accumulated CSS/JS includes.
- patched MainActivity candidate with steeloxEnsureAccumulatedBootstrap where possible.
- resolved AndroidManifest basic WebView/network compatibility:
  INTERNET
  ACCESS_NETWORK_STATE
  optional hardware features required=false
  supports-screens
  exported=true for intent-filter activities when missing
- found duplicate XML ids and android:name collisions into report JSON.
- extracted build tracebacks into:
  $REPORT_DIR/build-tracebacks.txt

Manual runtime check:
window.SteelOxAccumulatedBootstrap
EOF

echo "Manifest: $MANIFEST_OUT"
echo "Report: $REPORT_DIR"
echo "Backup: $BACKUP_DIR"
echo "Build status: $BUILD_STATUS"

exit "$BUILD_STATUS"
SH

chmod +x steelox_accumulated_diagnostic_resolver.sh
./steelox_accumulated_diagnostic_resolver.sh
