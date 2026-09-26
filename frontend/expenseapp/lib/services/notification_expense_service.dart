import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'databaseHelper.dart';
import 'local_notification_parser.dart';

class UnparseableNotificationException implements Exception {
  const UnparseableNotificationException();
}

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
    'src.com.bni': 'BNI Mobile',
    'com.bri.bmo': 'BRImo',
    'com.jago.app': 'Bank Jago',
    'com.btpn.jenius': 'Jenius BTPN',
    'com.beepr.bank': 'SeaBank',
    'com.bsi.mobile': 'BSI Mobile',
    'id.co.btn.mobile': 'BTN Mobile',
    'com.cimbniaga.octomobile': 'CIMB OCTO Mobile',
    'com.permatabank.mobile': 'PermataME',
    'com.danamon.dbank': 'Danamon D-Bank',
    'id.dana': 'DANA',
    'ovo.id': 'OVO',
    'com.gojek.app': 'GoPay / Gojek',
    'com.gopay.wallet': 'GoPay App',
    'com.shopee.id': 'Shopee / SPay',
    'com.grabtaxi.passenger': 'Grab',
    'com.tokopedia.tkpd': 'Tokopedia',
    'id.flip': 'Flip',
    'com.telkom.mwallet': 'LinkAja',
    'com.finaccel.android': 'Kredivo',
    'com.akulaku.android': 'Akulaku',
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
  static const _maxCloudRetryAttempts = 3;

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

  Future<int> updateAiNotificationReference() async {
    final onlineExpenses = await Throw.getOnlineExpenses();
    final localExpenses = await DatabaseHelp.getData();
    final items = buildAiNotificationReferenceItems(
      localExpenses: localExpenses,
      onlineExpenses: onlineExpenses,
    );
    return Throw.updateAiNotificationReference(items);
  }

  static List<Map<String, dynamic>> buildAiNotificationReferenceItems({
    required List<Map<String, dynamic>> localExpenses,
    required List<Map<String, dynamic>> onlineExpenses,
  }) {
    final items = <Map<String, dynamic>>[];
    final knownIds = <String>{};

    for (final expense in localExpenses) {
      final ids = <String>[
        if (expense['mongoId'] != null) 'mongo:${expense['mongoId']}',
        if (expense['id'] != null) 'local:${expense['id']}',
      ];
      final item = _toAiReferenceItem(expense);
      if (item == null || ids.any(knownIds.contains)) continue;
      knownIds.addAll(ids);
      items.add(item);
    }

    for (final expense in onlineExpenses) {
      final ids = <String>[
        if (expense['_id'] != null) 'mongo:${expense['_id']}',
        if (expense['localId'] != null) 'local:${expense['localId']}',
      ];
      if (ids.any(knownIds.contains)) continue;
      final item = _toAiReferenceItem(expense);
      if (item == null) continue;
      knownIds.addAll(ids);
      items.add(item);
    }

    return items;
  }

  static Map<String, dynamic>? _toAiReferenceItem(
    Map<String, dynamic> expense,
  ) {
    final name = expense['name']?.toString().trim() ?? '';
    final rawAmount = expense['amount'];
    final amount = rawAmount is num
        ? rawAmount.round()
        : int.tryParse(rawAmount?.toString() ?? '');
    if (name.isEmpty || amount == null || amount <= 0) return null;
    return {'expenseitem': name, 'expenseprice': amount};
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

    // Retry any notifications that were queued when offline
    unawaited(retryPendingCloudNotifications());

    _subscription = _events.receiveBroadcastStream().listen((event) async {
      final data = Map<String, dynamic>.from(event as Map);
      final title = data['title']?.toString() ?? '';
      final message = data['text']?.toString() ?? '';
      final packageName = data['packageName']?.toString() ?? '';
      final postTimeRaw = data['postTime'];
      final postTime = postTimeRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(postTimeRaw)
          : DateTime.now();

      // 1. Noise check
      if (LocalNotificationParser.isIgnoredNoise(title, message)) {
        return;
      }

      // 2. Income / top-up filter
      if (LocalNotificationParser.isIncomeTransaction(title, message)) {
        return;
      }

      // 3. Deduplication check
      if (_isDuplicate(packageName, title, message)) {
        return;
      }

      try {
        await _processNotification(
          title: title,
          message: message,
          packageName: packageName,
          postTime: postTime,
        );
      } catch (error) {
        if (error is! UnparseableNotificationException) {
          await _enqueuePendingCloudNotification({
            'title': title,
            'message': message,
            'packageName': packageName,
            'postTime': postTime.millisecondsSinceEpoch,
            'retryCount': 0,
          });
        }
        await _onError?.call(error.toString());
      }
    });

    await _methods.invokeMethod<void>('start');
  }

  Future<void> _processNotification({
    required String title,
    required String message,
    required String packageName,
    required DateTime postTime,
  }) async {
    Map<String, dynamic>? cloudParsed;
    Object? cloudError;
    try {
      cloudParsed = await _parseWithCloudParser(
        title: title,
        message: message,
        packageName: packageName,
      );
    } catch (error) {
      cloudError = error;
    }

    if (cloudParsed != null) {
      await DatabaseHelp.insertData(
        cloudParsed['name'] as String,
        cloudParsed['amount'] as int,
        postTime.toIso8601String().substring(0, 10),
        cloudParsed['category'] as String,
        cloudParsed['type'] as String,
      );
      await _onExpenseAdded?.call();
      return;
    }

    final localParsed = LocalNotificationParser.parse(
      title: title,
      message: message,
      packageName: packageName,
      timestamp: postTime,
    );
    if (localParsed != null && localParsed.amount > 0) {
      final date =
          localParsed.date ?? postTime.toIso8601String().substring(0, 10);
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

    if (cloudError != null) throw cloudError;
    throw const UnparseableNotificationException();
  }

  Future<Map<String, dynamic>?> _parseWithCloudParser({
    required String title,
    required String message,
    required String packageName,
  }) async {
    final cloudParsed = await Throw.parseNotification(
      title: title,
      message: message,
      packageName: packageName,
    );
    final rawAmount = cloudParsed['amount'];
    final amount = rawAmount is num
        ? rawAmount.round()
        : int.tryParse(rawAmount?.toString() ?? '') ?? 0;
    final name = (cloudParsed['name']?.toString() ?? '').trim();
    if (amount <= 0 || name.isEmpty) return null;

    final rawCategory =
        cloudParsed['category']?.toString().toLowerCase() ?? 'lainnya';
    final category = _validCategories.contains(rawCategory)
        ? rawCategory
        : 'lainnya';
    final rawType =
        cloudParsed['type']?.toString().toLowerCase() ?? 'unexpected';
    final type = (rawType == 'expected' || rawType == 'unexpected')
        ? rawType
        : 'unexpected';
    return {'name': name, 'amount': amount, 'category': category, 'type': type};
  }

  Future<void> _enqueuePendingCloudNotification(Map<String, dynamic> item) async {
    try {
      final stored = await DatabaseHelp.getSetting('pending_cloud_notifications');
      List<dynamic> queue = [];
      if (stored != null) {
        try {
          queue = jsonDecode(stored) as List<dynamic>;
        } catch (_) {}
      }
      // Keep at most 50 pending notifications
      if (queue.length >= 50) {
        queue.removeAt(0);
      }
      queue.add(item);
      await DatabaseHelp.setSetting('pending_cloud_notifications', jsonEncode(queue));
    } catch (_) {}
  }

  /// Retries parsing any notifications that were queued while offline.
  Future<void> retryPendingCloudNotifications() async {
    try {
      final stored = await DatabaseHelp.getSetting('pending_cloud_notifications');
      if (stored == null) return;
      final queue = (jsonDecode(stored) as List<dynamic>).cast<Map<String, dynamic>>();
      if (queue.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];

      for (final item in queue) {
        try {
          final title = item['title']?.toString() ?? '';
          final message = item['message']?.toString() ?? '';
          final packageName = item['packageName']?.toString() ?? '';
          final postTimeRaw = item['postTime'];
          final postTime = postTimeRaw is int
              ? DateTime.fromMillisecondsSinceEpoch(postTimeRaw)
              : DateTime.now();

          await _processNotification(
            title: title,
            message: message,
            packageName: packageName,
            postTime: postTime,
          );
        } on UnparseableNotificationException {
          // The notification was not an expense; it cannot succeed on retry.
        } catch (_) {
          final retryCount = (item['retryCount'] as num?)?.toInt() ?? 0;
          if (retryCount + 1 < _maxCloudRetryAttempts) {
            remaining.add({...item, 'retryCount': retryCount + 1});
          }
        }
      }

      await DatabaseHelp.setSetting('pending_cloud_notifications', jsonEncode(remaining));
    } catch (_) {}
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
