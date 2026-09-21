class ParsedNotificationResult {
  final String name;
  final int amount;
  final String category;
  final String type;
  final String? date;
  final bool isExpense;
  final bool isFinancial;

  const ParsedNotificationResult({
    required this.name,
    required this.amount,
    required this.category,
    required this.type,
    this.date,
    this.isExpense = true,
    this.isFinancial = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'category': category,
      'type': type,
      if (date != null) 'date': date,
    };
  }
}

class LocalNotificationParser {
  LocalNotificationParser._();

  static final _promoOtpKeywords = <String>[
    'promo',
    'diskon',
    'cashback',
    'voucher',
    'kupon',
    'penawaran spesial',
    'potongan harga',
    'otp',
    'kode verifikasi',
    'kode otp',
    'verification code',
    'jangan bagikan kode',
    'security code',
    'login terdeteksi',
    'berhasil masuk',
    'perangkat baru',
    'ubah pin',
    'ganti password',
  ];

  static final _incomeKeywords = <String>[
    'transfer masuk',
    'dana masuk',
    'uang masuk',
    'menerima transfer',
    'menerima saldo',
    'kamu menerima',
    'top up berhasil',
    'top up saldo berhasil',
    'telah ditambahkan ke saldo',
    'setoran tunai berhasil',
  ];

