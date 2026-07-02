package com.mrppfruit.noema

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingGalleryAccessResult: MethodChannel.Result? = null
    private var pendingSystemDeleteResult: MethodChannel.Result? = null
    private var pendingSystemDeleteUriCount: Int = 0
    private var systemBackChannel: MethodChannel? = null
    private var predictiveBackCallback: OnBackInvokedCallback? = null
    private val imageExecutor: ExecutorService = Executors.newFixedThreadPool(IMAGE_WORKER_COUNT)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemBackChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_BACK_CHANNEL,
        )
        registerSystemBackHandler()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "galleryAccessStatus" -> result.success(galleryAccessStatus())
                "requestGalleryAccess" -> requestGalleryAccess(result)
                "refreshGalleryIndex" -> refreshGalleryIndex(call, result)
                "warmGalleryThumbnails" -> warmGalleryThumbnails(call, result)
                "pickImages" -> pickImages(call, result)
                "loadMetadata" -> loadMetadata(call, result)
                "createThumbnail" -> createCachedImage(call, result, "thumbs", 320)
                "createPreview" -> createCachedImage(call, result, "previews", 1800)
                "deleteCachedFiles" -> deleteCachedFiles(call, result)
                "deleteMediaItems" -> deleteMediaItems(call, result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "noema/local_storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageDirectory" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_PROFILE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "imageCacheProfile" -> result.success(imageCacheProfile())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_LINKS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> openExternalUrl(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unregisterSystemBackHandler()
        systemBackChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        unregisterSystemBackHandler()
        imageExecutor.shutdown()
        super.onDestroy()
    }

    private fun registerSystemBackHandler() {
        unregisterSystemBackHandler()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val callback = OnBackInvokedCallback { dispatchSystemBackToFlutter() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                callback,
            )
            predictiveBackCallback = callback
        }
    }

    private fun unregisterSystemBackHandler() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            predictiveBackCallback?.let {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
            }
            predictiveBackCallback = null
        }
    }

    private fun dispatchSystemBackToFlutter() {
        systemBackChannel?.invokeMethod(
            "systemBack",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun notImplemented() = Unit
            },
        )
    }

    private fun openExternalUrl(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim()
        if (url.isNullOrEmpty()) {
            result.error("invalid_url", "URL is required.", null)
            return
        }

        val uri = Uri.parse(url)
        val scheme = uri.scheme?.lowercase(Locale.ROOT)
        if (scheme != "https" && scheme != "http") {
            result.error("invalid_url", "Only http and https URLs are supported.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, uri)
            .addCategory(Intent.CATEGORY_BROWSABLE)
        try {
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("browser_unavailable", "No browser can open this URL.", null)
        }
    }

    @Deprecated("Deprecated in Android API 33")
    override fun onBackPressed() {
        dispatchSystemBackToFlutter()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_DELETE_MEDIA_ITEMS) {
            completeSystemMediaDelete(resultCode)
            return
        }
        if (requestCode != REQUEST_PICK_IMAGES) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        val uris = selectedUris(data)
        uris.forEach { uri -> persistReadPermission(uri) }
        result.success(uris.map { uri -> minimalMediaMap(uri) })
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_GALLERY_ACCESS) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }

        val result = pendingGalleryAccessResult
        pendingGalleryAccessResult = null
        result?.success(galleryAccessStatus())
    }

    private fun requestGalleryAccess(result: MethodChannel.Result) {
        val currentStatus = galleryAccessStatus()
        if (currentStatus == ACCESS_FULL || currentStatus == ACCESS_PARTIAL) {
            result.success(currentStatus)
            return
        }

        if (pendingGalleryAccessResult != null) {
            result.error("already_active", "Noema gallery permission request is already active.", null)
            return
        }

        val permissions = galleryPermissions()
        if (permissions.isEmpty()) {
            result.success(galleryAccessStatus())
            return
        }

        pendingGalleryAccessResult = result
        requestPermissions(permissions, REQUEST_GALLERY_ACCESS)
    }

    private fun galleryAccessStatus(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return ACCESS_FULL
        }

        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> when {
                hasPermission(Manifest.permission.READ_MEDIA_IMAGES) -> ACCESS_FULL
                hasPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> ACCESS_PARTIAL
                else -> ACCESS_DENIED
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                if (hasPermission(Manifest.permission.READ_MEDIA_IMAGES)) {
                    ACCESS_FULL
                } else {
                    ACCESS_DENIED
                }
            }
            hasPermission(Manifest.permission.READ_EXTERNAL_STORAGE) -> ACCESS_FULL
            else -> ACCESS_DENIED
        }
    }

    private fun imageCacheProfile(): Map<String, Any> {
        val activityManager =
            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        val displayMetrics = resources.displayMetrics
        return mapOf(
            "memoryClassMb" to activityManager.memoryClass,
            "largeMemoryClassMb" to activityManager.largeMemoryClass,
            "isLowRamDevice" to activityManager.isLowRamDevice,
            "totalMemoryMb" to max(1, (memoryInfo.totalMem / (1024L * 1024L)).toInt()),
            "screenWidthPixels" to displayMetrics.widthPixels,
            "screenHeightPixels" to displayMetrics.heightPixels,
        )
    }

    private fun galleryPermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return emptyArray()
        }
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun refreshGalleryIndex(call: MethodCall, result: MethodChannel.Result) {
        val status = galleryAccessStatus()
        if (status == ACCESS_DENIED) {
            result.success(mapOf("access" to status, "count" to 0))
            return
        }

        val maxItems = call.argument<Int>("maxItems") ?: 0
        imageExecutor.execute {
            try {
                val count = writeGalleryIndex(maxItems)
                result.successOnMain(
                    mapOf(
                        "access" to galleryAccessStatus(),
                        "count" to count,
                        "path" to galleryIndexFile().absolutePath,
                    ),
                )
            } catch (error: Exception) {
                result.errorOnMain("gallery_index_failed", error.message, null)
            }
        }
    }

    private fun warmGalleryThumbnails(call: MethodCall, result: MethodChannel.Result) {
        val status = galleryAccessStatus()
        if (status == ACCESS_DENIED) {
            result.success(0)
            return
        }

        val maxItems = call.argument<Int>("maxItems") ?: GALLERY_WARM_THUMBNAIL_COUNT
        val maxSize = call.argument<Int>("maxSize") ?: 320
        imageExecutor.execute {
            try {
                var warmed = 0
                queryGalleryCursor()?.use { cursor ->
                    while (cursor.moveToNext() && (maxItems <= 0 || warmed < maxItems)) {
                        val uri = cursor.galleryUri() ?: continue
                        try {
                            if (prepareCachedImage(uri, "thumbs", maxSize) != null) {
                                warmed += 1
                            }
                        } catch (_: Exception) {
                            // A single unavailable cloud-backed image should not stop
                            // the rest of the local prewarm pass.
                        }
                    }
                }
                result.successOnMain(warmed)
            } catch (error: Exception) {
                result.errorOnMain("gallery_warm_failed", error.message, null)
            }
        }
    }

    private fun loadMetadata(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")
        if (uriValue.isNullOrBlank()) {
            result.error("missing_uri", "Missing source uri.", null)
            return
        }

        val uri = Uri.parse(uriValue)
        imageExecutor.execute {
            result.successOnMain(mediaMap(uri))
        }
    }

    private fun pickImages(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("already_active", "Noema media picker is already active.", null)
            return
        }

        pendingPickResult = result
        val requestedLimit = call.argument<Int>("limit") ?: 300
        val intent = imagePickerIntent(requestedLimit)
        try {
            startActivityForResult(intent, REQUEST_PICK_IMAGES)
        } catch (error: Exception) {
            pendingPickResult = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    private fun imagePickerIntent(requestedLimit: Int): Intent {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val maxLimit = MediaStore.getPickImagesMaxLimit()
            val limit = min(max(2, requestedLimit), maxLimit)
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, limit)
            }
        } else {
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
    }

    private fun selectedUris(data: Intent): List<Uri> {
        val uris = LinkedHashSet<Uri>()
        data.data?.let { uris.add(it) }
        val clipData = data.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        return uris.toList()
    }

    private fun persistReadPermission(uri: Uri) {
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (_: Exception) {
            // Android Photo Picker grants selected media access directly, while
            // some document providers allow persistable grants. Ignore providers
            // that do not support it and keep the cached preview fallback.
        }
    }

    private fun minimalMediaMap(uri: Uri): Map<String, Any?> {
        val uriValue = uri.toString()
        return mapOf(
            "uri" to uriValue,
            "id" to uriValue,
            "name" to (uri.lastPathSegment ?: "photo"),
        )
    }

    private fun mediaMap(uri: Uri): Map<String, Any?> {
        val metadata = queryMetadata(uri)
        val exif = readExifMetadata(uri)
        val orientation = displayOrientation(uri, metadata.orientationDegrees)
        val bounds = if (
            metadata.width == null ||
            metadata.height == null ||
            orientationSwapsDimensions(orientation)
        ) {
            decodeBounds(uri)
        } else {
            null
        }
        val dimensions = displayDimensions(
            metadata.width,
            metadata.height,
            bounds,
            orientation,
        )
        val name = metadata.name ?: uri.lastPathSegment ?: "photo"
        return mapOf(
            "uri" to uri.toString(),
            "id" to uri.toString(),
            "name" to name,
            "mimeType" to (metadata.mimeType ?: contentMimeType(uri)),
            "fileSize" to metadata.fileSize,
            "width" to dimensions?.first,
            "height" to dimensions?.second,
            "takenAtMillis" to (exif.takenAtMillis ?: metadata.takenAtMillis),
            "modifiedAtMillis" to metadata.modifiedAtMillis,
            "exifTakenAtMillis" to exif.takenAtMillis,
            "iso" to exif.iso,
            "shutterSpeed" to exif.shutterSpeed,
            "aperture" to exif.aperture,
            "focalLengthMm" to exif.focalLengthMm,
            "whiteBalance" to exif.whiteBalance,
        )
    }

    private fun writeGalleryIndex(maxItems: Int): Int {
        val file = galleryIndexFile()
        file.parentFile?.mkdirs()
        val tempFile = File.createTempFile(file.name, ".tmp", file.parentFile)
        var count = 0

        OutputStreamWriter(FileOutputStream(tempFile), Charsets.UTF_8).use { writer ->
            writer.write(
                "{\"version\":1,\"refreshedAtMillis\":${System.currentTimeMillis()}," +
                    "\"access\":\"${galleryAccessStatus()}\",\"items\":[",
            )

            queryGalleryCursor()?.use { cursor ->
                while (cursor.moveToNext() && (maxItems <= 0 || count < maxItems)) {
                    val item = cursor.galleryMediaMap() ?: continue
                    if (count > 0) {
                        writer.write(",")
                    }
                    writer.write(JSONObject(item).toString())
                    count += 1
                }
            }
            writer.write("]}")
        }

        if (!tempFile.renameTo(file)) {
            tempFile.copyTo(file, overwrite = true)
            tempFile.delete()
        }
        return count
    }

    private fun galleryIndexFile(): File {
        val directory = File(filesDir, "noema_media/index")
        return File(directory, GALLERY_INDEX_FILE_NAME)
    }

    private fun queryGalleryCursor(): Cursor? {
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.ORIENTATION,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.BUCKET_ID,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
        )
        return contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            "${MediaStore.Images.Media.DATE_MODIFIED} DESC",
        )
    }

    private fun Cursor.galleryUri(): Uri? {
        val id = longValue(MediaStore.Images.Media._ID) ?: return null
        return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
    }

    private fun Cursor.galleryMediaMap(): Map<String, Any?>? {
        val uri = galleryUri() ?: return null
        val uriValue = uri.toString()
        val exif = readExifMetadata(uri)
        val orientation = orientationFromDegrees(intValue(MediaStore.Images.Media.ORIENTATION))
        val dimensions = displayDimensions(
            intValue(MediaStore.Images.Media.WIDTH),
            intValue(MediaStore.Images.Media.HEIGHT),
            null,
            orientation,
        )
        val name = stringValue(MediaStore.Images.Media.DISPLAY_NAME)
            ?: uri.lastPathSegment
            ?: "photo"
        val thumbnailFile = cachedImageFile("thumbs", uriValue, 320)
        return mapOf(
            "uri" to uriValue,
            "id" to uriValue,
            "name" to name,
            "mimeType" to stringValue(MediaStore.Images.Media.MIME_TYPE),
            "fileSize" to longValue(MediaStore.Images.Media.SIZE),
            "width" to dimensions?.first,
            "height" to dimensions?.second,
            "takenAtMillis" to normalizedMillis(MediaStore.Images.Media.DATE_TAKEN),
            "modifiedAtMillis" to normalizedMillis(MediaStore.Images.Media.DATE_MODIFIED),
            "bucketId" to stringValue(MediaStore.Images.Media.BUCKET_ID),
            "bucketName" to stringValue(MediaStore.Images.Media.BUCKET_DISPLAY_NAME),
            "iso" to exif.iso,
            "shutterSpeed" to exif.shutterSpeed,
            "aperture" to exif.aperture,
            "focalLengthMm" to exif.focalLengthMm,
            "whiteBalance" to exif.whiteBalance,
            "thumbnailPath" to if (thumbnailFile.exists() && thumbnailFile.length() > 0) {
                thumbnailFile.absolutePath
            } else {
                null
            },
        )
    }

    private fun queryMetadata(uri: Uri): MediaMetadata {
        val projection = arrayOf(
            OpenableColumns.DISPLAY_NAME,
            OpenableColumns.SIZE,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.ORIENTATION,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_MODIFIED,
            MediaStore.Images.Media.MIME_TYPE,
        )
        return try {
            contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return MediaMetadata()
                }
                MediaMetadata(
                    name = cursor.stringValue(OpenableColumns.DISPLAY_NAME),
                    fileSize = cursor.longValue(OpenableColumns.SIZE),
                    width = cursor.intValue(MediaStore.Images.Media.WIDTH),
                    height = cursor.intValue(MediaStore.Images.Media.HEIGHT),
                    orientationDegrees = cursor.intValue(MediaStore.Images.Media.ORIENTATION),
                    takenAtMillis = cursor.normalizedMillis(MediaStore.Images.Media.DATE_TAKEN),
                    modifiedAtMillis = cursor.normalizedMillis(MediaStore.Images.Media.DATE_MODIFIED),
                    mimeType = cursor.stringValue(MediaStore.Images.Media.MIME_TYPE),
                )
            } ?: MediaMetadata()
        } catch (_: Exception) {
            MediaMetadata()
        }
    }

    private fun contentMimeType(uri: Uri): String? {
        return try {
            contentResolver.getType(uri)
        } catch (_: Exception) {
            null
        }
    }

    private fun readExifMetadata(uri: Uri): MediaExif {
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val exif = ExifInterface(stream)
                MediaExif(
                    takenAtMillis = exifTakenAtMillis(exif),
                    iso = exifIso(exif),
                    shutterSpeed = exifExposureTime(exif),
                    aperture = exif.getAttributeDouble(ExifInterface.TAG_F_NUMBER, 0.0)
                        .takeIf { it > 0.0 },
                    focalLengthMm = exif.getAttributeDouble(ExifInterface.TAG_FOCAL_LENGTH, 0.0)
                        .takeIf { it > 0.0 },
                    whiteBalance = exifWhiteBalance(exif),
                )
            } ?: MediaExif()
        } catch (_: Exception) {
            MediaExif()
        }
    }

    private fun exifTakenAtMillis(exif: ExifInterface): Long? {
        val tags = arrayOf(
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_DATETIME,
        )
        for (tag in tags) {
            val parsed = parseExifDateMillis(exif.getAttribute(tag))
            if (parsed != null) {
                return parsed
            }
        }
        return null
    }

    private fun parseExifDateMillis(value: String?): Long? {
        if (value.isNullOrBlank()) {
            return null
        }
        return try {
            val formatter = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US)
            formatter.isLenient = false
            formatter.parse(value.trim())?.time
        } catch (_: Exception) {
            null
        }
    }

    private fun exifIso(exif: ExifInterface): Int? {
        return firstPositiveExifInt(
            exif,
            ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
            ExifInterface.TAG_ISO_SPEED,
            ExifInterface.TAG_ISO_SPEED_RATINGS,
            ExifInterface.TAG_RW2_ISO,
        )
    }

    private fun exifExposureTime(exif: ExifInterface): String? {
        val seconds = exif.getAttributeDouble(ExifInterface.TAG_EXPOSURE_TIME, 0.0)
        if (seconds <= 0.0) {
            return null
        }
        if (seconds < 1.0) {
            val denominator = (1.0 / seconds).roundToInt()
            if (denominator > 0) {
                return "1/${denominator}s"
            }
        }
        val rounded = if (seconds == seconds.toInt().toDouble()) {
            seconds.toInt().toString()
        } else {
            String.format("%.1f", seconds)
        }
        return "${rounded}s"
    }

    private fun firstPositiveExifInt(exif: ExifInterface, vararg tags: String): Int? {
        for (tag in tags) {
            val value = exif.getAttributeInt(tag, 0)
            if (value > 0) {
                return value
            }
        }
        return null
    }

    private fun exifWhiteBalance(exif: ExifInterface): String? {
        return when (exif.getAttributeInt(ExifInterface.TAG_WHITE_BALANCE, -1)) {
            ExifInterface.WHITEBALANCE_AUTO -> "WB 自动"
            ExifInterface.WHITEBALANCE_MANUAL -> "WB 手动"
            else -> null
        }
    }

    private fun android.database.Cursor.stringValue(column: String): String? {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) return null
        return getString(index)
    }

    private fun android.database.Cursor.intValue(column: String): Int? {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) return null
        val value = getInt(index)
        return if (value > 0) value else null
    }

    private fun android.database.Cursor.longValue(column: String): Long? {
        val index = getColumnIndex(column)
        if (index < 0 || isNull(index)) return null
        val value = getLong(index)
        return if (value > 0) value else null
    }

    private fun android.database.Cursor.normalizedMillis(column: String): Long? {
        val value = longValue(column) ?: return null
        return if (value < 100000000000L) value * 1000 else value
    }

    private fun decodeBounds(uri: Uri): Pair<Int, Int>? {
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeStream(stream, null, options)
                if (options.outWidth > 0 && options.outHeight > 0) {
                    options.outWidth to options.outHeight
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun createCachedImage(
        call: MethodCall,
        result: MethodChannel.Result,
        directoryName: String,
        defaultMaxSize: Int,
    ) {
        val uriValue = call.argument<String>("uri")
        if (uriValue.isNullOrBlank()) {
            result.error("missing_uri", "Missing source uri.", null)
            return
        }

        val maxSize = call.argument<Int>("maxSize") ?: defaultMaxSize
        val uri = Uri.parse(uriValue)
        val file = cachedImageFile(directoryName, uriValue, maxSize)
        if (file.exists() && file.length() > 0) {
            result.success(file.absolutePath)
            return
        }

        imageExecutor.execute {
            try {
                result.successOnMain(prepareCachedImage(uri, directoryName, maxSize))
            } catch (error: Exception) {
                result.errorOnMain("image_prepare_failed", error.message, null)
            }
        }
    }

    private fun deleteCachedFiles(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<Any?>>("paths").orEmpty().filterIsInstance<String>()
        if (paths.isEmpty()) {
            result.success(0)
            return
        }

        imageExecutor.execute {
            try {
                val deletedCount = paths.count { deleteNoemaCachedFile(it) }
                result.successOnMain(deletedCount)
            } catch (error: Exception) {
                result.errorOnMain("cache_delete_failed", error.message, null)
            }
        }
    }

    private fun deleteMediaItems(call: MethodCall, result: MethodChannel.Result) {
        val uriValues = call.argument<List<Any?>>("uris").orEmpty().filterIsInstance<String>()
        if (uriValues.isEmpty()) {
            result.success(mapOf("deleted" to false, "count" to 0, "cancelled" to false))
            return
        }
        if (pendingSystemDeleteResult != null) {
            result.error("system_media_delete_busy", "Another media delete request is active.", null)
            return
        }

        val deleteUris = mutableListOf<Uri>()
        val seenUris = mutableSetOf<String>()
        for (value in uriValues) {
            val mediaUri = mediaStoreDeleteUri(Uri.parse(value))
            if (mediaUri == null) {
                result.error(
                    "unsupported_media_uri",
                    "Only specific MediaStore media items can be deleted.",
                    value,
                )
                return
            }
            val key = mediaUri.toString()
            if (seenUris.add(key)) {
                deleteUris.add(mediaUri)
            }
        }
        if (deleteUris.isEmpty()) {
            result.success(mapOf("deleted" to false, "count" to 0, "cancelled" to false))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val request = try {
                MediaStore.createDeleteRequest(contentResolver, deleteUris)
            } catch (error: IllegalArgumentException) {
                result.error("unsupported_media_uri", error.message, null)
                return
            } catch (error: SecurityException) {
                result.error("system_media_delete_failed", error.message, null)
                return
            }
            pendingSystemDeleteResult = result
            pendingSystemDeleteUriCount = deleteUris.size
            try {
                startIntentSenderForResult(
                    request.intentSender,
                    REQUEST_DELETE_MEDIA_ITEMS,
                    null,
                    0,
                    0,
                    0,
                    null,
                )
            } catch (error: IntentSender.SendIntentException) {
                pendingSystemDeleteResult = null
                pendingSystemDeleteUriCount = 0
                result.error("system_media_delete_failed", error.message, null)
            }
            return
        }

        result.error(
            "system_media_delete_unsupported",
            "Deleting system media from Noema requires Android 11 or later.",
            null,
        )
    }

    private fun completeSystemMediaDelete(resultCode: Int) {
        val result = pendingSystemDeleteResult ?: return
        val count = pendingSystemDeleteUriCount
        pendingSystemDeleteResult = null
        pendingSystemDeleteUriCount = 0
        val deleted = resultCode == Activity.RESULT_OK
        result.success(
            mapOf(
                "deleted" to deleted,
                "count" to if (deleted) count else 0,
                "cancelled" to !deleted,
            ),
        )
    }

    private fun mediaStoreDeleteUri(uri: Uri): Uri? {
        if (isSpecificMediaStoreItem(uri)) {
            return uri
        }
        photoPickerMediaStoreUri(uri)?.let { return it }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val mediaUri = MediaStore.getMediaUri(this, uri)
                if (mediaUri != null && isSpecificMediaStoreItem(mediaUri)) {
                    return mediaUri
                }
            } catch (_: Exception) {
                return null
            }
        }
        return null
    }

    private fun photoPickerMediaStoreUri(uri: Uri): Uri? {
        if (uri.scheme != "content" || uri.authority != MediaStore.AUTHORITY) {
            return null
        }
        val segments = uri.pathSegments
        if (segments.size < 2 || segments[segments.size - 2] != "media") {
            return null
        }
        val id = uri.lastPathSegment?.toLongOrNull() ?: return null
        if (!segments.contains("picker")) {
            return null
        }
        val candidate = ContentUris.withAppendedId(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            id,
        )
        return if (mediaStoreImageExists(candidate)) candidate else null
    }

    private fun mediaStoreImageExists(uri: Uri): Boolean {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media._ID),
                null,
                null,
                null,
            )?.use { cursor -> cursor.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun isSpecificMediaStoreItem(uri: Uri): Boolean {
        if (uri.scheme != "content" || uri.authority != MediaStore.AUTHORITY) {
            return false
        }
        val segments = uri.pathSegments
        if (segments.size < 4 || segments[segments.size - 2] != "media") {
            return false
        }
        if (segments[1] != "images") {
            return false
        }
        return try {
            ContentUris.parseId(uri) >= 0
        } catch (_: Exception) {
            false
        }
    }

    private fun deleteNoemaCachedFile(path: String): Boolean {
        if (path.isBlank()) {
            return false
        }
        return try {
            val file = File(path).canonicalFile
            val mediaRoot = File(filesDir, "noema_media").canonicalFile
            val rootPath = mediaRoot.path
            val isInsideMediaRoot =
                file.path == rootPath || file.path.startsWith("$rootPath${File.separator}")
            if (!isInsideMediaRoot || !file.exists() || !file.isFile) {
                return false
            }
            file.delete()
        } catch (_: Exception) {
            false
        }
    }

    private fun prepareCachedImage(uri: Uri, directoryName: String, maxSize: Int): String? {
        val file = cachedImageFile(directoryName, uri.toString(), maxSize)
        if (file.exists() && file.length() > 0) {
            return file.absolutePath
        }

        val bitmap = loadScaledBitmap(uri, maxSize) ?: return null
        try {
            writeBitmap(bitmap, file)
        } finally {
            bitmap.recycle()
        }
        return file.absolutePath
    }

    private fun loadScaledBitmap(uri: Uri, maxSize: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            decodeScaledBitmap(uri, maxSize)?.let { return it }
        }

        val bounds = decodeBounds(uri) ?: return null
        val sampleSize = sampleSize(bounds.first, bounds.second, maxSize)
        val bitmap = contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(
                stream,
                null,
                BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                },
            )
        }
        return bitmap?.let {
            scaleBitmapToMaxSize(
                applyExifOrientation(it, displayOrientation(uri)),
                maxSize,
            )
        }
    }

    private fun decodeScaledBitmap(uri: Uri, maxSize: Int): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return null
        }
        return try {
            val source = ImageDecoder.createSource(contentResolver, uri)
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val width = info.size.width
                val height = info.size.height
                val largestSide = max(width, height)
                if (maxSize > 0 && largestSide > maxSize) {
                    val scale = maxSize.toFloat() / largestSide
                    decoder.setTargetSize(
                        max(1, (width * scale).roundToInt()),
                        max(1, (height * scale).roundToInt()),
                    )
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun sampleSize(width: Int, height: Int, maxSize: Int): Int {
        var sample = 1
        var scaledWidth = width
        var scaledHeight = height
        while (scaledWidth / 2 >= maxSize || scaledHeight / 2 >= maxSize) {
            sample *= 2
            scaledWidth /= 2
            scaledHeight /= 2
        }
        return max(1, sample)
    }

    private fun cachedImageFile(directoryName: String, uriValue: String, maxSize: Int): File {
        val directory = File(filesDir, "noema_media/$directoryName")
        directory.mkdirs()
        val fileName = "${IMAGE_CACHE_VERSION}_${abs(uriValue.hashCode())}_$maxSize.jpg"
        return File(directory, fileName)
    }

    private fun writeBitmap(bitmap: Bitmap, file: File): File {
        val tempFile = File.createTempFile(file.name, ".tmp", file.parentFile)
        FileOutputStream(tempFile).use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)) {
                throw IllegalStateException("Bitmap compression failed.")
            }
        }
        if (!tempFile.renameTo(file)) {
            tempFile.copyTo(file, overwrite = true)
            tempFile.delete()
        }
        return file
    }

    private fun scaleBitmapToMaxSize(bitmap: Bitmap, maxSize: Int): Bitmap {
        if (maxSize <= 0) {
            return bitmap
        }
        val largestSide = max(bitmap.width, bitmap.height)
        if (largestSide <= maxSize) {
            return bitmap
        }

        val scale = maxSize.toFloat() / largestSide
        val targetWidth = max(1, (bitmap.width * scale).roundToInt())
        val targetHeight = max(1, (bitmap.height * scale).roundToInt())
        return try {
            val scaled = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
            if (scaled != bitmap) {
                bitmap.recycle()
            }
            scaled
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun readExifOrientation(uri: Uri): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return ExifInterface.ORIENTATION_NORMAL
        }
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                ExifInterface(stream).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
    }

    private fun displayOrientation(uri: Uri, mediaStoreOrientationDegrees: Int? = null): Int {
        val mediaStoreOrientation = orientationFromDegrees(
            mediaStoreOrientationDegrees ?: queryOrientationDegrees(uri),
        )
        if (mediaStoreOrientation != ExifInterface.ORIENTATION_NORMAL) {
            return mediaStoreOrientation
        }

        val exifOrientation = readExifOrientation(uri)
        if (exifOrientation != ExifInterface.ORIENTATION_NORMAL) {
            return exifOrientation
        }
        return ExifInterface.ORIENTATION_NORMAL
    }

    private fun queryOrientationDegrees(uri: Uri): Int? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.Images.Media.ORIENTATION),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.intValue(MediaStore.Images.Media.ORIENTATION)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun orientationFromDegrees(degrees: Int?): Int {
        return when (degrees) {
            90 -> ExifInterface.ORIENTATION_ROTATE_90
            180 -> ExifInterface.ORIENTATION_ROTATE_180
            270 -> ExifInterface.ORIENTATION_ROTATE_270
            else -> ExifInterface.ORIENTATION_NORMAL
        }
    }

    private fun displayDimensions(
        metadataWidth: Int?,
        metadataHeight: Int?,
        bounds: Pair<Int, Int>?,
        orientation: Int,
    ): Pair<Int, Int>? {
        val width = bounds?.first ?: metadataWidth
        val height = bounds?.second ?: metadataHeight
        if (width == null || height == null || width <= 0 || height <= 0) {
            return null
        }

        if (!orientationSwapsDimensions(orientation)) {
            return (metadataWidth ?: width) to (metadataHeight ?: height)
        }

        val swapped = height to width
        if (metadataWidth == swapped.first && metadataHeight == swapped.second) {
            return metadataWidth to metadataHeight
        }
        return swapped
    }

    private fun orientationSwapsDimensions(orientation: Int): Boolean {
        return orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
            orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
            orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
            orientation == ExifInterface.ORIENTATION_TRANSVERSE
    }

    private fun applyExifOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }

        return try {
            val oriented = Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true,
            )
            if (oriented != bitmap) {
                bitmap.recycle()
            }
            oriented
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun MethodChannel.Result.successOnMain(value: Any?) {
        runOnUiThread { success(value) }
    }

    private fun MethodChannel.Result.errorOnMain(
        code: String,
        message: String?,
        details: Any?,
    ) {
        runOnUiThread { error(code, message, details) }
    }

    private data class MediaMetadata(
        val name: String? = null,
        val fileSize: Long? = null,
        val width: Int? = null,
        val height: Int? = null,
        val orientationDegrees: Int? = null,
        val takenAtMillis: Long? = null,
        val modifiedAtMillis: Long? = null,
        val mimeType: String? = null,
    )

    private data class MediaExif(
        val takenAtMillis: Long? = null,
        val iso: Int? = null,
        val shutterSpeed: String? = null,
        val aperture: Double? = null,
        val focalLengthMm: Double? = null,
        val whiteBalance: String? = null,
    )

    companion object {
        private const val MEDIA_PICKER_CHANNEL = "noema/media_picker"
        private const val DEVICE_PROFILE_CHANNEL = "noema/device_profile"
        private const val EXTERNAL_LINKS_CHANNEL = "noema/external_links"
        private const val SYSTEM_BACK_CHANNEL = "com.mrppfruit.noema/system_back"
        private const val REQUEST_PICK_IMAGES = 7612
        private const val REQUEST_GALLERY_ACCESS = 7613
        private const val REQUEST_DELETE_MEDIA_ITEMS = 7614
        private const val IMAGE_WORKER_COUNT = 3
        private const val IMAGE_CACHE_VERSION = "v5"
        private const val GALLERY_WARM_THUMBNAIL_COUNT = 96
        private const val GALLERY_INDEX_FILE_NAME = "gallery_index_v1.json"
        private const val ACCESS_FULL = "full"
        private const val ACCESS_PARTIAL = "partial"
        private const val ACCESS_DENIED = "denied"
    }
}
