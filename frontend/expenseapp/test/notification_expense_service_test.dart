import 'package:flutter_test/flutter_test.dart';
import 'package:expenseapp/services/notification_expense_service.dart';

void main() {
  group('buildAiNotificationReferenceItems', () {
    test('prefers local edits for mirrored cloud expenses', () {
      final items =
          NotificationExpenseService.buildAiNotificationReferenceItems(
            localExpenses: [
              {
                'id': 7,
                'name': 'Updated shop name',
                'amount': 42000,
              },
            ],
            onlineExpenses: [
              {
                'localId': '7',
                'name': 'Old shop name',
                'amount': 40000,
              },
            ],
          );

      expect(items, [
        {'expenseitem': 'Updated shop name', 'expenseprice': 42000},
      ]);
    });

    test('keeps separate purchases with the same name and price', () {
      final items =
          NotificationExpenseService.buildAiNotificationReferenceItems(
            localExpenses: [
              {'id': 1, 'name': 'Coffee', 'amount': 25000},
              {'id': 2, 'name': 'Coffee', 'amount': 25000},
            ],
            onlineExpenses: [
              {
                'localId': '3',
                'name': 'Coffee',
                'amount': 25000,
              },
            ],
          );

      expect(items, hasLength(3));
      expect(
        items,
        everyElement({'expenseitem': 'Coffee', 'expenseprice': 25000}),
      );
    });

    test('keeps local expense details for the AI template', () {
      final items =
          NotificationExpenseService.buildAiNotificationReferenceItems(
            localExpenses: [
              {
                'id': 1,
                'name': 'Kopi',
                'amount': 25000,
                'category': 'makanan',
                'type': 'expected',
                'date': '2026-11-16',
              },
            ],
            onlineExpenses: const [],
          );

      expect(items, [
        {
          'expenseitem': 'Kopi',
          'expenseprice': 25000,
          'category': 'makanan',
          'type': 'expected',
          'date': '2026-11-16',
        },
      ]);
    });
  });

  group('notificationKeyFor', () {
    final time = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('is stable for the same notification', () {
      String key() => NotificationExpenseService.notificationKeyFor(
        packageName: 'com.bca',
        title: 'BCA',
        message: 'Pembayaran Rp 25.000',
        postTime: time,
      );
      expect(key(), key());
    });

    test('differs when the text or time differs', () {
      final base = NotificationExpenseService.notificationKeyFor(
        packageName: 'com.bca',
        title: 'BCA',
        message: 'Pembayaran Rp 25.000',
        postTime: time,
      );
      expect(
        NotificationExpenseService.notificationKeyFor(
          packageName: 'com.bca',
          title: 'BCA',
          message: 'Pembayaran Rp 30.000',
          postTime: time,
        ),
        isNot(base),
      );
      expect(
        NotificationExpenseService.notificationKeyFor(
          packageName: 'com.bca',
          title: 'BCA',
          message: 'Pembayaran Rp 25.000',
          postTime: time.add(const Duration(seconds: 1)),
        ),
        isNot(base),
      );
    });
  });

  group('isPlaceholderName', () {
    test('treats empty and backend fallback names as placeholders', () {
      expect(NotificationExpenseService.isPlaceholderName(''), isTrue);
      expect(NotificationExpenseService.isPlaceholderName('  '), isTrue);
      expect(
        NotificationExpenseService.isPlaceholderName('Unknown expense'),
        isTrue,
      );
      expect(NotificationExpenseService.isPlaceholderName('Kopi'), isFalse);
    });
  });

  group('supported notification apps', () {
    test('includes every BCA app package variant', () {
      expect(
        NotificationExpenseService.supportedApps.keys,
        containsAll([
          'com.bca',
          'com.mybca',
          'com.bca.mybca.omni.android',
        ]),
      );
      expect(
        NotificationExpenseService.supportedApps.containsKey('mybca'),
        isFalse,
      );
    });
  });
}
