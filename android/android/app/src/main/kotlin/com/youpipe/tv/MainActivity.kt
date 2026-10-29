package com.youpipe.tv

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowManager
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
    }
}
