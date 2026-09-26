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

  // Robust amount regex string used across all parsers
  // Matches: 50k | 25rb | 1.250.000 | 50.000,00 | 50.000,- | 50000
  // The grouped-thousands branch requires at least one separator group so a bare
  // number like "5000" falls through to the plain-digit branch instead of being
  // truncated to "500".
  static const _numberPattern =
      r'([0-9]+(?:\s*(?:[kK]|rb|RB))|[0-9]{1,3}(?:[.,\s][0-9]{3})+(?:[.,][0-9]{2})?|[0-9]+)\s*(?:,-)?';

  // Numbers whose nearby context mentions these words are balances/limits,
  // not the transaction amount, and must be skipped when picking an amount.
  static const _balanceContextKeywords = <String>['saldo', 'limit', 'sisa', 'balance'];

  // Strict OTP / Auth keywords that must always be ignored for security
  static final _securityOtpKeywords = <String>[
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
    'reset password',
  ];

  // Marketing keywords (ignored only when there is NO payment confirmation)
  static final _purePromoKeywords = <String>[
    'diskon s.d',
    'cashback hingga',
    'klaim voucher',
    'klaim kupon',
    'penawaran spesial buat kamu',
    'promo gajian',
    'flash sale',
    'diskon hingga',
    'voucher gratis',
  ];

  // Income / incoming funds (ignored to prevent recording as expense)
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
    'rekening dikredit',
    'kredit rekening',
    'received money',
    'money in',
  ];

  // Payment confirmation keywords (indicating a transaction really took place)
  static final _paymentActionKeywords = <String>[
    'bayar',
    'membayar',
    'pembayaran',
    'berhasil bayar',
    'sukses bayar',
    'qris',
    'transaksi',
    'transfer ke',
    'kirim uang ke',
    'kirim saldo',
    'debit',
    'debet',
    'terpotong',
    'potongan',
    'keluar',
    'tarik tunai',
    'belanja',
    'paid',
    'payment of',
    'payment successful',
    'money out',
    'spent',
    'purchase',
    'order completed',
    'pesananmu di',
  ];

  /// Checks if a notification is noise (pure promo or OTP/security alert).
  static bool isIgnoredNoise(String title, String message) {
    final combined = '$title $message'.toLowerCase();

    // Always ignore OTP or security verification
    for (final keyword in _securityOtpKeywords) {
      if (combined.contains(keyword)) {
        return true;
      }
    }

    // Check if it's pure promo without actual payment indicator
    final hasPaymentConfirmation = _paymentActionKeywords.any((kw) => combined.contains(kw));
    if (!hasPaymentConfirmation) {
      for (final keyword in _purePromoKeywords) {
        if (combined.contains(keyword)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Checks if a notification indicates income / money received.
  static bool isIncomeTransaction(String title, String message) {
    final combined = '$title $message'.toLowerCase();

    for (final keyword in _incomeKeywords) {
      if (combined.contains(keyword)) {
        if (!combined.contains('transfer keluar') && !combined.contains('gagal')) {
          return true;
        }
      }
    }
    return false;
  }

  /// Multi-tier parsing engine designed for >99% success rate.
  static ParsedNotificationResult? parse({
    required String title,
    required String message,
    required String packageName,
    DateTime? timestamp,
  }) {
    if (isIgnoredNoise(title, message)) {
      return null;
    }

    if (isIncomeTransaction(title, message)) {
      return null;
    }

    final combined = '$title\n$message';
    final pkg = packageName.toLowerCase();

    ParsedNotificationResult? result;

    // --- Tier 1: Specialized Bank & Fintech Parsers ---
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
    } else if (pkg.contains('bni')) {
      result = _parseBni(title, message, combined);
    } else if (pkg.contains('jago')) {
      result = _parseJago(title, message, combined);
    } else if (pkg.contains('jenius') || pkg.contains('btpn')) {
      result = _parseJenius(title, message, combined);
    } else if (pkg.contains('beepr') || pkg.contains('seabank')) {
      result = _parseSeaBank(title, message, combined);
    } else if (pkg.contains('bsi')) {
      result = _parseBsi(title, message, combined);
    } else if (pkg.contains('cimb') || pkg.contains('octo')) {
      result = _parseCimb(title, message, combined);
    } else if (pkg.contains('shopee')) {
      result = _parseShopee(title, message, combined);
    } else if (pkg.contains('grab')) {
      result = _parseGrab(title, message, combined);
    } else if (pkg.contains('tokopedia')) {
      result = _parseTokopedia(title, message, combined);
    }

    // --- Tier 2: Universal Financial Semantic Extractor ---
    result ??= _parseUniversalFinancial(title, message, combined, packageName);

    if (result != null && result.amount > 0) {
      final dateStr = (timestamp ?? DateTime.now()).toIso8601String().substring(0, 10);
      final fallbackAppName = getAppDisplayName(packageName);
      final finalName = result.name.trim().isEmpty || result.name.trim() == 'Merchant'
          ? 'Transaksi $fallbackAppName'
          : result.name.trim();

      return ParsedNotificationResult(
        name: finalName,
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
    if (pkg.contains('bri')) return 'BRI';
    if (pkg.contains('bni')) return 'BNI';
    if (pkg.contains('jago')) return 'Bank Jago';
    if (pkg.contains('jenius') || pkg.contains('btpn')) return 'Jenius';
    if (pkg.contains('beepr') || pkg.contains('seabank')) return 'SeaBank';
    if (pkg.contains('bsi')) return 'BSI';
    if (pkg.contains('cimb') || pkg.contains('octo')) return 'CIMB Niaga';
    if (pkg.contains('gojek') || pkg.contains('gopay')) return 'GoPay';
    if (pkg.contains('dana')) return 'DANA';
    if (pkg.contains('ovo')) return 'OVO';
    if (pkg.contains('shopee')) return 'ShopeePay';
    if (pkg.contains('grab')) return 'Grab';
    if (pkg.contains('tokopedia')) return 'Tokopedia';
    if (pkg.contains('flip')) return 'Flip';
    if (pkg.contains('linkaja')) return 'LinkAja';
    return 'Bank / E-Wallet';
  }

  // ==========================================
  // SPECIFIC APP PARSERS (Tier 1)
  // ==========================================

  // Extracts an expense using a per-app keyword check plus the shared,
  // order-independent amount finder, instead of requiring the keyword to sit
  // directly next to the amount (real notifications vary word order too much
  // for that to be reliable, e.g. "QRIS di Toko X sebesar Rp..." vs
  // "QRIS sebesar Rp... di Toko X").
  static ParsedNotificationResult? _bankParse(
    String combined,
    List<String> keywords,
    String defaultName,
  ) {
    if (!_containsAny(combined.toLowerCase(), keywords)) return null;
    final amount = _findAmount(combined);
    if (amount <= 0) return null;
    final merchant = _extractMerchant(combined, defaultName);
    return ParsedNotificationResult(
      name: merchant,
      amount: amount,
      category: _categorize('$merchant $combined'),
      type: 'unexpected',
    );
  }

  static ParsedNotificationResult? _parseGoPay(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['bayar', 'membayar', 'pembayaran', 'paid', 'payment of', 'order completed', 'pesananmu'],
      'GoPay Transaction',
    );
  }

  static ParsedNotificationResult? _parseDana(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['bayar', 'membayar', 'pembayaran', 'kirim uang', 'kirim saldo'],
      'DANA Payment',
    );
  }

  static ParsedNotificationResult? _parseOvo(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['bayar', 'berhasil bayar', 'pembayaran', 'terpotong'],
      'OVO Payment',
    );
  }

  static ParsedNotificationResult? _parseBca(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'debit', 'pembayaran', 'transfer ke', 'transfer'],
      'BCA Transaction',
    );
  }

  static ParsedNotificationResult? _parseMandiri(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'transaksi debit', 'transfer ke', 'transfer', 'pembayaran'],
      'Livin Mandiri',
    );
  }

  static ParsedNotificationResult? _parseBri(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'transaksi debit', 'transfer keluar', 'pembayaran'],
      'BRImo Payment',
    );
  }

  static ParsedNotificationResult? _parseBni(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'transaksi', 'transfer keluar', 'pembayaran'],
      'BNI Payment',
    );
  }

  static ParsedNotificationResult? _parseJago(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['kirim', 'pembayaran ke', 'terpotong', 'pembayaran'],
      'Bank Jago',
    );
  }

  static ParsedNotificationResult? _parseJenius(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'money out', 'membayar', 'pembayaran'],
      'Jenius Payment',
    );
  }

  static ParsedNotificationResult? _parseSeaBank(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['membayar', 'qris', 'pembayaran', 'transfer keluar'],
      'SeaBank Payment',
    );
  }

  static ParsedNotificationResult? _parseBsi(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'transaksi', 'pembayaran', 'transfer keluar'],
      'BSI Mobile',
    );
  }

  static ParsedNotificationResult? _parseCimb(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['qris', 'debit rekening', 'transaksi', 'pembayaran'],
      'OCTO Mobile',
    );
  }

  static ParsedNotificationResult? _parseShopee(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['pembayaran', 'berhasil bayar', 'transaksi'],
      'ShopeePay',
    );
  }

  static ParsedNotificationResult? _parseGrab(String title, String message, String combined) {
    return _bankParse(
      combined,
      const ['pembayaran', 'pesananmu', 'total'],
      'Grab',
    );
  }

  static ParsedNotificationResult? _parseTokopedia(String title, String message, String combined) {
    if (!_containsAny(combined.toLowerCase(), const ['pembayaran', 'transaksi'])) return null;
    final amount = _findAmount(combined);
    if (amount <= 0) return null;
    return ParsedNotificationResult(
      name: 'Tokopedia',
      amount: amount,
      category: 'lainnya',
      type: 'unexpected',
    );
  }

  // ==========================================
  // UNIVERSAL FINANCIAL EXTRACTOR (Tier 2)
  // ==========================================

  static ParsedNotificationResult? _parseUniversalFinancial(
    String title,
    String message,
    String combined,
    String packageName,
  ) {
    if (!_containsAny(combined.toLowerCase(), _paymentActionKeywords)) {
      return null;
    }

    final amount = _findAmount(combined);
    if (amount <= 0) {
      return null;
    }

    String name = _extractMerchant(combined, '');
    if (name.isEmpty || name == 'Merchant') {
      name = title.trim().isNotEmpty ? title.trim() : 'Transaksi ${getAppDisplayName(packageName)}';
    }

    return ParsedNotificationResult(
      name: name,
      amount: amount,
      category: _categorize('$name $combined'),
      type: 'unexpected',
    );
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  // Prepositions like "ke"/"di" often precede account/device nouns instead of a
  // merchant name (e.g. "kirim ke rekening", "transaksi di aplikasi"); treat
  // those, and purely numeric captures (phone/account numbers), as unknown.
  static const _merchantStopWords = <String>[
    'rekening', 'akun', 'aplikasi', 'atm', 'kartu', 'nomor', 'saldo',
    'hp', 'perangkat', 'tanggal', 'pukul', 'jam',
  ];

  static bool _containsAny(String haystack, Iterable<String> keywords) {
    return keywords.any(haystack.contains);
  }

  /// Finds the most likely transaction amount in [combined]: prefers a
  /// currency-tagged number (skipping balance/limit figures), then falls back
  /// to a plain number that directly follows a known payment keyword.
  static int _findAmount(String combined) {
    final lower = combined.toLowerCase();

    final currencyMatches = RegExp(
      r'(?:Rp\.?|IDR)\s*' + _numberPattern,
      caseSensitive: false,
    ).allMatches(combined);

    for (final match in currencyMatches) {
      final contextStart = match.start - 25 < 0 ? 0 : match.start - 25;
      final context = lower.substring(contextStart, match.start);
      if (_containsAny(context, _balanceContextKeywords)) continue;
      final amount = _parseAmount(match.group(1));
      if (amount > 0) return amount;
    }

    final keywordAlternation = _paymentActionKeywords.map(RegExp.escape).join('|');
    final actionMatch = RegExp(
      '(?:$keywordAlternation)\\s+(?:Rp\\.?|IDR)?\\s*' + _numberPattern,
      caseSensitive: false,
    ).firstMatch(combined);
    if (actionMatch != null) {
      final amount = _parseAmount(actionMatch.group(1));
      if (amount > 0) return amount;
    }

    return 0;
  }

  static String _extractMerchant(String combined, [String defaultName = 'Merchant']) {
    final m = RegExp(
      r'(?:di|ke|to|at|untuk)\s+([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(combined);

    if (m != null) {
      final cleaned = _cleanMerchantName(m.group(1) ?? '');
      final firstWord = cleaned.toLowerCase().split(' ').first;
      final looksNumeric = RegExp(r'^[0-9.\-\s]+$').hasMatch(cleaned);
      if (cleaned.isNotEmpty &&
          cleaned != 'Merchant' &&
          !looksNumeric &&
          !_merchantStopWords.contains(firstWord)) {
        return cleaned;
      }
    }
    return defaultName;
  }

  static int _parseAmount(String? raw) {
    if (raw == null) return 0;
    var cleaned = raw.trim().toLowerCase();

    cleaned = cleaned.replaceAll('rp', '').replaceAll('idr', '').replaceAll(',-', '').trim();

    if (cleaned.endsWith('k') || cleaned.endsWith('rb')) {
      cleaned = cleaned.replaceAll('k', '').replaceAll('rb', '').trim();
      final base = double.tryParse(cleaned.replaceAll(',', '.')) ?? 0;
      return (base * 1000).round();
    }

    cleaned = cleaned.replaceAll(' ', '');

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
    name = name.replaceAll(RegExp(r'^(berhasil|sukses|pada)\s+', caseSensitive: false), '');
    name = name.replaceAll(
      RegExp(
        r'\s+(berhasil|sukses|pada|sebesar|rp|idr|menggunakan|lewat|completed|verified|diverifikasi|diproses|processed|selesai).*$',
        caseSensitive: false,
      ),
      '',
    );
    name = name.replaceAll(RegExp(r'[.!?,;]+$'), '').trim();
    return name.isEmpty ? 'Merchant' : name;
  }

  static String _categorize(String text) {
    final lower = text.toLowerCase();

    // Makanan & Minuman
    if (RegExp(r'kopi|coffee|cafe|roti|bakso|mie|mcd|kfc|starbucks|chatime|indomaret|alfamart|solaria|hokben|dapur|resto|restoran|warung|makan|food|jco|pizza|burger|snack|gofood|grabfood|beverage|mixue|janji jiwa|kenangan|fore').hasMatch(lower)) {
      return 'makanan';
    }

    // Transportasi
    if (RegExp(r'gojek|goride|gocar|grab|grabcar|grabride|parkir|pertamina|spbu|shell|bensin|krl|mrt|transjakarta|tiket|kereta|tol|bluebird|kai|garuda|lion|citilink').hasMatch(lower)) {
      return 'transportasi';
    }

    // Hiburan
    if (RegExp(r'cinema|bioskop|xxi|cgv|netflix|spotify|youtube|steam|game|playstation|karaoke|billiard|disney|vidio').hasMatch(lower)) {
      return 'hiburan';
    }

    // Kesehatan
    if (RegExp(r'apotek|apotik|kimia farma|k24|rumah sakit|siloam|klinik|dokter|optik|halodoc|alodokter|dental|century|guardian|watsons').hasMatch(lower)) {
      return 'kesehatan';
    }

    // Elektronik
    if (RegExp(r'ibox|erafone|electronic|gadget|digimap|samsung|xiaomi|asus|laptop|komputer|tokopedia|shopee').hasMatch(lower)) {
      return 'elektronik';
    }

    // Baju / Fashion
    if (RegExp(r'zara|uniqlo|h&m|pakaian|distro|fashion|baju|sepatu|tas|cotton|boutique|matahari').hasMatch(lower)) {
      return 'baju';
    }

    // School / Stationery
    if (RegExp(r'gramedia|buku|fotocopy|stationery|toko buku|atk|sekolah|kuliah|universitas').hasMatch(lower)) {
      return 'school supply';
    }

    return 'lainnya';
  }
}
