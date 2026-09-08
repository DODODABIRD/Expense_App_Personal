package com.example.expenseapp

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
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
        if (!parserActive ||
            (!allowAllNotifications && !allowedPackages.contains(sbn.packageName))) return
        val extras = sbn.notification.extras
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
        )?.toString()?.trim() ?: return
        val payload = JSONObject().apply {
            put("title", extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: "")
            put("text", text)
            put("packageName", sbn.packageName)
        }.toString()

        synchronized(this) {
            if (eventSink != null) {
                eventSink?.success(payloadToMap(payload))
            } else {
                val queued = preferences
                    .getStringSet(PENDING_NOTIFICATIONS, emptySet())
                    ?.toMutableSet() ?: mutableSetOf()
                queued.add(payload)
                preferences.edit().putStringSet(PENDING_NOTIFICATIONS, queued).apply()
            }
        }
    }

    private fun payloadToMap(payload: String): Map<String, String> {
        val json = JSONObject(payload)
        return mapOf(
            "title" to json.getString("title"),
            "text" to json.getString("text"),
            "packageName" to json.getString("packageName"),
        )
    }

    private fun drainPendingNotifications() {
        val queued = preferences
            .getStringSet(PENDING_NOTIFICATIONS, emptySet())
            ?.toList() ?: emptyList()
        preferences.edit().remove(PENDING_NOTIFICATIONS).apply()
        queued.forEach { eventSink?.success(payloadToMap(it)) }
    }

    companion object {
        private const val PREFERENCES = "notification_parser"
        private const val ALLOWED_PACKAGES = "allowed_packages"
        private const val ALLOW_ALL_NOTIFICATIONS = "allow_all_notifications"
        private const val PARSER_ACTIVE = "parser_active"
        private const val PENDING_NOTIFICATIONS = "pending_notifications"
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