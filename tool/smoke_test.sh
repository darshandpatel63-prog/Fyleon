#!/usr/bin/env bash
# Runs INSIDE the Android emulator step of .github/workflows/smoke-test.yml.
# Installs the release APK, launches it, and saves logcat + screenshots.
set -u
OUT=smoke-output
mkdir -p "$OUT"
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=com.fyleon.app

adb install -r "$APK" 2>&1 | tee "$OUT/install.txt"
adb logcat -c
adb shell getprop ro.build.version.release | tee "$OUT/android-version.txt"

adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 2>&1 | tee "$OUT/launch.txt"
sleep 8
adb exec-out screencap -p > "$OUT/screen-after-8s.png"
PID8=$(adb shell pidof "$PKG" | tr -d '\r')
sleep 17
adb exec-out screencap -p > "$OUT/screen-after-25s.png"
PID25=$(adb shell pidof "$PKG" | tr -d '\r')

adb logcat -d -v threadtime > "$OUT/logcat-full.txt"
adb logcat -d -b crash -v threadtime > "$OUT/logcat-crash.txt" 2>/dev/null
adb shell dumpsys activity activities 2>/dev/null | grep -iE "mResumedActivity|topResumedActivity" > "$OUT/foreground.txt"

{
  echo "pid after 8s : '${PID8}'"
  echo "pid after 25s: '${PID25}'"
  if [ -z "$PID25" ]; then echo "RESULT: APP IS NOT RUNNING (it crashed or exited)"; else echo "RESULT: app is running"; fi
} | tee "$OUT/result.txt"

grep -E "FATAL EXCEPTION|AndroidRuntime|Fatal signal|SIGSEGV|SIGABRT|UnsatisfiedLinkError|NoClassDefFoundError|ClassNotFoundException|NoSuchMethodError|IllegalStateException|Process ${PKG}.*(died|crash)|E flutter|F flutter|F DEBUG" \
  "$OUT/logcat-full.txt" | head -120 > "$OUT/summary.txt"
echo "==== crash summary ===="
cat "$OUT/summary.txt"
echo "==== crash buffer ===="
head -80 "$OUT/logcat-crash.txt"
exit 0
