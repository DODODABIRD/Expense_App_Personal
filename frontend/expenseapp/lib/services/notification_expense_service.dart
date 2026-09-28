import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'auth_service.dart';
import 'databaseHelper.dart';
import 'error_log_service.dart';
import 'local_notification_parser.dart';

class UnparseableNotificationException implements Exception {
  const UnparseableNotificationException();
}

class AiRequiredNotificationException implements Exception {
  const AiRequiredNotificationException();

  @override
  String toString() => 'Ambiguous transfer queued until AI can parse it';
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
  static const _pendingRetryInterval = Duration(minutes: 1);

  Future<void> Function(String)? _onError;
  Future<void> Function()? _onPendingNotificationAdded;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pendingRetryTimer;
  bool _isRetryingPendingNotifications = false;
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Read allowed notification apps');
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
    return Throw.updateAiNotificationReference();
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
    _recentDeduplication.removeWhere(
      (_, time) => now.difference(time) > _dedupDuration,
    );

    final key =
        '$packageName|${title.trim().toLowerCase()}|${text.trim().toLowerCase()}';
    if (_recentDeduplication.containsKey(key)) {
      return true;
    }
    _recentDeduplication[key] = now;
    return false;
  }

  Future<void> start(
    Future<void> Function(String)? onError, {
    Future<void> Function()? onPendingNotificationAdded,
  }) async {
    _onError = onError;
    if (onPendingNotificationAdded != null) {
      _onPendingNotificationAdded = onPendingNotificationAdded;
    }
    if (_started || !Platform.isAndroid) return;
    await _methods.invokeMethod<void>('setParserActive', {'active': true});
    await setAllowedApps(await getAllowedApps());
    _started = true;

    // Retry any notifications that were queued when offline
    unawaited(retryPendingCloudNotifications());
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = Timer.periodic(_pendingRetryInterval, (_) {
      unawaited(retryPendingCloudNotifications());
    });

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
      } catch (error, stackTrace) {
        if (error is! UnparseableNotificationException) {
          if (error is! AiRequiredNotificationException) {
            captureAppError(error, stackTrace, 'Process payment notification');
          }
          await _enqueuePendingCloudNotification({
            'title': title,
            'message': message,
            'packageName': packageName,
            'postTime': postTime.millisecondsSinceEpoch,
            'retryCount': 0,
            'aiRequired': error is AiRequiredNotificationException,
            'ownerId': AuthService.currentUser?.uid,
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
    bool aiRequired = false,
  }) async {
    Map<String, dynamic>? cloudParsed;
    Object? cloudError;
    try {
      cloudParsed = await _parseWithCloudParser(
        title: title,
        message: message,
        packageName: packageName,
      );
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Cloud notification parsing');
      cloudError = error;
    }

    if (cloudParsed != null) {
      await DatabaseHelp.insertPendingNotificationExpense(
        name: cloudParsed['name'] as String,
        amount: cloudParsed['amount'] as int,
        date: postTime.toIso8601String().substring(0, 10),
        category: cloudParsed['category'] as String,
        type: cloudParsed['type'] as String,
        sourceApp: packageName,
        receivedAt: postTime,
      );
      await _onPendingNotificationAdded?.call();
      return;
    }

    final localParsed = aiRequired
        ? null
        : LocalNotificationParser.parse(
            title: title,
            message: message,
            packageName: packageName,
            timestamp: postTime,
          );
    if (aiRequired ||
        LocalNotificationParser.isAmbiguousNotification(
          title,
          message,
          localParsed,
        )) {
      throw const AiRequiredNotificationException();
    }

    if (localParsed != null && localParsed.amount > 0) {
      final date =
          localParsed.date ?? postTime.toIso8601String().substring(0, 10);
      await DatabaseHelp.insertPendingNotificationExpense(
        name: localParsed.name,
        amount: localParsed.amount,
        date: date,
        category: localParsed.category,
        type: localParsed.type,
        sourceApp: packageName,
        receivedAt: postTime,
      );
      await _onPendingNotificationAdded?.call();
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

  Future<void> _enqueuePendingCloudNotification(
    Map<String, dynamic> item,
  ) async {
    try {
      final stored = await DatabaseHelp.getSetting(
        'pending_cloud_notifications',
      );
      List<dynamic> queue = [];
      if (stored != null) {
        try {
          queue = jsonDecode(stored) as List<dynamic>;
        } catch (error, stackTrace) {
          captureAppError(error, stackTrace, 'Read pending notification queue');
        }
      }
      // Keep ordinary transient failures bounded without evicting AI-required entries.
      if (queue.length >= 50) {
        final evictableIndex = queue.indexWhere(
          (queued) => queued is Map && queued['aiRequired'] != true,
        );
        if (evictableIndex >= 0) {
          queue.removeAt(evictableIndex);
        } else if (item['aiRequired'] != true) {
          return;
        }
      }
      queue.add(item);
      await DatabaseHelp.setSetting(
        'pending_cloud_notifications',
        jsonEncode(queue),
      );
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Store pending notification');
    }
  }

  /// Retries parsing any notifications that were queued while offline.
  Future<void> retryPendingCloudNotifications() async {
    if (_isRetryingPendingNotifications) return;
    _isRetryingPendingNotifications = true;
    try {
      final stored = await DatabaseHelp.getSetting(
        'pending_cloud_notifications',
      );
      if (stored == null) return;
      final queue = (jsonDecode(stored) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (queue.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];

      for (final item in queue) {
        final pendingOwnerId = item['ownerId']?.toString();
        final currentOwnerId = AuthService.currentUser?.uid;
        if (pendingOwnerId != null && pendingOwnerId != currentOwnerId) {
          remaining.add(item);
          continue;
        }

        final nextRetryAt = (item['nextRetryAt'] as num?)?.toInt() ?? 0;
        if (nextRetryAt > DateTime.now().millisecondsSinceEpoch) {
          remaining.add(item);
          continue;
        }

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
            aiRequired: item['aiRequired'] == true,
          );
        } on UnparseableNotificationException {
          // The notification was not an expense; it cannot succeed on retry.
        } catch (error, stackTrace) {
          if (error is! AiRequiredNotificationException) {
            captureAppError(error, stackTrace, 'Retry payment notification');
          }
          final retryCount = (item['retryCount'] as num?)?.toInt() ?? 0;
          final nextRetryCount = retryCount + 1;
          final mustKeepForAi =
              item['aiRequired'] == true ||
              error is AiRequiredNotificationException;
          if (mustKeepForAi || nextRetryCount < _maxCloudRetryAttempts) {
            remaining.add({
              ...item,
              'retryCount': nextRetryCount,
              'nextRetryAt': DateTime.now()
                  .add(_pendingRetryDelay(nextRetryCount))
                  .millisecondsSinceEpoch,
              if (mustKeepForAi) 'aiRequired': true,
            });
          }
        }
      }

      await DatabaseHelp.setSetting(
        'pending_cloud_notifications',
        jsonEncode(remaining),
      );
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Read pending notification queue');
    } finally {
      _isRetryingPendingNotifications = false;
    }
  }

  Duration _pendingRetryDelay(int retryCount) {
    if (retryCount >= 7) return const Duration(hours: 1);
    return Duration(minutes: 1 << (retryCount - 1));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = null;
    _started = false;
  }
}
