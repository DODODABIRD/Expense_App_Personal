import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'databaseHelper.dart';
import 'local_notification_parser.dart';

class NotificationExpenseService {
  NotificationExpenseService._();
  static final instance = NotificationExpenseService._();

  static const _methods = MethodChannel('expense_app/notifications');
  static const _events = EventChannel('expense_app/notification_events');
  static const allNotificationsKey = '__all_notifications__';

  static const supportedApps = <String, String>{
    'com.bca': 'BCA Mobile',
    'mybca': 'myBCA',
    'id.bmri.livin': 'Livin’ by Mandiri',
    'id.co.bni.newmobile': 'wondr by BNI',
    'com.bri.bmo': 'BRImo',
    'com.btpn.jenius': 'Jenius',
    'com.beepr.bank': 'SeaBank',
    'id.dana': 'DANA',
    'ovo.id': 'OVO',
    'com.gojek.app': 'GoPay / Gojek',
    'com.gopay.wallet': 'GoPay App',
    'com.shopee.id': 'Shopee / SPay',
    'com.grabtaxi.passenger': 'Grab',
    'com.tokopedia.tkpd': 'Tokopedia',
    'id.flip': 'Flip',
    'com.android.shell': 'Android Shell (debug)',
  };

  static final defaultAllowedApps = supportedApps.keys.toSet();

  static const _validCategories = <String>{
    'makanan',
    'transportasi',
    'hiburan',
    'school supply',
    'baju',
    'elektronik',
    'kesehatan',
    'lainnya',
  };

  final Map<String, DateTime> _recentDeduplication = {};
  static const Duration _dedupDuration = Duration(minutes: 5);

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

  bool _isDuplicate(String packageName, String title, String text) {
    final now = DateTime.now();
    _recentDeduplication.removeWhere((_, time) => now.difference(time) > _dedupDuration);

    final key = '$packageName|${title.trim().toLowerCase()}|${text.trim().toLowerCase()}';
    if (_recentDeduplication.containsKey(key)) {
      return true;
    }
    _recentDeduplication[key] = now;
    return false;
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
      final title = data['title']?.toString() ?? '';
      final message = data['text']?.toString() ?? '';
      final packageName = data['packageName']?.toString() ?? '';
      final postTimeRaw = data['postTime'];
      final postTime = postTimeRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(postTimeRaw)
          : DateTime.now();

      // 1. Noise check (drop promo, discount, OTP, security verification)
      if (LocalNotificationParser.isIgnoredNoise(title, message)) {
        return;
      }

      // 2. Income / top-up filter (do not record as expense)
      if (LocalNotificationParser.isIncomeTransaction(title, message)) {
        return;
      }

      // 3. Deduplication check (drop repeat notification triggers)
      if (_isDuplicate(packageName, title, message)) {
        return;
      }

      try {
        // 4. Try Fast Local Offline Regex Parser first
        final localParsed = LocalNotificationParser.parse(
          title: title,
          message: message,
          packageName: packageName,
          timestamp: postTime,
        );

        if (localParsed != null && localParsed.amount > 0) {
          final date = localParsed.date ?? postTime.toIso8601String().substring(0, 10);
          await DatabaseHelp.insertData(
            localParsed.name,
            localParsed.amount,
            date,
            localParsed.category,
            localParsed.type,
          );
          await _onExpenseAdded?.call();
          return;
        }

        // 5. Fallback to Cloud AI Parser when local regex did not recognize the pattern
        final cloudParsed = await Throw.parseNotification(
          title: title,
          message: message,
          packageName: packageName,
        );

        final amount = int.tryParse(cloudParsed['amount']?.toString() ?? '') ?? 0;
        final name = (cloudParsed['name']?.toString() ?? '').trim();

        // Enforce valid expense amount and name
        if (amount <= 0 || name.isEmpty) {
          return;
        }

        final rawCategory = cloudParsed['category']?.toString().toLowerCase() ?? 'lainnya';
        final category = _validCategories.contains(rawCategory) ? rawCategory : 'lainnya';
        final rawType = cloudParsed['type']?.toString().toLowerCase() ?? 'unexpected';
        final type = (rawType == 'expected' || rawType == 'unexpected') ? rawType : 'unexpected';
        final date = cloudParsed['date']?.toString() ?? postTime.toIso8601String().substring(0, 10);

        await DatabaseHelp.insertData(
          name,
          amount,
          date,
          category,
          type,
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