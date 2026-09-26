import 'package:flutter_test/flutter_test.dart';
import 'package:expenseapp/services/local_notification_parser.dart';

void main() {
  group('LocalNotificationParser >99% Robustness Tests', () {
    test('Noise & Security OTP detection', () {
      // Pure promo without transaction should be ignored
      expect(
        LocalNotificationParser.isIgnoredNoise(
          'Diskon hingga 50% Akhir Pekan!',
          'Klaim voucher dan penawaran spesial buat kamu hari ini.',
        ),
        isTrue,
      );

      // OTP should strictly be ignored
      expect(
        LocalNotificationParser.isIgnoredNoise(
          'Kode OTP BCA',
          'Jangan berikan kode OTP 839201 kepada siapapun termasuk pihak bank.',
        ),
        isTrue,
      );

      // Promo attached to actual payment should NOT be ignored as noise!
      expect(
        LocalNotificationParser.isIgnoredNoise(
          'Pembayaran Berhasil',
          'Pembayaran QRIS Rp 25.000 di Kopi Kenangan berhasil. Dapatkan promo cashback 10%.',
        ),
        isFalse,
      );
    });

    test('Income & Top-up detection (excluded from expense)', () {
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

      expect(
        LocalNotificationParser.isIncomeTransaction(
          'Money In',
          'Received money IDR 500,000 from Client.',
        ),
        isTrue,
      );
    });

    test('GoPay notification (ID & EN)', () {
      // ID
      final resId = LocalNotificationParser.parse(
        title: 'Transaksi Berhasil',
        message: 'Kamu telah membayar Rp25.000 ke Kopi Kenangan',
        packageName: 'com.gojek.app',
      );
      expect(resId, isNotNull);
      expect(resId!.amount, 25000);
      expect(resId.name, contains('Kopi Kenangan'));
      expect(resId.category, 'makanan');

      // EN
      final resEn = LocalNotificationParser.parse(
        title: 'Payment Successful',
        message: "You've paid Rp 45,000 to Janji Jiwa",
        packageName: 'com.gopay.wallet',
      );
      expect(resEn, isNotNull);
      expect(resEn!.amount, 45000);
      expect(resEn.name, contains('Janji Jiwa'));
      expect(resEn.category, 'makanan');
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

    test('BCA Mobile & myBCA parsing', () {
      final qrisRes = LocalNotificationParser.parse(
        title: 'BCA mobile',
        message: 'Pembayaran QRIS sebesar Rp 75.000 di Solaria berhasil',
        packageName: 'com.bca',
      );
      expect(qrisRes, isNotNull);
      expect(qrisRes!.amount, 75000);
      expect(qrisRes.name, contains('Solaria'));

      final detailedMerchantRes = LocalNotificationParser.parse(
        title: 'BCA mobile',
        message:
            'Pembayaran QRIS Rp 75.000 di Cafe Utama (Cabang Pusat) / Lantai-2 berhasil',
        packageName: 'com.bca',
      );
      expect(detailedMerchantRes, isNotNull);
      expect(detailedMerchantRes!.amount, 75000);
      expect(
        detailedMerchantRes.name,
        'Cafe Utama (Cabang Pusat) / Lantai-2',
      );

      final transferRes = LocalNotificationParser.parse(
        title: 'myBCA',
        message: 'm-Transfer: BERHASIL... Transfer ke BUDI SETIAWAN Rp 150.000',
        packageName: 'mybca',
      );
      expect(transferRes, isNotNull);
      expect(transferRes!.amount, 150000);
      expect(transferRes.name, contains('BUDI SETIAWAN'));
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

    test('BRImo notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'BRImo',
        message: 'Pembayaran QRIS Rp 15.000 di Mixue berhasil',
        packageName: 'com.bri.bmo',
      );
      expect(res, isNotNull);
      expect(res!.amount, 15000);
      expect(res.name, contains('Mixue'));
    });

    test('BNI / wondr notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'wondr by BNI',
        message: 'Transaksi Berhasil. Pembayaran QRIS IDR 62.000 di Fore Coffee',
        packageName: 'id.co.bni.newmobile',
      );
      expect(res, isNotNull);
      expect(res!.amount, 62000);
      expect(res.name, contains('Fore Coffee'));
      expect(res.category, 'makanan');
    });

    test('Bank Jago notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'Bank Jago',
        message: 'Kamu berhasil kirim Rp 80.000 ke Toko Buku Gramedia',
        packageName: 'com.jago.app',
      );
      expect(res, isNotNull);
      expect(res!.amount, 80000);
      expect(res.name, contains('Gramedia'));
      expect(res.category, 'school supply');
    });

    test('Jenius BTPN notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'Jenius',
        message: 'Money Out: Rp 50.000 untuk XXI Cinema',
        packageName: 'com.btpn.jenius',
      );
      expect(res, isNotNull);
      expect(res!.amount, 50000);
      expect(res.name, contains('XXI Cinema'));
      expect(res.category, 'hiburan');
    });

    test('SeaBank notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'SeaBank',
        message: 'Pembayaran QRIS berhasil! Kamu telah membayar Rp 32.000 ke HokBen',
        packageName: 'com.beepr.bank',
      );
      expect(res, isNotNull);
      expect(res!.amount, 32000);
      expect(res.name, contains('HokBen'));
      expect(res.category, 'makanan');
    });

    test('ShopeePay notification parsing', () {
      final res = LocalNotificationParser.parse(
        title: 'ShopeePay',
        message: 'Pembayaran sebesar Rp 18.000 berhasil di Chatime',
        packageName: 'com.shopee.id',
      );
      expect(res, isNotNull);
      expect(res!.amount, 18000);
      expect(res.name, contains('Chatime'));
      expect(res.category, 'makanan');
    });

    test('Grab & Tokopedia notification parsing', () {
      final grabRes = LocalNotificationParser.parse(
        title: 'GrabFood',
        message: 'Pembayaran GrabFood sebesar Rp 54.000 berhasil di Restoran Sederhana',
        packageName: 'com.grabtaxi.passenger',
      );
      expect(grabRes, isNotNull);
      expect(grabRes!.amount, 54000);

      final topedRes = LocalNotificationParser.parse(
        title: 'Tokopedia',
        message: 'Pembayaran sebesar Rp 125.000 berhasil diverifikasi',
        packageName: 'com.tokopedia.tkpd',
      );
      expect(topedRes, isNotNull);
      expect(topedRes!.amount, 125000);
    });

    test('Diverse amount formatting (,-, decimals, thousand spaces, k/rb)', () {
      // 50.000,-
      final dashRes = LocalNotificationParser.parse(
        title: 'Pembayaran',
        message: 'Pembayaran debit Rp 50.000,- di Apotek K24 berhasil',
        packageName: 'com.any.bank',
      );
      expect(dashRes, isNotNull);
      expect(dashRes!.amount, 50000);
      expect(dashRes.category, 'kesehatan');

      // IDR 125,000.00
      final idrRes = LocalNotificationParser.parse(
        title: 'Debit Alert',
        message: 'Payment of IDR 125,000.00 at iBox Store completed',
        packageName: 'com.any.bank',
      );
      expect(idrRes, isNotNull);
      expect(idrRes!.amount, 125000);
      expect(idrRes.category, 'elektronik');

      // 50k
      final kRes = LocalNotificationParser.parse(
        title: 'Transaksi',
        message: 'Kamu telah membayar Rp 50k di Uniqlo',
        packageName: 'com.any.fintech',
      );
      expect(kRes, isNotNull);
      expect(kRes!.amount, 50000);
      expect(kRes.category, 'baju');

      // 25rb
      final rbRes = LocalNotificationParser.parse(
        title: 'Transaksi Sukses',
        message: 'Bayar 25rb di Parkir Mall berhasil',
        packageName: 'com.any.fintech',
      );
      expect(rbRes, isNotNull);
      expect(rbRes!.amount, 25000);
      expect(rbRes.category, 'transportasi');
    });

    test('Universal Financial Fallback on unknown app package', () {
      final fallbackRes = LocalNotificationParser.parse(
        title: 'Bank Custom Baru',
        message: 'Transaksi debit keluar Rp 350.000 untuk Rumah Sakit Siloam berhasil',
        packageName: 'com.bankcustom.baru',
      );
      expect(fallbackRes, isNotNull);
      expect(fallbackRes!.amount, 350000);
      expect(fallbackRes.category, 'kesehatan');
    });

    test('Bare unformatted amount is not truncated', () {
      final res = LocalNotificationParser.parse(
        title: 'Pembayaran',
        message: 'Pembayaran QRIS Rp5000 di Warung Kopi berhasil',
        packageName: 'com.any.bank',
      );
      expect(res, isNotNull);
      expect(res!.amount, 5000);
    });

    test('Ignores balance/limit figures when a real transaction amount exists', () {
      final res = LocalNotificationParser.parse(
        title: 'Transaksi Berhasil',
        message: 'Sisa saldo Rp 1.500.000. Pembayaran QRIS Rp 45.000 di Warung Makan Berkah berhasil.',
        packageName: 'com.any.bank',
      );
      expect(res, isNotNull);
      expect(res!.amount, 45000);
    });

    test('Merchant word order independent of the payment keyword', () {
      final res = LocalNotificationParser.parse(
        title: 'BCA mobile',
        message: 'Pembayaran QRIS di Solaria sebesar Rp 75.000 berhasil',
        packageName: 'com.bca',
      );
      expect(res, isNotNull);
      expect(res!.amount, 75000);
      expect(res.name, contains('Solaria'));
    });

    test('Does not extract account/device nouns as merchant', () {
      final res = LocalNotificationParser.parse(
        title: 'Transfer Berhasil',
        message: 'Kamu berhasil kirim Rp 100.000 ke rekening 1234567890',
        packageName: 'com.jago.app',
      );
      expect(res, isNotNull);
      expect(res!.amount, 100000);
      expect(res.name, isNot(contains('1234567890')));
    });
  });
}
