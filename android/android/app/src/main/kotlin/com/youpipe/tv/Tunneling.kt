package com.youpipe.tv

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.util.LongSparseArray
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.videoplayer.VideoPlayer
import io.flutter.plugins.videoplayer.VideoPlayerPlugin

/**
 * Tunneled playback, Settings → Audio sync (docs/streaming.md). The decoder and the TV's audio output then keep
 * sound and picture together in hardware, as YouTube's own app does on Android TV, instead of ExoPlayer timing the
 * frames from the audio delay the TV reports. Some TVs report that delay wrongly, so the sound runs ahead of or behind
 * the picture in every video.
 *
 * `video_player` doesn't expose ExoPlayer's track selector, so it's read from the plugin's fields (kept from R8 in
 * proguard-rules.pro). Checked against video_player_android 2.12.2.
 */
object Tunneling {
    /** Whether a hardware H.264 decoder on this TV can play tunneled. */
    fun supported(): Boolean = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
        !info.isEncoder &&
            info.supportedTypes.any { type ->
                type.equals("video/avc", ignoreCase = true) &&
                    info.getCapabilitiesForType(type)
                        .isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback)
            }
    }

    /**
     * Turns tunneling on or off for the plugin's players (the app has one at a time; the old one is disposed before
     * the next opens). Returns how many were set.
     */
    @OptIn(UnstableApi::class)
    fun set(engine: FlutterEngine, on: Boolean): Int {
        val plugin = engine.plugins.get(VideoPlayerPlugin::class.java) ?: return 0
        val players = VideoPlayerPlugin::class.java.getDeclaredField("videoPlayers")
            .apply { isAccessible = true }
            .get(plugin) as LongSparseArray<*>
        val field = VideoPlayer::class.java.getDeclaredField("trackSelector").apply { isAccessible = true }
        var count = 0
        for (i in 0 until players.size()) {
            val selector = field.get(players.valueAt(i)) as? DefaultTrackSelector ?: continue
            selector.setParameters(selector.buildUponParameters().setTunnelingEnabled(on).build())
            count++
        }
        return count
    }
}
