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
                'mongoId': 'mongo-7',
                'name': 'Updated shop name',
                'amount': 42000,
              },
            ],
            onlineExpenses: [
              {
                '_id': 'mongo-7',
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
                '_id': 'mongo-3',
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
  });
}
