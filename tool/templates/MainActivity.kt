package com.fyleon.app

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.FileProvider
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// Copied over the generated MainActivity by tool/patch_android.py.
// - receives files from "Open with", "Share" and "Send to" (VIEW / SEND / SEND_MULTIPLE)
// - tells Flutter how much storage is free
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val ready = ArrayList<String>()

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
                "installApk" -> {
                    try {
                        val path = call.argument<String>("path")
                        val file = File(path!!)
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            val i = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + packageName))
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success("need_permission")
                        } else {
                            val uri = FileProvider.getUriForFile(this, packageName + ".fileprovider", file)
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
                "openPlayProtect" -> {
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
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

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
