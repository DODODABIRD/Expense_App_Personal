package com.example.expenseapp

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.os.Bundle
import io.flutter.plugin.common.EventChannel

class NotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
        )?.toString()?.trim() ?: return
        val payload = mapOf(
            "title" to (extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""),
            "text" to text,
            "packageName" to sbn.packageName,
        )
        eventSink?.success(payload)
    }

    companion object {
        var eventSink: EventChannel.EventSink? = null
        val eventStreamHandler = object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        }
    }
}