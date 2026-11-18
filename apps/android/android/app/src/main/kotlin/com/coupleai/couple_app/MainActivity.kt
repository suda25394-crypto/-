package com.coupleai.couple_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pickResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private val io = Executors.newSingleThreadExecutor()
    private var audio: AudioRecord? = null
    private var worker: Thread? = null
    private var pcm = ByteArrayOutputStream()
    @Volatile private var recording = false
    @Volatile private var captureFailed = false
    private var player: MediaPlayer? = null
    private var playback: File? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val mediaChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "couple/device_media")
        mediaChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "pick" -> {
                        if (pickResult != null) { result.error("busy","正在选择文件",null); return@setMethodCallHandler }
                        val intent=Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                        intent.type=if(call.argument<Boolean>("imageOnly")==true) "image/*" else "*/*"
                        startActivityForResult(intent, 401)
                        pickResult=result
                    }
                    "record" -> {
                        if (audio!=null || permissionResult!=null) { result.error("busy","正在录音",null); return@setMethodCallHandler }
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED) begin(result)
                        else { permissionResult=result; requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),402) }
                    }
                    "finish" -> {
                        haltCapture()
                        if(captureFailed || pcm.size()==0) result.error("capture","未录到可用的声音",null)
                        else result.success(wav(pcm.toByteArray()))
                        pcm.reset()
                    }
                    "cancel" -> {
                        permissionResult?.error("cancelled", "已取消录音", null)
                        permissionResult = null
                        haltCapture()
                        pcm.reset()
                        result.success(null)
                    }
                    "stop" -> { haltPlayback(); result.success(null) }
                    "play" -> {
                        haltPlayback()
                        val bytes=call.arguments as ByteArray
                        val file=File.createTempFile("dp-voice-", ".wav",cacheDir)
                        playback=file
                        file.writeBytes(bytes)
                        val media=MediaPlayer()
                        player=media
                        media.setDataSource(file.absolutePath)
                        media.setOnCompletionListener { haltPlayback() }
                        media.setOnErrorListener { _, _, _ ->
                            haltPlayback()
                            mediaChannel.invokeMethod("playbackFailed", "播放中断，请重新打开这段音频。")
                            true
                        }
                        media.prepare()
                        media.start()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e:Exception) {
                if (call.method == "play") haltPlayback()
                result.error("media", "设备媒体操作失败，请重试", null)
            }
        }
    }
    @Deprecated("Flutter activity callback")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode!=401) return
        val callback=pickResult ?: return
        pickResult=null
        val uri=data?.data
        if(resultCode!=RESULT_OK || uri==null) {callback.success(null);return}
        io.execute {
            try {
                val name=contentResolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use {
                    if(it.moveToFirst()) it.getString(0) else null
                } ?: "attachment"
                val mime=contentResolver.getType(uri) ?: "application/octet-stream"
                val bytes=contentResolver.openInputStream(uri)?.use { input ->
                    val buf=ByteArray(16384)
                    val out=ByteArrayOutputStream()
                    while(true) {
                        val n=input.read(buf)
                        if(n<0) break
                        require(out.size()+n<=4*1024*1024)
                        out.write(buf,0,n)
                    }
                    out.toByteArray()
                } ?: error("file")
                runOnUiThread {callback.success(mapOf("name" to name,"mime" to mime,"data" to bytes))}
            } catch(e:Exception) { runOnUiThread {callback.error("file","无法读取文件，单个附件最多 4 MiB",null)} }
        }
    }

    override fun onRequestPermissionsResult(code:Int,permissions:Array<String>,results:IntArray) {
        super.onRequestPermissionsResult(code,permissions,results)
        if(code==402) {
            val result=permissionResult ?: return
            permissionResult=null
            if(results.firstOrNull()==PackageManager.PERMISSION_GRANTED) begin(result)
            else result.error("denied","未授权麦克风，可以改为输入文字或选择音频文件。",null)
        }
    }
    private fun begin(result:MethodChannel.Result) {
        try {
            val size=AudioRecord.getMinBufferSize(16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT)
            require(size>0)
            val device=AudioRecord(MediaRecorder.AudioSource.MIC,16000,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_16BIT,maxOf(size,4096))
            audio=device
            check(device.state==AudioRecord.STATE_INITIALIZED)
            pcm=ByteArrayOutputStream()
            captureFailed=false
            device.startRecording()
            check(device.recordingState==AudioRecord.RECORDSTATE_RECORDING)
            recording=true
            worker=Thread {
                val buf=ByteArray(4096)
                try {
                    while(recording && pcm.size()<3840000) {
                        val n=device.read(buf,0,minOf(buf.size,3840000-pcm.size()))
                        if(n<0) {if(recording) captureFailed=true;break}
                        if(n>0) pcm.write(buf,0,n)
                    }
                } catch(e:Exception) { if(recording) captureFailed=true }
                finally { recording=false; runCatching { device.stop() } }
            }.also {it.start()}
            result.success(null)
        } catch(e:Exception) { haltCapture();result.error("capture","麦克风不可用",null) }
    }
    private fun haltCapture() {
        recording=false
        audio?.let { runCatching {it.stop()} }
        worker?.join(1200)
        audio?.release()
        audio=null;worker=null
    }
    private fun haltPlayback() {
        player?.release();player=null
        playback?.delete();playback=null
    }
    private fun wav(data:ByteArray):ByteArray = ByteBuffer.allocate(44+data.size).order(ByteOrder.LITTLE_ENDIAN).apply {
        put("RIFF".toByteArray());putInt(36+data.size);put("WAVEfmt ".toByteArray());putInt(16)
        putShort(1);putShort(1);putInt(16000);putInt(32000);putShort(2);putShort(16)
        put("data".toByteArray());putInt(data.size);put(data)
    }.array()
    override fun onStop() { super.onStop();haltCapture();haltPlayback() }
    override fun onDestroy() { haltCapture();haltPlayback();io.shutdown();super.onDestroy() }
}
