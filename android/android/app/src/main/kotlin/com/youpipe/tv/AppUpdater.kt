package com.youpipe.tv

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Installs a downloaded update through Android's PackageInstaller (docs/release.md). Android shows its own
 * confirmation, and the first time asks to let YouPipe install apps. The answer is null once Android takes over (the
 * app is then replaced), `cancelled` when the user declines, `signature` when the APK is signed with another key, or
 * Android's message.
 */
class AppUpdater(private val activity: Activity) {
    private var pending: MethodChannel.Result? = null
    private var receiver: BroadcastReceiver? = null

    fun install(path: String, result: MethodChannel.Result) {
        pending?.success("cancelled")
        pending = result
        Thread {
            try {
                val installer = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    val file = File(path)
                    file.inputStream().use { input ->
                        session.openWrite("youpipe.apk", 0, file.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    activity.runOnUiThread { listen() }
                    val intent = Intent(ACTION).setPackage(activity.packageName)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    session.commit(PendingIntent.getBroadcast(activity, sessionId, intent, flags).intentSender)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { finish(e.message ?: e.toString()) }
            }
        }.start()
    }

    private fun listen() {
        if (receiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                    // Android's confirmation (and its "install unknown apps" switch) comes up; the status follows.
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        @Suppress("DEPRECATION")
                        val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                        } else {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT)
                        }
                        if (confirm != null) activity.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }

                    PackageInstaller.STATUS_SUCCESS -> finish(null)
                    PackageInstaller.STATUS_FAILURE_ABORTED -> finish("cancelled")
                    PackageInstaller.STATUS_FAILURE_CONFLICT, PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> finish("signature")
                    else -> finish(intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status")
                }
            }
        }
        val filter = IntentFilter(ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(r, filter)
        }
        receiver = r
    }

    private fun finish(answer: String?) {
        receiver?.let { activity.unregisterReceiver(it) }
        receiver = null
        pending?.success(answer)
        pending = null
    }

    companion object {
        private const val ACTION = "com.youpipe.tv.UPDATE_STATUS"
    }
}
