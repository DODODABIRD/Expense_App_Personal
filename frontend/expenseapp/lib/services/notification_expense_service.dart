import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'auth_service.dart';
import 'databaseHelper.dart';
import 'error_log_service.dart';
import 'local_notification_parser.dart';

class NotificationExpenseService {
  NotificationExpenseService._();
  static final instance = NotificationExpenseService._();

  static const _methods = MethodChannel('expense_app/notifications');
  static const _events = EventChannel('expense_app/notification_events');
  static const allNotificationsKey = '__all_notifications__';

  static const supportedApps = <String, String>{
    'com.bca': 'BCA Mobile',
    'com.mybca': 'myBCA',
    'com.bca.mybca.omni.android': 'myBCA (Play Store)',
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

  static const needsInputName = 'Perlu dilengkapi';
  static const _legacyQueueKey = 'pending_cloud_notifications';
  static const _maxAiAttempts = 6;
  static const _pendingRetryInterval = Duration(minutes: 1);

  Future<void> Function(String)? _onError;
  Future<void> Function()? _onPendingNotificationAdded;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pendingRetryTimer;
  bool _isDraining = false;
  bool _drainAgain = false;
  bool _isEnriching = false;
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
    final localExpenses = await DatabaseHelp.getData();
    List<Map<String, dynamic>> onlineExpenses = const [];
    try {
      onlineExpenses = await Throw.getOnlineExpenses();
    } catch (error, stackTrace) {
      // Local expenses are enough to build the reference, so keep going offline.
      captureAppError(
        error,
        stackTrace,
        'Load online expenses for AI reference',
      );
    }
    final items = buildAiNotificationReferenceItems(
      localExpenses: localExpenses,
      onlineExpenses: onlineExpenses,
    );
    return Throw.saveAiNotificationReference(items);
  }

