package com.fyleon.app

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.app.usage.UsageStatsManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Process
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

// Copied over the generated MainActivity by tool/patch_android.py.
// - receives files from "Open with", "Share" and "Send to" (VIEW / SEND / SEND_MULTIPLE)
// - free storage, share / open-with, APK install
// - installed apps list, app sizes + cache sizes (needs "Usage access"), app info / uninstall
// - "clear all apps' cache" system dialog, hotspot / Wi-Fi settings, multicast lock (Dash)
// AudioServiceActivity = FlutterActivity + the engine needed for background audio (just_audio_background).
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private val ready = ArrayList<String>()
    private val pool = Executors.newFixedThreadPool(2)
    private var clearCacheResult: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private val reqClearCache = 4711

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fyleon/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeFiles" -> {
                    synchronized(ready) {
                        val copy = ArrayList(ready)
                        ready.clear()
                        result.success(copy)
                    }
                }
                "storageInfo" -> {
                    try {
                        val path = call.argument<String>("path")
                        val st = StatFs(path)
                        result.success(mapOf("total" to st.totalBytes, "free" to st.availableBytes))
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "installApk" -> installApk(call.argument<String>("path"), result)
                "openPlayProtect" -> openPlayProtect(result)
                "shareFiles" -> shareFiles(call.argument<List<String>>("paths") ?: emptyList(), result)
                "openWith" -> openWith(call.argument<String>("path"), result)
                "deviceName" -> result.success(deviceName())
                // ---- apps ----
                "listApps" -> listApps(call.argument<Boolean>("includeSystem") ?: true, result)
                "appIcon" -> appIcon(call.argument<String>("pkg"), call.argument<Int>("size") ?: 96, result)
                "appStats" -> appStats(call.argument<List<String>>("pkgs"), result)
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "openUsageAccess" -> {
                    try {
                        val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openAppInfo" -> {
                    try {
                        val pkg = call.argument<String>("pkg")
                        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "uninstallApp" -> {
                    try {
                        val pkg = call.argument<String>("pkg")
                        val i = Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "launchApp" -> {
                    try {
                        val pkg = call.argument<String>("pkg") ?: ""
                        val i = packageManager.getLaunchIntentForPackage(pkg)
                        if (i == null) {
                            result.success(false)
                        } else {
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "extractApk" -> extractApk(call.argument<String>("pkg"), result)
                "clearAllCache" -> clearAllCache(result)
                // ---- Dash (file sharing) helpers ----
                "openHotspotSettings" -> openHotspotSettings(result)
                "openWifiSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_WIFI_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "multicastLock" -> {
                    try {
                        setMulticastLock(call.argument<Boolean>("on") ?: false)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onDestroy() {
        try {
            setMulticastLock(false)
        } catch (e: Exception) {
        }
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqClearCache) {
            val r = clearCacheResult
            clearCacheResult = null
            r?.success(if (resultCode == Activity.RESULT_OK) "cleared" else "cancelled")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    // ------------------------------------------------------------------ install / share / open

    private fun installApk(path: String?, result: MethodChannel.Result) {
        try {
            val file = File(path!!)
            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                result.success("need_permission")
            } else {
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                val i = Intent(Intent.ACTION_VIEW)
                i.setDataAndType(uri, "application/vnd.android.package-archive")
                i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                result.success("started")
            }
        } catch (e: Exception) {
            result.success("error: " + e.message)
        }
    }

    private fun openPlayProtect(result: MethodChannel.Result) {
        try {
            val i = Intent()
            i.setClassName("com.google.android.gms", "com.google.android.gms.security.settings.VerifyAppsSettingsActivity")
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            result.success(true)
        } catch (e: Exception) {
            try {
                val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.android.vending"))
                market.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(market)
                result.success(true)
            } catch (e2: Exception) {
                result.success(false)
            }
        }
    }

    private fun mimeOf(path: String): String {
        val ext = MimeTypeMap.getFileExtensionFromUrl(Uri.fromFile(File(path)).toString())
        val m = if (ext.isNullOrEmpty()) null else MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase())
        return m ?: "*/*"
    }

    private fun shareFiles(paths: List<String>, result: MethodChannel.Result) {
        try {
            if (paths.isEmpty()) {
                result.success(false)
                return
            }
            val uris = ArrayList<Uri>()
            for (p in paths) uris.add(FileProvider.getUriForFile(this, "$packageName.fileprovider", File(p)))
            val intent: Intent
            if (uris.size == 1) {
                intent = Intent(Intent.ACTION_SEND)
                intent.type = mimeOf(paths[0])
                intent.putExtra(Intent.EXTRA_STREAM, uris[0])
            } else {
                intent = Intent(Intent.ACTION_SEND_MULTIPLE)
                intent.type = "*/*"
                intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            }
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(intent, null))
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun openWith(path: String?, result: MethodChannel.Result) {
        try {
            val file = File(path!!)
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val i = Intent(Intent.ACTION_VIEW)
            i.setDataAndType(uri, mimeOf(path))
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(Intent.createChooser(i, null))
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun deviceName(): String {
        try {
            val n = Settings.Global.getString(contentResolver, "device_name")
            if (!n.isNullOrBlank()) return n
        } catch (e: Exception) {
        }
        return Build.MODEL ?: "Android"
    }

    // ------------------------------------------------------------------ apps

    @Suppress("DEPRECATION")
    private fun listApps(includeSystem: Boolean, result: MethodChannel.Result) {
        pool.execute {
            val out = ArrayList<Map<String, Any?>>()
            try {
                val pm = packageManager
                for (ai in pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                    val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
                    if (isSystem && !includeSystem) continue
                    var installed = 0L
                    var updated = 0L
                    var version = ""
                    try {
                        val pi = pm.getPackageInfo(ai.packageName, 0)
                        installed = pi.firstInstallTime
                        updated = pi.lastUpdateTime
                        version = pi.versionName ?: ""
                    } catch (e: Exception) {
                    }
                    var apkSize = 0L
                    try {
                        apkSize += File(ai.sourceDir).length()
                        val splits = ai.splitSourceDirs
                        if (splits != null) for (s in splits) apkSize += File(s).length()
                    } catch (e: Exception) {
                    }
                    val game = (Build.VERSION.SDK_INT >= 26 && ai.category == ApplicationInfo.CATEGORY_GAME) ||
                        (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0
                    out.add(
                        mapOf(
                            "pkg" to ai.packageName,
                            "label" to (pm.getApplicationLabel(ai)?.toString() ?: ai.packageName),
                            "system" to isSystem,
                            "game" to game,
                            "apkSize" to apkSize,
                            "installed" to installed,
                            "updated" to updated,
                            "version" to version,
                            "launchable" to (pm.getLaunchIntentForPackage(ai.packageName) != null),
                            "enabled" to ai.enabled,
                        )
                    )
                }
            } catch (e: Exception) {
            }
            runOnUiThread { result.success(out) }
        }
    }

    private fun drawableToPng(d: Drawable, size: Int): ByteArray {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    private fun appIcon(pkg: String?, size: Int, result: MethodChannel.Result) {
        pool.execute {
            var bytes: ByteArray? = null
            try {
                val d = packageManager.getApplicationIcon(pkg!!)
                bytes = drawableToPng(d, size.coerceIn(32, 192))
            } catch (e: Throwable) {
            }
            runOnUiThread { result.success(bytes) }
        }
    }

    @Suppress("DEPRECATION")
    private fun hasUsageAccess(): Boolean {
        return try {
            val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            } else {
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /** pkg -> {app, data, cache, last}. Empty when "Usage access" is not allowed. */
    @Suppress("DEPRECATION")
    private fun appStats(only: List<String>?, result: MethodChannel.Result) {
        pool.execute {
            val out = HashMap<String, Map<String, Long>>()
            try {
                if (hasUsageAccess() && Build.VERSION.SDK_INT >= 26) {
                    val ssm = getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
                    val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                    val now = System.currentTimeMillis()
                    val usage = try {
                        usm.queryAndAggregateUsageStats(now - 365L * 24 * 3600 * 1000, now)
                    } catch (e: Exception) {
                        null
                    }
                    for (ai in packageManager.getInstalledApplications(0)) {
                        if (only != null && !only.contains(ai.packageName)) continue
                        try {
                            val st = ssm.queryStatsForPackage(StorageManager.UUID_DEFAULT, ai.packageName, Process.myUserHandle())
                            val last = usage?.get(ai.packageName)?.lastTimeUsed ?: 0L
                            out[ai.packageName] = mapOf(
                                "app" to st.appBytes,
                                "data" to st.dataBytes,
                                "cache" to st.cacheBytes,
                                "last" to last,
                            )
                        } catch (e: Exception) {
                        }
                    }
                }
            } catch (e: Exception) {
            }
            runOnUiThread { result.success(out) }
        }
    }

    private fun extractApk(pkg: String?, result: MethodChannel.Result) {
        pool.execute {
            var path: String? = null
            try {
                val ai = packageManager.getApplicationInfo(pkg!!, 0)
                val dir = File(cacheDir, "apk_backup")
                dir.mkdirs()
                val out = File(dir, "$pkg.apk")
                File(ai.sourceDir).inputStream().use { i -> FileOutputStream(out).use { o -> i.copyTo(o) } }
                path = out.absolutePath
            } catch (e: Exception) {
            }
            runOnUiThread { result.success(path) }
        }
    }

    @Suppress("DEPRECATION")
    private fun clearAllCache(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 30) {
            result.success("unsupported")
            return
        }
        try {
            clearCacheResult = result
            startActivityForResult(Intent(StorageManager.ACTION_CLEAR_APP_CACHE), reqClearCache)
        } catch (e: Exception) {
            clearCacheResult = null
            result.success("error: " + e.message)
        }
    }

    // ------------------------------------------------------------------ Dash helpers

    private fun openHotspotSettings(result: MethodChannel.Result) {
        try {
            val i = Intent()
            i.setClassName("com.android.settings", "com.android.settings.TetherSettings")
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(i)
            result.success(true)
        } catch (e: Exception) {
            try {
                val i = Intent(Settings.ACTION_WIRELESS_SETTINGS)
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(i)
                result.success(true)
            } catch (e2: Exception) {
                result.success(false)
            }
        }
    }

    private fun setMulticastLock(on: Boolean) {
        if (on) {
            if (multicastLock == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val l = wifi.createMulticastLock("fyleon-dash")
                l.setReferenceCounted(false)
                multicastLock = l
            }
            multicastLock?.acquire()
        } else {
            val l = multicastLock
            if (l != null && l.isHeld) l.release()
        }
    }

    // ------------------------------------------------------------------ incoming files

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val uris = ArrayList<Uri>()
        val data = intent.data
        if (data != null) uris.add(data)
        val clip = intent.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                val u = clip.getItemAt(i).uri
                if (u != null) uris.add(u)
            }
        }
        if (uris.isEmpty()) return

        // handled once (a screen rotation must not import the file again)
        intent.action = null

        Thread {
            for (uri in uris.distinct()) {
                val path = copyToCache(uri)
                if (path != null) {
                    synchronized(ready) { ready.add(path) }
                }
            }
            runOnUiThread { channel?.invokeMethod("filesReady", null) }
        }.start()
    }

    private fun copyToCache(uri: Uri): String? {
        try {
            if (uri.scheme == "file") {
                val p = uri.path ?: return null
                val f = File(p)
                return if (f.exists()) f.absolutePath else null
            }
            var name: String? = null
            if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
                val cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                if (cursor != null) {
                    cursor.use { c ->
                        if (c.moveToFirst()) {
                            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) name = c.getString(idx)
                        }
                    }
                }
            }
            val rawName = name ?: uri.lastPathSegment ?: "file"
            val safeName = rawName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val dir = File(cacheDir, "incoming/" + System.currentTimeMillis())
            dir.mkdirs()
            val out = File(dir, safeName)
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { i ->
                FileOutputStream(out).use { o -> i.copyTo(o) }
            }
            return out.absolutePath
        } catch (e: Exception) {
            return null
        }
    }
}
