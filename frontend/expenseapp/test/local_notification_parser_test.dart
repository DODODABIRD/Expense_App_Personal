import 'package:flutter_test/flutter_test.dart';
import 'package:expenseapp/services/local_notification_parser.dart';

void main() {
  group('LocalNotificationParser', () {
    test('Noise & Promo detection', () {
      expect(
        LocalNotificationParser.isIgnoredNoise(
          'Diskon 50% Akhir Pekan!',
          'Dapatkan cashback hingga Rp50.000 untuk transaksi berikutnya.',
        ),
        isTrue,
      );

      expect(
        LocalNotificationParser.isIgnoredNoise(
          'Kode OTP BCA',
          'Jangan berikan kode OTP 839201 kepada siapapun termasuk pihak bank.',
        ),
        isTrue,
      );

      expect(
        LocalNotificationParser.isIncomeTransaction(
          'Transfer Masuk',
          'Kamu menerima transfer masuk sebesar Rp 250.000 dari BUDI.',
        ),
        isTrue,
      );

      expect(
        LocalNotificationParser.isIncomeTransaction(
          'Top Up Berhasil',
          'Top up saldo berhasil Rp 100.000 via BCA.',
        ),
        isTrue,
      );
    });

    test('GoPay notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'Transaksi Berhasil',
        message: 'Kamu telah membayar Rp25.000 ke Kopi Kenangan',
        packageName: 'com.gojek.app',
      );
      expect(res, isNotNull);
      expect(res!.amount, 25000);
      expect(res.name, contains('Kopi Kenangan'));
      expect(res.category, 'makanan');
    });

    test('DANA notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'Pembayaran Berhasil',
        message: 'Pembayaran berhasil! Kamu telah bayar Rp50.000 di Alfamart',
        packageName: 'id.dana',
      );
      expect(res, isNotNull);
      expect(res!.amount, 50000);
      expect(res.name, contains('Alfamart'));
      expect(res.category, 'makanan');
    });

    test('OVO notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'OVO Cash',
        message: 'Berhasil bayar Rp 45.000 di GrabFood',
        packageName: 'ovo.id',
      );
      expect(res, isNotNull);
      expect(res!.amount, 45000);
      expect(res.name, contains('GrabFood'));
      expect(res.category, 'makanan');
    });

    test('BCA QRIS notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'BCA mobile',
        message: 'Pembayaran QRIS sebesar Rp 75.000 di Solaria berhasil',
        packageName: 'com.bca',
      );
      expect(res, isNotNull);
      expect(res!.amount, 75000);
      expect(res.name, contains('Solaria'));
      expect(res.category, 'makanan');
    });

    test('Mandiri Livin notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'Livin by Mandiri',
        message: 'Pembayaran QRIS sebesar Rp 35.000 di SPBU Shell berhasil',
        packageName: 'id.bmri.livin',
      );
      expect(res, isNotNull);
      expect(res!.amount, 35000);
      expect(res.name, contains('SPBU Shell'));
      expect(res.category, 'transportasi');
    });

    test('ShopeePay notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'ShopeePay',
        message: 'Pembayaran sebesar Rp 18.000 berhasil di Mixue',
        packageName: 'com.shopee.id',
      );
      expect(res, isNotNull);
      expect(res!.amount, 18000);
      expect(res.name, contains('Mixue'));
    });

    test('Generic notification parsing with thousand separators', () {
      final res = LocalNotificationParser.parse(
        title: 'Pembayaran Berhasil',
        message: 'Pembayaran transaksi debit Rp 1.250.000 di iBox berhasil',
        packageName: 'com.example.bank',
      );
      expect(res, isNotNull);
      expect(res!.amount, 1250000);
      expect(res.category, 'elektronik');
    });
  });
}
