package com.example.expenseapp

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

class NotificationListener : NotificationListenerService() {
    private lateinit var preferences: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        instance = this
        preferences = getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        allowedPackages = preferences.getStringSet(ALLOWED_PACKAGES, emptySet()) ?: emptySet()
        allowAllNotifications = preferences.getBoolean(ALLOW_ALL_NOTIFICATIONS, false)
        parserActive = preferences.getBoolean(PARSER_ACTIVE, true)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // 1. Basic active & permission filter
        if (!parserActive ||
            (!allowAllNotifications && !allowedPackages.contains(sbn.packageName))) return

        // 2. Ignore ongoing / persistent notifications (music players, system alerts, progress bars)
        if (sbn.isOngoing) return

        // 3. Deduplication filter: prevent duplicate events within 60 seconds
        val signature = "${sbn.packageName}_${sbn.id}_${sbn.postTime}"
        val now = System.currentTimeMillis()
        synchronized(recentSignatures) {
            val it = recentSignatures.entries.iterator()
            while (it.hasNext()) {
                if (now - it.next().value > DEDUP_WINDOW_MS) {
                    it.remove()
                }
            }
            if (recentSignatures.containsKey(signature)) {
                return
            }
            recentSignatures[signature] = now
        }

        // 4. Comprehensive text extraction
        val extras = sbn.notification.extras
        val textBuilder = StringBuilder()

        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
        val normalText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()?.trim()
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)

        if (!bigText.isNullOrEmpty()) {
            textBuilder.append(bigText)
        } else if (!normalText.isNullOrEmpty()) {
            textBuilder.append(normalText)
        }

        if (!subText.isNullOrEmpty() && !textBuilder.contains(subText)) {
            if (textBuilder.isNotEmpty()) textBuilder.append(" ")
            textBuilder.append(subText)
        }

        if (textLines != null && textLines.isNotEmpty()) {
            for (line in textLines) {
                val lineStr = line?.toString()?.trim()
                if (!lineStr.isNullOrEmpty() && !textBuilder.contains(lineStr)) {
                    if (textBuilder.isNotEmpty()) textBuilder.append(" ")
                    textBuilder.append(lineStr)
                }
            }
        }

        val fullText = textBuilder.toString().trim()
        if (fullText.isEmpty()) return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val payload = JSONObject().apply {
            put("title", title)
            put("text", fullText)
            put("packageName", sbn.packageName)
            put("postTime", sbn.postTime)
        }.toString()

        synchronized(this) {
            if (eventSink != null) {
                eventSink?.success(payloadToMap(payload))
            } else {
                // Store in ordered FIFO queue
                val rawQueue = preferences.getString(PENDING_QUEUE, "[]") ?: "[]"
                val jsonArray = try {
                    JSONArray(rawQueue)
                } catch (_: Exception) {
                    JSONArray()
                }

                // Prevent unbounded growth (keep latest 100)
                if (jsonArray.length() >= 100) {
                    jsonArray.remove(0)
                }
                jsonArray.put(payload)
                preferences.edit().putString(PENDING_QUEUE, jsonArray.toString()).apply()
            }
        }
    }

    private fun payloadToMap(payload: String): Map<String, Any> {
        val json = JSONObject(payload)
        return mapOf(
            "title" to json.optString("title", ""),
            "text" to json.optString("text", ""),
            "packageName" to json.optString("packageName", ""),
            "postTime" to json.optLong("postTime", System.currentTimeMillis()),
        )
    }

    private fun drainPendingNotifications() {
        val rawQueue = preferences.getString(PENDING_QUEUE, null) ?: return
        preferences.edit().remove(PENDING_QUEUE).apply()
        try {
            val jsonArray = JSONArray(rawQueue)
            for (i in 0 until jsonArray.length()) {
                val payload = jsonArray.getString(i)
                eventSink?.success(payloadToMap(payload))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    companion object {
        private const val PREFERENCES = "notification_parser"
        private const val ALLOWED_PACKAGES = "allowed_packages"
        private const val ALLOW_ALL_NOTIFICATIONS = "allow_all_notifications"
        private const val PARSER_ACTIVE = "parser_active"
        private const val PENDING_QUEUE = "pending_notifications_queue"
        private const val DEDUP_WINDOW_MS = 60_000L

        private val recentSignatures = LinkedHashMap<String, Long>()
        private var instance: NotificationListener? = null

        var allowedPackages: Set<String> = emptySet()
            set(value) {
                field = value
                instance?.preferences?.edit()
                    ?.putStringSet(ALLOWED_PACKAGES, value)?.apply()
            }

        var parserActive: Boolean = true
            set(value) {
                field = value
                instance?.preferences?.edit()
                    ?.putBoolean(PARSER_ACTIVE, value)?.apply()
            }

        var allowAllNotifications: Boolean = false
            set(value) {
                field = value
                instance?.preferences?.edit()
                    ?.putBoolean(ALLOW_ALL_NOTIFICATIONS, value)?.apply()
            }

        var eventSink: EventChannel.EventSink? = null
        val eventStreamHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                instance?.drainPendingNotifications()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        }
    }
}