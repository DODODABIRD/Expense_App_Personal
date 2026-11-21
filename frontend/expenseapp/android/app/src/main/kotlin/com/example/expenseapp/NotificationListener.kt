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
        attach(applicationContext)
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

        // 3. Comprehensive text extraction
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

        // 4. Deduplication filter: many banking apps reuse the same notification id and
        // Android keeps the original postTime on updates, so dedup must be content-based
        // rather than id/postTime-based, otherwise every later transaction gets dropped.
        val signature = "${sbn.packageName}_${title}_$fullText"
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

        // 5. Always persist first. The queue is only emptied by ack() once Dart has
        // stored a draft, so a dead engine or a crash mid-parse cannot lose it.
        val key = "${sbn.packageName}|${sbn.postTime}|${(title + "\u0000" + fullText).hashCode()}"
        val payload = JSONObject().apply {
            put("key", key)
            put("title", title)
            put("text", fullText)
            put("packageName", sbn.packageName)
            put("postTime", sbn.postTime)
        }
        enqueue(payload)

        // 6. Wake Dart up. This is only a hint; a failed or stale sink is harmless.
        try {
            eventSink?.success("new")
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val MAX_QUEUE = 500
        private val queueLock = Any()

        private fun readQueue(): JSONArray {
            val raw = sharedPreferences()?.getString(PENDING_QUEUE, "[]") ?: "[]"
            return try {
                JSONArray(raw)
            } catch (_: Exception) {
                JSONArray()
            }
        }

        private fun enqueue(payload: JSONObject) {
            synchronized(queueLock) {
                val queue = readQueue()
                // Keep the newest MAX_QUEUE entries (drop the oldest).
                val trimmed = JSONArray()
                val start = maxOf(0, queue.length() - (MAX_QUEUE - 1))
                for (i in start until queue.length()) trimmed.put(queue.get(i))
                trimmed.put(payload)
                sharedPreferences()?.edit()?.putString(PENDING_QUEUE, trimmed.toString())?.commit()
            }
        }

        /** Everything not yet acknowledged, oldest first. Does not remove anything. */
        fun takePending(): List<Map<String, Any>> = synchronized(queueLock) {
            val queue = readQueue()
            val items = ArrayList<Map<String, Any>>()
            for (i in 0 until queue.length()) {
                val json = queue.optJSONObject(i) ?: continue
                items.add(
                    mapOf(
                        "key" to json.optString("key", ""),
                        "title" to json.optString("title", ""),
                        "text" to json.optString("text", ""),
                        "packageName" to json.optString("packageName", ""),
                        "postTime" to json.optLong("postTime", System.currentTimeMillis()),
                    )
                )
            }
            items
        }

        /** Removes entries Dart has stored (or deliberately filtered out). */
        fun ack(keys: Set<String>) {
            if (keys.isEmpty()) return
            synchronized(queueLock) {
                val queue = readQueue()
                val kept = JSONArray()
                for (i in 0 until queue.length()) {
                    val json = queue.optJSONObject(i) ?: continue
                    if (!keys.contains(json.optString("key", ""))) kept.put(json)
                }
                sharedPreferences()?.edit()?.putString(PENDING_QUEUE, kept.toString())?.commit()
            }
        }

        private const val PREFERENCES = "notification_parser"
        private const val ALLOWED_PACKAGES = "allowed_packages"
        private const val ALLOW_ALL_NOTIFICATIONS = "allow_all_notifications"
        private const val PARSER_ACTIVE = "parser_active"
        private const val PENDING_QUEUE = "pending_notifications_queue"
        private const val DEDUP_WINDOW_MS = 60_000L

        private val recentSignatures = LinkedHashMap<String, Long>()
        private var instance: NotificationListener? = null
        private var appContext: Context? = null

        // Called by both MainActivity and the service so settings survive even
        // when the listener service has not been bound yet.
        fun attach(context: Context) {
            if (appContext == null) appContext = context.applicationContext
        }

        private fun sharedPreferences(): SharedPreferences? =
            appContext?.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

        var allowedPackages: Set<String> = emptySet()
            set(value) {
                field = value
                sharedPreferences()?.edit()?.putStringSet(ALLOWED_PACKAGES, value)?.apply()
            }

        var parserActive: Boolean = true
            set(value) {
                field = value
                sharedPreferences()?.edit()?.putBoolean(PARSER_ACTIVE, value)?.apply()
            }

        var allowAllNotifications: Boolean = false
            set(value) {
                field = value
                sharedPreferences()?.edit()?.putBoolean(ALLOW_ALL_NOTIFICATIONS, value)?.apply()
            }

        var eventSink: EventChannel.EventSink? = null
        val eventStreamHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        }
    }
}