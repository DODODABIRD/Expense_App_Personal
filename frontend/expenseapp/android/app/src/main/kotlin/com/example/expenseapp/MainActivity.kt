package com.example.expenseapp

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "expense_app/platform")
			.setMethodCallHandler { call, result ->
				if (call.method == "isAndroid") result.success(true) else result.notImplemented()
			}
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "expense_app/notifications")
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"openSettings" -> {
						startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
						result.success(null)
					}
					"isEnabled" -> result.success(isNotificationAccessEnabled())
					"setAllowedPackages" -> {
						val packages = (call.argument<List<String>>("packages") ?: emptyList()).toSet()
						NotificationListener.allowedPackages = packages
						NotificationListener.allowAllNotifications =
							call.argument<Boolean>("allowAll") == true
						result.success(null)
					}
					"setParserActive" -> {
						NotificationListener.parserActive = call.argument<Boolean>("active") == true
						result.success(null)
					}
					"start" -> result.success(null)
					else -> result.notImplemented()
				}
			}
		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "expense_app/notification_events")
			.setStreamHandler(NotificationListener.eventStreamHandler)
	}

	private fun isNotificationAccessEnabled(): Boolean {
		val component = ComponentName(this, NotificationListener::class.java).flattenToString()
		return Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
			?.split(":")?.contains(component) == true
	}
}