  /// Checks if a notification is noise (promo, OTP, security alert).
  static bool isIgnoredNoise(String title, String message) {
    final combined = '$title $message'.toLowerCase();
    for (final keyword in _promoOtpKeywords) {
      if (combined.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if a notification indicates income / money received.
  static bool isIncomeTransaction(String title, String message) {
    final combined = '$title $message'.toLowerCase();
    for (final keyword in _incomeKeywords) {
      if (combined.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// Attempts to parse expense details from notification text locally.
  /// Returns null if unable to determine amount or not recognized as an expense.
  static ParsedNotificationResult? parse({
    required String title,
    required String message,
    required String packageName,
    DateTime? timestamp,
  }) {
    // 1. Noise check
    if (isIgnoredNoise(title, message)) {
      return null;
    }

    // 2. Income check (skip incoming money/top-up to avoid double counting)
    if (isIncomeTransaction(title, message)) {
      return null;
    }

    final combined = '$title\n$message';
    final pkg = packageName.toLowerCase();

    ParsedNotificationResult? result;

    if (pkg.contains('gojek') || pkg.contains('gopay')) {
      result = _parseGoPay(title, message, combined);
    } else if (pkg.contains('dana')) {
      result = _parseDana(title, message, combined);
    } else if (pkg.contains('ovo')) {
      result = _parseOvo(title, message, combined);
    } else if (pkg.contains('bca')) {
      result = _parseBca(title, message, combined);
    } else if (pkg.contains('bmri') || pkg.contains('mandiri') || pkg.contains('livin')) {
      result = _parseMandiri(title, message, combined);
    } else if (pkg.contains('bri')) {
      result = _parseBri(title, message, combined);
    } else if (pkg.contains('shopee')) {
      result = _parseShopee(title, message, combined);
    }

    // Fallback to generic Indonesian transaction regex
    result ??= _parseGeneric(title, message, combined);

    if (result != null && result.amount > 0) {
      final dateStr = (timestamp ?? DateTime.now()).toIso8601String().substring(0, 10);
      return ParsedNotificationResult(
        name: result.name.trim().isEmpty ? 'Transaksi ${getAppDisplayName(packageName)}' : result.name.trim(),
        amount: result.amount,
        category: result.category,
        type: result.type,
        date: dateStr,
        isExpense: true,
        isFinancial: true,
      );
    }

    return null;
  }

  static String getAppDisplayName(String packageName) {
    final pkg = packageName.toLowerCase();
    if (pkg.contains('bca')) return 'BCA';
    if (pkg.contains('mandiri') || pkg.contains('bmri')) return 'Mandiri';
    if (pkg.contains('bri')) return 'BRImo';
    if (pkg.contains('bni')) return 'BNI';
    if (pkg.contains('gojek') || pkg.contains('gopay')) return 'GoPay';
    if (pkg.contains('dana')) return 'DANA';
    if (pkg.contains('ovo')) return 'OVO';
    if (pkg.contains('shopee')) return 'ShopeePay';
    if (pkg.contains('grab')) return 'Grab';
    return 'Bank/E-Wallet';
  }

  // --- Parser Rules ---

  static ParsedNotificationResult? _parseGoPay(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:bayar|membayar|pembayaran)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)\s+(?:ke|di)\s+([^.\n]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? '');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    final m2 = RegExp(
      r'(?:bayar|pembayaran)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)\s+berhasil',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m2 != null) {
      final amount = _parseAmount(m2.group(1));
      if (amount > 0) {
        return ParsedNotificationResult(
          name: 'GoPay Payment',
          amount: amount,
          category: 'makanan',
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseDana(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:bayar|membayar|pembayaran|kirim uang)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)\s+(?:di|ke)\s+([^.\n]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? '');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseOvo(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:berhasil bayar|pembayaran)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)\s+(?:di|ke)\s+([^.\n]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? '');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseBca(String title, String message, String combined) {
    final qrisMatch = RegExp(
      r'(?:qris|debit|transfer ke)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)(?:\s+(?:di|ke)\s+([^.\n]+))?',
      caseSensitive: false,
    ).firstMatch(combined);

    if (qrisMatch != null) {
      final amount = _parseAmount(qrisMatch.group(1));
      final merchant = _cleanMerchantName(qrisMatch.group(2) ?? 'BCA Transaction');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    final transferMatch = RegExp(
      r'transfer ke\s+([A-Za-z0-9 ._-]+).*?(?:Rp\.?|IDR)\s*([0-9.,]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (transferMatch != null) {
      final merchant = _cleanMerchantName(transferMatch.group(1) ?? 'Transfer');
      final amount = _parseAmount(transferMatch.group(2));
      if (amount > 0) {
        return ParsedNotificationResult(
          name: 'Transfer ke $merchant',
          amount: amount,
          category: 'lainnya',
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseMandiri(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:pembayaran qris|transaksi debit|transfer)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)(?:\s+(?:di|ke)\s+([^.\n]+))?',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? 'Mandiri Payment');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseBri(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:pembayaran qris|transaksi)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)(?:\s+(?:di|ke)\s+([^.\n]+))?',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? 'BRImo Payment');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseShopee(String title, String message, String combined) {
    final m1 = RegExp(
      r'(?:pembayaran|berhasil bayar)\s+(?:sebesar\s+)?(?:Rp\.?|IDR)?\s*([0-9.,]+)(?:.*?(?:di|ke)\s+([^.\n]+))?',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m1 != null) {
      final amount = _parseAmount(m1.group(1));
      final merchant = _cleanMerchantName(m1.group(2) ?? 'ShopeePay');
      if (amount > 0) {
        return ParsedNotificationResult(
          name: merchant,
          amount: amount,
          category: _categorize(merchant),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  static ParsedNotificationResult? _parseGeneric(String title, String message, String combined) {
    final isTransaction = RegExp(
      r'(?:bayar|pembayaran|berhasil|debit|debet|qris|belanja|merchant)',
      caseSensitive: false,
    ).hasMatch(combined);

    if (!isTransaction) return null;

    final match = RegExp(
      r'(?:Rp\.?|IDR)\s*([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{2})?|[0-9]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (match != null) {
      final amount = _parseAmount(match.group(1));
      if (amount > 0) {
        final targetMatch = RegExp(r'(?:di|ke)\s+([A-Za-z0-9 .,_-]+)', caseSensitive: false)
            .firstMatch(combined);
        final name = targetMatch != null
            ? _cleanMerchantName(targetMatch.group(1) ?? '')
            : (title.isNotEmpty ? title : 'Transaksi Otomatis');

        return ParsedNotificationResult(
          name: name.isEmpty ? 'Transaksi Otomatis' : name,
          amount: amount,
          category: _categorize(name),
          type: 'unexpected',
        );
      }
    }

    return null;
  }

  // --- Helper Methods ---

  static int _parseAmount(String? raw) {
    if (raw == null) return 0;
    var cleaned = raw.trim();

    if (cleaned.contains(',') && cleaned.contains('.')) {
      if (cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')) {
        cleaned = cleaned.split(',')[0].replaceAll('.', '');
      } else {
        cleaned = cleaned.split('.')[0].replaceAll(',', '');
      }
    } else if (cleaned.contains('.')) {
      final parts = cleaned.split('.');
      if (parts.last.length == 3 || parts.length > 2) {
        cleaned = cleaned.replaceAll('.', '');
      } else if (parts.last.length == 2) {
        cleaned = parts[0];
      } else {
        cleaned = cleaned.replaceAll('.', '');
      }
    } else if (cleaned.contains(',')) {
      final parts = cleaned.split(',');
      if (parts.last.length == 3 || parts.length > 2) {
        cleaned = cleaned.replaceAll(',', '');
      } else if (parts.last.length == 2) {
        cleaned = parts[0];
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    }

    return int.tryParse(cleaned.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  static String _cleanMerchantName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    name = name.replaceAll(RegExp(r'^(berhasil|sukses)\s+', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'\s+(berhasil|sukses|pada|sebesar|rp).*$', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'[.!?,;]+$'), '').trim();
    return name.isEmpty ? 'Merchant' : name;
  }

  static String _categorize(String text) {
    final lower = text.toLowerCase();

    if (RegExp(r'kopi|coffee|cafe|roti|bakso|mie|mcd|kfc|starbucks|chatime|indomaret|alfamart|solaria|hokben|dapur|resto|restoran|warung|makan|food|jco|pizza|burger|snack|gofood|grabfood|beverage').hasMatch(lower)) {
      return 'makanan';
    }

    if (RegExp(r'gojek|goride|gocar|grab|grabcar|grabride|parkir|pertamina|spbu|shell|bensin|krl|mrt|transjakarta|tiket|kereta|tol|bluebird').hasMatch(lower)) {
      return 'transportasi';
    }

    if (RegExp(r'cinema|bioskop|xxi|cgv|netflix|spotify|youtube|steam|game|playstation|karaoke|billiard').hasMatch(lower)) {
      return 'hiburan';
    }

    if (RegExp(r'apotek|apotik|kimia farma|k24|rumah sakit|klinik|dokter|optik|halodoc|alodokter|dental').hasMatch(lower)) {
      return 'kesehatan';
    }

    if (RegExp(r'ibox|erafone|electronic|gadget|digimap|samsung|xiaomi|asus|laptop|komputer').hasMatch(lower)) {
      return 'elektronik';
    }

    if (RegExp(r'zara|uniqlo|h&m|pakaian|distro|fashion|baju|sepatu|tas|cotton|boutique').hasMatch(lower)) {
      return 'baju';
    }

    if (RegExp(r'gramedia|buku|fotocopy|stationery|toko buku|atk|sekolah|kuliah').hasMatch(lower)) {
      return 'school supply';
    }

    return 'lainnya';
  }
}
