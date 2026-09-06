import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'ApiService.dart';
import 'databaseHelper.dart';

class NotificationExpenseService {
  NotificationExpenseService._();
  static final instance = NotificationExpenseService._();

  static const _methods = MethodChannel('expense_app/notifications');
  static const _events = EventChannel('expense_app/notification_events');
  Future<void> Function(String)? _onError;
  Future<void> Function()? _onExpenseAdded;
  bool _started = false;

  Future<bool> isEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _methods.invokeMethod<bool>('isEnabled') ?? false;
  }

  Future<void> openAccessSettings() async {
    if (Platform.isAndroid) await _methods.invokeMethod<void>('openSettings');
  }

  Future<void> start(
    Future<void> Function(String)? onError, {
    Future<void> Function()? onExpenseAdded,
  }) async {
    _onError = onError;
    _onExpenseAdded = onExpenseAdded;
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _events.receiveBroadcastStream().listen((event) async {
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
}