  static List<Map<String, dynamic>> buildAiNotificationReferenceItems({
    required List<Map<String, dynamic>> localExpenses,
    required List<Map<String, dynamic>> onlineExpenses,
  }) {
    final items = <Map<String, dynamic>>[];
    final knownIds = <String>{};

    for (final expense in localExpenses) {
      final ids = <String>[
        if (expense['id'] != null) 'local:${expense['id']}',
      ];
      final item = _toAiReferenceItem(expense);
      if (item == null || ids.any(knownIds.contains)) continue;
      knownIds.addAll(ids);
      items.add(item);
    }

    for (final expense in onlineExpenses) {
      final ids = <String>[
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
    final item = <String, dynamic>{'expenseitem': name, 'expenseprice': amount};
    for (final field in ['category', 'type', 'date']) {
      final value = expense[field]?.toString().trim();
      if (value != null && value.isNotEmpty) item[field] = value;
    }
    return item;
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

  /// Stable identity of a notification, so a redelivery never creates a
  /// second draft (the DB has a unique index on it).
  static String notificationKeyFor({
    required String packageName,
    required String title,
    required String message,
    required DateTime postTime,
  }) {
    return '$packageName|${postTime.millisecondsSinceEpoch}|'
        '${'$title\u0000$message'.hashCode}';
  }

  /// A name the backend uses when the AI found none; never worth showing.
  static bool isPlaceholderName(String name) {
    final lower = name.trim().toLowerCase();
    return lower.isEmpty || lower == 'unknown expense';
  }

  Future<void> start(
    Future<void> Function(String)? onError, {
    Future<void> Function()? onPendingNotificationAdded,
  }) async {
    _onError = onError;
    if (onPendingNotificationAdded != null) {
      _onPendingNotificationAdded = onPendingNotificationAdded;
    }
    if (!Platform.isAndroid) return;

    // Re-apply native settings on every call. The listener service may have
    // been (re)created after the last call, and its SharedPreferences are the
    // only state it reads on startup.
    await _methods.invokeMethod<void>('setParserActive', {'active': true});
    await setAllowedApps(await getAllowedApps());

    if (_started) {
      unawaited(processPending());
      return;
    }
    _started = true;

    _pendingRetryTimer?.cancel();
    _pendingRetryTimer = Timer.periodic(_pendingRetryInterval, (_) {
      unawaited(processPending());
    });

    // Events are only a "something arrived" hint. The durable source of truth
    // is the native queue, drained below.
    _subscription = _events.receiveBroadcastStream().listen((_) {
      unawaited(processPending());
    });

    await _methods.invokeMethod<void>('start');
    unawaited(processPending());
  }

  /// Moves native notifications into drafts, then lets the AI improve them.
  Future<void> processPending() async {
    await _drainNativeQueue();
    await _enrichPendingWithAi();
  }

  Future<void> _drainNativeQueue() async {
    if (_isDraining) {
      _drainAgain = true;
      return;
    }
    _isDraining = true;
    try {
      do {
        _drainAgain = false;
        await _migrateLegacyQueue();
        await _drainNativeQueueOnce();
      } while (_drainAgain);
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Drain notification queue');
      await _onError?.call(error.toString());
    } finally {
      _isDraining = false;
    }
  }

  Future<void> _drainNativeQueueOnce() async {
    // Without a signed-in user there is nowhere to store a draft: leave the
    // notifications in the native queue until login.
    if (AuthService.currentUser == null || !Platform.isAndroid) return;

    final raw =
        await _methods.invokeMethod<List<dynamic>>('takePending') ?? const [];
    if (raw.isEmpty) return;

    final ackKeys = <String>[];
    var added = false;
    for (final entry in raw) {
      final data = Map<String, dynamic>.from(entry as Map);
      final title = data['title']?.toString() ?? '';
      final message = data['text']?.toString() ?? '';
      final packageName = data['packageName']?.toString() ?? '';
      final postTimeRaw = data['postTime'];
      final postTime = postTimeRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(postTimeRaw.toInt())
          : DateTime.now();
      var key = data['key']?.toString() ?? '';
      if (key.isEmpty) {
        key = notificationKeyFor(
          packageName: packageName,
          title: title,
          message: message,
          postTime: postTime,
        );
      }

      try {
        final inserted = await _storeNotification(
          title: title,
          message: message,
          packageName: packageName,
          postTime: postTime,
          key: key,
        );
        added = added || inserted;
        ackKeys.add(key);
      } catch (error, stackTrace) {
        // Not acked: it stays in the native queue and is retried next drain.
        captureAppError(error, stackTrace, 'Store payment notification');
        await _onError?.call(error.toString());
      }
    }

    if (ackKeys.isNotEmpty) {
      await _methods.invokeMethod<void>('ack', {'keys': ackKeys});
    }
    if (added) await _onPendingNotificationAdded?.call();
  }

  /// Saves one notification as a pending draft. Returns true when a new draft
  /// was created. Noise and income are dropped on purpose (returns false).
  Future<bool> _storeNotification({
    required String title,
    required String message,
    required String packageName,
    required DateTime postTime,
    required String key,
  }) async {
    if (LocalNotificationParser.isIgnoredNoise(title, message)) return false;
    if (LocalNotificationParser.isIncomeTransaction(title, message)) {
      return false;
    }

    final local = LocalNotificationParser.parse(
      title: title,
      message: message,
      packageName: packageName,
      timestamp: postTime,
    );
    final hasAmount = local != null && local.amount > 0;

    final id = await DatabaseHelp.insertPendingNotificationExpense(
      name: hasAmount ? local.name : needsInputName,
      amount: hasAmount ? local.amount : 0,
      date:
          (hasAmount ? local.date : null) ??
          postTime.toIso8601String().substring(0, 10),
      category: hasAmount ? local.category : 'lainnya',
      type: hasAmount ? local.type : 'unexpected',
      sourceApp: packageName,
      receivedAt: postTime,
      rawTitle: title,
      rawText: message,
      notificationKey: key,
      status: hasAmount ? 'ready' : 'needs_input',
      aiStatus: 'pending',
    );
    return id > 0;
  }

  /// Improves name/category/type (and the amount of "needs input" drafts)
  /// with the cloud parser. A failure never removes the draft.
  Future<void> _enrichPendingWithAi() async {
    if (_isEnriching || AuthService.currentUser == null) return;
    _isEnriching = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await DatabaseHelp.getPendingAiEnrichment(now);
      var changed = false;

      for (final row in rows) {
        final id = row['id'] as int;
        final attempts = (row['aiAttempts'] as num?)?.toInt() ?? 0;
        try {
          final parsed = await _parseWithCloudParser(
            title: row['rawTitle']?.toString() ?? '',
            message: row['rawText']?.toString() ?? '',
            packageName: row['sourceApp']?.toString() ?? '',
          );
          if (parsed == null) {
            // The AI answered but found no amount: keep the local draft as is.
            await DatabaseHelp.markPendingAiAttemptFailed(
              id: id,
              attempts: attempts + 1,
              nextRetryAtMs: 0,
              giveUp: true,
            );
            continue;
          }
          final aiName = parsed['name'] as String;
          final applied = await DatabaseHelp.applyAiEnrichment(
            id: id,
            name: isPlaceholderName(aiName)
                ? (row['name']?.toString() ?? needsInputName)
                : aiName,
            amount: parsed['amount'] as int,
            category: parsed['category'] as String,
            type: parsed['type'] as String,
          );
          changed = changed || applied;
        } catch (error, stackTrace) {
          captureAppError(error, stackTrace, 'Cloud notification parsing');
          final next = attempts + 1;
          await DatabaseHelp.markPendingAiAttemptFailed(
            id: id,
            attempts: next,
            nextRetryAtMs: DateTime.now()
                .add(_pendingRetryDelay(next))
                .millisecondsSinceEpoch,
            giveUp: next >= _maxAiAttempts,
          );
        }
      }

      if (changed) await _onPendingNotificationAdded?.call();
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Enrich pending notifications');
    } finally {
      _isEnriching = false;
    }
  }

  /// Returns null when the AI found no usable amount. A placeholder name is
  /// returned as an empty string so callers keep the local one.
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
    if (amount <= 0) return null;

    final rawName = (cloudParsed['name']?.toString() ?? '').trim();
    final name = isPlaceholderName(rawName) ? '' : rawName;
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

  /// One-time move of the old JSON retry queue (`pending_cloud_notifications`)
  /// into drafts, so nothing queued by an older version is lost.
  Future<void> _migrateLegacyQueue() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    try {
      final stored = await DatabaseHelp.getSetting(_legacyQueueKey);
      if (stored == null || stored == '[]') return;
      final queue = (jsonDecode(stored) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final remaining = <Map<String, dynamic>>[];
      var added = false;
      for (final item in queue) {
        final ownerId = item['ownerId']?.toString();
        if (ownerId != null && ownerId != uid) {
          remaining.add(item);
          continue;
        }
        final title = item['title']?.toString() ?? '';
        final message = item['message']?.toString() ?? '';
        final packageName = item['packageName']?.toString() ?? '';
        final postTimeRaw = item['postTime'];
        final postTime = postTimeRaw is num
            ? DateTime.fromMillisecondsSinceEpoch(postTimeRaw.toInt())
            : DateTime.now();
        try {
          added =
              await _storeNotification(
                title: title,
                message: message,
                packageName: packageName,
                postTime: postTime,
                key: notificationKeyFor(
                  packageName: packageName,
                  title: title,
                  message: message,
                  postTime: postTime,
                ),
              ) ||
              added;
        } catch (error, stackTrace) {
          captureAppError(error, stackTrace, 'Migrate pending notification');
          remaining.add(item);
        }
      }

      await DatabaseHelp.setSetting(_legacyQueueKey, jsonEncode(remaining));
      if (added) await _onPendingNotificationAdded?.call();
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Read legacy notification queue');
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
