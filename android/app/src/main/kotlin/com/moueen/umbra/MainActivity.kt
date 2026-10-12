package com.moueen.umbra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random

class MainActivity : FlutterActivity() {
    private var wind: AudioTrack? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "umbra/ambience")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> { if (wind == null) wind = makeWind(); wind?.play() }
                        "pause" -> wind?.pause()
                        "dispose" -> { wind?.release(); wind = null }
                        else -> { result.notImplemented(); return@setMethodCallHandler }
                    }
                    result.success(null)
                } catch (error: Exception) {
                    wind?.release(); wind = null
                    result.error("AUDIO_UNAVAILABLE", error.message, null)
                }
            }
    }

    private fun makeWind(): AudioTrack {
        val sampleRate = 16000
        val frames = sampleRate * 8
        val samples = ShortArray(frames)
        val random = Random(3709)
        var low = 0.0
        var medium = 0.0
        for (i in 0 until frames) {
            val noise = random.nextDouble(-1.0, 1.0)
            low += (noise - low) * 0.018
            medium += (noise - medium) * 0.10
            val swell = 0.7 + 0.3 * sin(2 * PI * i / frames)
            samples[i] = ((low * 0.8 + medium * 0.2) * swell * 6200).toInt().toShort()
        }
        // Crossfade the ends once; playback uses a native static loop.
        val fade = sampleRate / 2
        for (i in 0 until fade) {
            val t = i.toDouble() / fade
            samples[frames - fade + i] =
                (samples[frames - fade + i] * (1 - t) + samples[i] * t).toInt().toShort()
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(frames * 2)
            .setTransferMode(AudioTrack.MODE_STATIC).build()
        track.write(samples, 0, samples.size)
        track.setLoopPoints(fade, frames, -1)
        track.setVolume(0.28f)
        return track
    }

    override fun onPause() { wind?.pause(); super.onPause() }
    override fun onDestroy() { wind?.release(); wind = null; super.onDestroy() }
}
