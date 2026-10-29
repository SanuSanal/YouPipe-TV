package com.youpipe.tv

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android's own focus highlight draws a frame round the whole app once a remote key is pressed. Flutter draws
        // its own focus, so turn Android's off (as in YouPipe).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            findViewById<View>(FLUTTER_VIEW_ID)?.defaultFocusHighlightEnabled = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        Googlevideo.attach(this)
        StreamExtractorChannel.register(messenger)
        PlaybackProxy.register(messenger)
        // `youpipe/system`: the screen stays on while a video plays; `exit` leaves the app from the exit dialog.
        MethodChannel(messenger, "youpipe/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "playing" -> {
                    if (call.argument<Boolean>("playing") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }

                "exit" -> {
                    finishAndRemoveTask()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        // `youpipe/account`: `signIn` opens Google's page (SignInActivity) and answers with the session cookie, or
        // null when cancelled; `clear` forgets the WebView's cookies on sign-out.
        MethodChannel(messenger, "youpipe/account").setMethodCallHandler { call, result ->
            when (call.method) {
                "signIn" -> {
                    signInResult?.success(null)
                    signInResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent(this, SignInActivity::class.java), SIGN_IN)
                }

                "clear" -> CookieManager.getInstance().removeAllCookies { removed ->
                    CookieManager.getInstance().flush()
                    result.success(removed)
                }

                else -> result.notImplemented()
            }
        }
    }

    private var signInResult: MethodChannel.Result? = null

    @Deprecated("Activity.onActivityResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SIGN_IN) return
        signInResult?.success(if (resultCode == RESULT_OK) data?.getStringExtra(SignInActivity.EXTRA_COOKIE) else null)
        signInResult = null
    }

    companion object {
        private const val SIGN_IN = 7001
    }
}
