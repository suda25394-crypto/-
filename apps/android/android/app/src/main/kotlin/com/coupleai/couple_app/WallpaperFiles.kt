package com.coupleai.couple_app

import android.app.Activity
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executor

/** Device-only files. Account and service names are never used as filesystem paths. */
internal object WallpaperFiles {
    fun register(activity: Activity, messenger: BinaryMessenger, io: Executor) {
        MethodChannel(messenger, "couple/personal_wallpaper").setMethodCallHandler { call, result ->
            if (call.method !in setOf("read", "write", "clear")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val scope = call.argument<String>("scope")
            if (scope.isNullOrEmpty()) {
                result.error("scope", "请先登录自己的账号", null)
                return@setMethodCallHandler
            }
            io.execute {
                try {
                    val digest = MessageDigest.getInstance("SHA-256").digest(scope.toByteArray(Charsets.UTF_8))
                    val name = digest.joinToString("") { "%02x".format(it) }
                    val file = AtomicFile(File(activity.noBackupFilesDir, "background-$name"))
                    val answer: ByteArray? = when (call.method) {
                        "read" -> try { file.openRead().use { it.readBytes() } } catch (_: java.io.FileNotFoundException) { null }
                        "clear" -> { file.delete(); null }
                        else -> {
                            val data = requireNotNull(call.argument<ByteArray>("data"))
                            require(data.isNotEmpty() && data.size <= 10 * 1024 * 1024)
                            val out = file.startWrite()
                            try {
                                out.write(data)
                                file.finishWrite(out)
                            } catch (e: Exception) {
                                file.failWrite(out)
                                throw e
                            }
                            null
                        }
                    }
                    activity.runOnUiThread { result.success(answer) }
                } catch (_: Exception) {
                    activity.runOnUiThread { result.error("wallpaper", "无法读写设备中的背景照片", null) }
                }
            }
        }
    }
}
