import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'databaseHelper.dart';

class NotificationExpenseService {
  NotificationExpenseService._();
  static final instance = NotificationExpenseService._();

  static const _methods = MethodChannel('expense_app/notifications');
  static const _events = EventChannel('expense_app/notification_events');
  static const allNotificationsKey = '__all_notifications__';
  static const supportedApps = <String, String>{
    'com.bca': 'BCA Mobile',
    'id.dana': 'OVO',
    'com.gojek.app': 'GoPay / Gojek',
    'id.bmri.livin': 'Livin’ by Mandiri',
    'com.grabtaxi.passenger': 'Grab',
    'com.tokopedia.tkpd': 'Tokopedia',
    'com.android.shell': 'Android Shell (debug)',
  };
  static final defaultAllowedApps = supportedApps.keys.toSet();
  Future<void> Function(String)? _onError;
  Future<void> Function()? _onExpenseAdded;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;

  Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _methods.invokeMethod<bool>('isEnabled') ?? false;
  }

  Future<void> openAccessSettings() async {
    if (Platform.isAndroid) await _methods.invokeMethod<void>('openSettings');
  }

  Future<Set<String>> getAllowedApps() async {
    final stored = await DatabaseHelp.getSetting('notification_allowed_apps');
    if (stored == null) return {...defaultAllowedApps};
    try {
      final values = (jsonDecode(stored) as List).whereType<String>().toSet();
      if (values.contains(allNotificationsKey)) return {allNotificationsKey};
      return values.intersection(supportedApps.keys.toSet());
    } catch (_) {
      return {...defaultAllowedApps};
    }
  }

  Future<void> setAllowedApps(Set<String> packages) async {
    final allowAll = packages.contains(allNotificationsKey);
    final allowed = allowAll
        ? {allNotificationsKey}
        : packages.intersection(supportedApps.keys.toSet());
    await DatabaseHelp.setSetting(
      'notification_allowed_apps',
      jsonEncode(allowed.toList()),
    );
    if (Platform.isAndroid) {
      await _methods.invokeMethod<void>('setAllowedPackages', {
        'packages': allowed.toList(),
        'allowAll': allowAll,
      });
    }
  }

  Future<bool> isParserEnabled() async {
    return (await DatabaseHelp.getSetting('auto_expense_parser')) != 'false';
  }

  Future<void> setParserEnabled(bool enabled) async {
    await DatabaseHelp.setSetting('auto_expense_parser', enabled.toString());
    if (Platform.isAndroid) {
      await _methods.invokeMethod<void>('setParserActive', {'active': enabled});
    }
    if (!enabled) await stop();
  }

  Future<void> start(
    Future<void> Function(String)? onError, {
    Future<void> Function()? onExpenseAdded,
  }) async {
    _onError = onError;
    _onExpenseAdded = onExpenseAdded;
    if (_started || !Platform.isAndroid) return;
    await _methods.invokeMethod<void>('setParserActive', {'active': true});
    await setAllowedApps(await getAllowedApps());
    _started = true;
    _subscription = _events.receiveBroadcastStream().listen((event) async {
      final data = Map<String, dynamic>.from(event as Map);
      try {
        final parsed = await Throw.parseNotification(
          title: data['title']?.toString() ?? '',
          message: data['text']?.toString() ?? '',
          packageName: data['packageName']?.toString() ?? '',
        );
        await DatabaseHelp.insertData(
          parsed['name']?.toString() ?? 'Unknown expense',
          int.tryParse(parsed['amount'].toString()) ?? 0,
          DateTime.now().toIso8601String().substring(0, 10),
          parsed['category']?.toString() ?? 'general',
          parsed['type']?.toString() ?? 'others',
        );
        await _onExpenseAdded?.call();
      } catch (error) {
        await _onError?.call(error.toString());
      }
    });
    await _methods.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}