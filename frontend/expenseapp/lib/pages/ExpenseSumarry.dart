import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/databaseHelper.dart';
import '../widgets/neo_animations.dart';
import 'ExpenseEdit.dart';
import 'hp2.dart';

class ExpenseSumarryPage extends StatefulWidget {
  final List<ExpenseModel>? initialExpenses;

  const ExpenseSumarryPage({super.key, this.initialExpenses});

  @override
  State<ExpenseSumarryPage> createState() => _ExpenseSumarryPageState();
}

class _CategorySummary {
  final String category;
  final int totalAmount;
  final int count;
  final double percentage;
  final Color color;
  final IconData icon;

  _CategorySummary({
    required this.category,
    required this.totalAmount,
    required this.count,
    required this.percentage,
    required this.color,
    required this.icon,
  });
}

class _TypeSummary {
  final String type;
  final String label;
  final int totalAmount;
  final int count;
  final double percentage;
  final Color color;

  _TypeSummary({
    required this.type,
    required this.label,
    required this.totalAmount,
    required this.count,
    required this.percentage,
    required this.color,
  });
}

class _DailyExpenseSummary {
  final DateTime date;
  final String dayLabel;
  final int totalAmount;
  final bool isToday;

  _DailyExpenseSummary({
    required this.date,
    required this.dayLabel,
    required this.totalAmount,
    required this.isToday,
  });
}

class _ExpenseSumarryPageState extends State<ExpenseSumarryPage> {
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;

  final Map<String, IconData> _categoryIcons = {
    'makanan': Icons.fastfood_rounded,
    'school supply': Icons.school_rounded,
    'baju': Icons.checkroom_rounded,
    'elektronik': Icons.devices_rounded,
    'transportasi': Icons.directions_car_rounded,
    'kesehatan': Icons.medical_services_rounded,
    'hiburan': Icons.celebration_rounded,
  };

  final Map<String, Color> _categoryColors = {
    'makanan': const Color(0xFFFFD166),
    'school supply': const Color(0xFFC77DFF),
    'baju': const Color(0xFFFF99C8),
    'elektronik': const Color(0xFF70D6FF),
    'transportasi': const Color(0xFF06D6A0),
    'kesehatan': const Color(0xFFFF70A6),
    'hiburan': const Color(0xFFB5E48C),
  };

  @override
  void initState() {
    super.initState();
    if (widget.initialExpenses != null) {
      _expenses = List.from(widget.initialExpenses!);
      _isLoading = false;
    } else {
      _loadExpenses();
    }
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    try {
      final raw = await DatabaseHelp.getData();
      final loaded = raw.map((item) => ExpenseModel.fromMap(item)).toList();
      if (mounted) {
        setState(() {
          _expenses = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _currencySymbol {
    switch (appCurrency.value) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      default:
        return 'Rp';
    }
  }

  String get _currencyLocale {
    switch (appCurrency.value) {
      case 'USD':
        return 'en_US';
      case 'EUR':
        return 'de_DE';
      default:
        return 'id_ID';
    }
  }

  int get _currencyDecimalDigits {
    switch (appCurrency.value) {
      case 'USD':
      case 'EUR':
        return 2;
      default:
        return 0;
    }
  }

  String _formatCurrency(num amount) {
    final formatter = NumberFormat.currency(
      locale: _currencyLocale,
      symbol: _currencySymbol,
      decimalDigits: _currencyDecimalDigits,
    );
    return formatter.format(amount * appExchangeRate.value);
  }

  BoxDecoration _neoCardDecoration({
    Color color = Colors.white,
    double radius = 20,
    double borderWidth = 2.8,
    double shadowOffset = 4,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.black, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: Colors.black,
          offset: Offset(shadowOffset, shadowOffset),
          blurRadius: 0,
        ),
      ],
    );
  }

  // --- CALCULATION LOGIC ---

  int get _grandTotal => _expenses.fold<int>(0, (sum, e) => sum + e.amount);

  List<_CategorySummary> get _categorySummaries {
    if (_expenses.isEmpty) return [];
    final total = _grandTotal;
    final Map<String, List<ExpenseModel>> grouped = {};

    for (final exp in _expenses) {
      final cat = exp.category.trim().toLowerCase();
      grouped.putIfAbsent(cat, () => []).add(exp);
    }

    final list = grouped.entries.map((entry) {
      final cat = entry.key;
      final items = entry.value;
      final sum = items.fold<int>(0, (acc, item) => acc + item.amount);
      final pct = total > 0 ? (sum / total) * 100 : 0.0;
      final color = _categoryColors[cat] ?? const Color(0xFF5DF9FF);
      final icon = _categoryIcons[cat] ?? Icons.receipt_long_rounded;

      return _CategorySummary(
        category: cat,
        totalAmount: sum,
        count: items.length,
        percentage: pct,
        color: color,
        icon: icon,
      );
    }).toList();

    list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
    return list;
  }

  List<_TypeSummary> get _typeSummaries {
    if (_expenses.isEmpty) return [];
    final total = _grandTotal;
    final Map<String, int> amounts = {
      'expected': 0,
      'unexpected': 0,
      'others': 0,
    };
    final Map<String, int> counts = {
      'expected': 0,
      'unexpected': 0,
      'others': 0,
    };

    for (final exp in _expenses) {
      final t = exp.type.trim().toLowerCase();
      final key = amounts.containsKey(t) ? t : 'others';
      amounts[key] = (amounts[key] ?? 0) + exp.amount;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return [
      _TypeSummary(
        type: 'expected',
        label: 'Terencana',
        totalAmount: amounts['expected']!,
        count: counts['expected']!,
        percentage: total > 0 ? (amounts['expected']! / total) * 100 : 0.0,
        color: const Color(0xFFF9EB5D),
      ),
      _TypeSummary(
        type: 'unexpected',
        label: 'Tak Terduga',
        totalAmount: amounts['unexpected']!,
        count: counts['unexpected']!,
        percentage: total > 0 ? (amounts['unexpected']! / total) * 100 : 0.0,
        color: const Color(0xFFFF5D5D),
      ),
      _TypeSummary(
        type: 'others',
        label: 'Lainnya',
        totalAmount: amounts['others']!,
        count: counts['others']!,
        percentage: total > 0 ? (amounts['others']! / total) * 100 : 0.0,
        color: const Color(0xFF5D9BFF),
      ),
    ];
  }

  List<_DailyExpenseSummary> get _last7DaysReview {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<_DailyExpenseSummary> result = [];

    final dayFormat = DateFormat('E', 'id_ID');

    for (int i = 6; i >= 0; i--) {
      final dayDate = today.subtract(Duration(days: i));
      final dayExpenses = _expenses.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return d.isAtSameMomentAs(dayDate);
      });

      final sum = dayExpenses.fold<int>(0, (acc, e) => acc + e.amount);
      String label = dayFormat.format(dayDate);
      if (label.isEmpty) {
        label = DateFormat('E').format(dayDate);
      }

      result.add(_DailyExpenseSummary(
        date: dayDate,
        dayLabel: label,
        totalAmount: sum,
        isToday: i == 0,
      ));
    }

    return result;
  }

  /// Statistically sound Outlier Detection
  /// Uses Interquartile Range (IQR = Q3 - Q1) with threshold Q3 + 1.5 * IQR.
  /// Falls back to mean + 1.5 * standard deviation for smaller datasets.
  List<Map<String, dynamic>> get _outliers {
    if (_expenses.length < 3) return [];

    final sortedAmounts = _expenses.map((e) => e.amount.toDouble()).toList()..sort();
    final n = sortedAmounts.length;

    double q1;
    double q3;
    if (n >= 4) {
      final q1Index = (n * 0.25).floor();
      final q3Index = (n * 0.75).floor();
      q1 = sortedAmounts[q1Index];
      q3 = sortedAmounts[q3Index];
    } else {
      q1 = sortedAmounts.first;
      q3 = sortedAmounts.last;
    }

    final iqr = q3 - q1;
    final double threshold = iqr > 0
        ? q3 + (1.5 * iqr)
        : sortedAmounts.reduce((a, b) => a + b) / n * 1.8;

    final mean = sortedAmounts.reduce((a, b) => a + b) / n;

    final detected = <Map<String, dynamic>>[];

    for (final exp in _expenses) {
      if (exp.amount >= threshold && exp.amount > mean) {
        final ratio = mean > 0 ? (exp.amount / mean) : 1.0;
        detected.add({
          'expense': exp,
          'ratio': ratio,
        });
      }
    }

    detected.sort((a, b) => (b['expense'] as ExpenseModel)
        .amount
        .compareTo((a['expense'] as ExpenseModel).amount));

    return detected;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF14171A) : const Color(0xFFF4F7FB);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: NeoBouncy(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: _neoCardDecoration(
              color: isDark ? const Color(0xFF242424) : Colors.white,
              radius: 12,
              shadowOffset: 2,
              borderWidth: 2,
            ),
            child: Icon(
              Icons.arrow_back,
              color: isDark ? Colors.white : Colors.black,
              size: 22,
            ),
          ),
        ),
        title: Text(
          'Expense Analytics',
          style: GoogleFonts.itim(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadExpenses,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                children: [
                  // Hero Total Overview Banner
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 50),
                    child: _buildHeroOverviewCard(isDark),
                  ),

                  const SizedBox(height: 22),

                  // 7-Day Review Chart Section
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 100),
                    child: _buildWeeklySection(isDark),
                  ),

                  const SizedBox(height: 22),

                  // Category Breakdown Chart Section
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 150),
                    child: _buildCategorySection(isDark),
                  ),

                  const SizedBox(height: 22),

                  // Expense Type Breakdown Section (Expected vs Unexpected)
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 200),
                    child: _buildTypeSection(isDark),
                  ),

                  const SizedBox(height: 22),

                  // Outlier Detector Section
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 250),
                    child: _buildOutliersSection(isDark),
                  ),
                ],
              ),
            ),
    );
  }

  // --- SECTION BUILDERS ---

  Widget _buildHeroOverviewCard(bool isDark) {
    final count = _expenses.length;
    final total = _grandTotal;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _neoCardDecoration(
        color: const Color(0xFF5DF9FF),
        radius: 24,
        shadowOffset: 5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 1.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.insights_rounded, size: 16, color: Colors.black),
                      const SizedBox(width: 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'TOTAL FINANCIAL SUMMARY',
                            style: GoogleFonts.itim(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EB5D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.6),
                ),
                child: Text(
                  appCurrency.value,
                  style: GoogleFonts.itim(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatCurrency(total),
              style: GoogleFonts.itim(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHeroStatPill(
                icon: Icons.receipt_long_rounded,
                label: '$count Transaksi',
              ),
              _buildHeroStatPill(
                icon: Icons.pie_chart_rounded,
                label: '${_categorySummaries.length} Kategori',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.itim(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // --- 7-DAY REVIEW BAR CHART ---

  Widget _buildWeeklySection(bool isDark) {
    final days = _last7DaysReview;
    final total7Days = days.fold<int>(0, (acc, d) => acc + d.totalAmount);
    final maxAmount = days.map((d) => d.totalAmount).reduce(math.max);
    final highestDay = days.where((d) => d.totalAmount == maxAmount && d.totalAmount > 0).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _neoCardDecoration(
        color: isDark ? const Color(0xFF1E2830) : Colors.white,
        radius: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EB5D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.date_range_rounded, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Review 7 Hari Terakhir',
                    style: GoogleFonts.itim(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.6),
                ),
                child: Text(
                  'Total 7H: ${_formatCurrency(total7Days)}',
                  style: GoogleFonts.itim(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Custom Neobrutalist Bar Chart
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: days.map((day) {
                final ratio = maxAmount > 0 ? (day.totalAmount / maxAmount) : 0.0;
                final barHeight = (ratio * 105).clamp(8.0, 105.0);
                final isPeak = highestDay != null && day.date.isAtSameMomentAs(highestDay.date);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (day.totalAmount > 0)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _formatCompact(day.totalAmount),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey[300] : Colors.black87,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutBack,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isPeak
                                ? const Color(0xFFFF5D5D)
                                : (day.isToday ? const Color(0xFF5DF9FF) : const Color(0xFFF9EB5D)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(2, 2),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: day.isToday
                              ? BoxDecoration(
                                  color: isDark ? Colors.white24 : const Color(0xFF06D6A0),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.black, width: 1.2),
                                )
                              : null,
                          child: Text(
                            day.dayLabel,
                            style: GoogleFonts.itim(
                              fontSize: 12,
                              fontWeight: day.isToday ? FontWeight.bold : FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Peak Day Insight Banner
          if (highestDay != null && highestDay.totalAmount > 0)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5D5D).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF5D5D), width: 1.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF5D5D), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Puncak pengeluaran 7 hari ini terjadi pada ${highestDay.dayLabel} (${_formatCurrency(highestDay.totalAmount)})',
                      style: GoogleFonts.itim(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFFB42318),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatCompact(num amount) {
    final converted = amount * appExchangeRate.value;
    if (_currencyDecimalDigits > 0) {
      if (converted >= 1000000) {
        return '$_currencySymbol${(converted / 1000000).toStringAsFixed(1)}M';
      }
      if (converted >= 1000) {
        return '$_currencySymbol${(converted / 1000).toStringAsFixed(1)}k';
      }
      return '$_currencySymbol${converted.toStringAsFixed(2)}';
    } else {
      if (converted >= 1000000) {
        return '${(converted / 1000000).toStringAsFixed(1)}M';
      }
      if (converted >= 1000) {
        return '${(converted / 1000).toStringAsFixed(0)}k';
      }
      return converted.toStringAsFixed(0);
    }
  }

  // --- CATEGORY BREAKDOWN ---

  Widget _buildCategorySection(bool isDark) {
    final cats = _categorySummaries;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _neoCardDecoration(
        color: isDark ? const Color(0xFF1E2830) : Colors.white,
        radius: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.category_rounded, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Distribusi per Kategori',
                    style: GoogleFonts.itim(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Proportional Multi-Segmented Bar
          if (cats.isNotEmpty) ...[
            Container(
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 2.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9.8),
                child: Row(
                  children: cats.map((c) {
                    return Flexible(
                      flex: (c.percentage * 10).round().clamp(1, 1000),
                      child: Container(
                        color: c.color,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Category Cards List
          if (cats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Belum ada kategori tercatat', style: TextStyle(color: Colors.grey[500])),
              ),
            )
          else
            ...cats.map((c) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF242E38) : const Color(0xFFF9FBFD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black, width: 1.8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.color,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black, width: 1.6),
                      ),
                      child: Icon(c.icon, size: 18, color: Colors.black),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.category.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.itim(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${c.count} item • ${c.percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatCurrency(c.totalAmount),
                        style: GoogleFonts.itim(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --- TYPE BREAKDOWN (Expected vs Unexpected) ---

  Widget _buildTypeSection(bool isDark) {
    final types = _typeSummaries;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _neoCardDecoration(
        color: isDark ? const Color(0xFF1E2830) : Colors.white,
        radius: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF99C8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.pie_chart_outline_rounded, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tipe Pengeluaran',
                    style: GoogleFonts.itim(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 3-Way Ratio Row
          Row(
            children: types.map((t) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black,
                        offset: Offset(2.5, 2.5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.label,
                          style: GoogleFonts.itim(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${t.percentage.toStringAsFixed(1)}%',
                          style: GoogleFonts.itim(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatCurrency(t.totalAmount),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // Financial Discipline Advice Pill
          _buildDisciplineInsight(types, isDark),
        ],
      ),
    );
  }

  Widget _buildDisciplineInsight(List<_TypeSummary> types, bool isDark) {
    final unexpected = types.firstWhere((t) => t.type == 'unexpected');
    final isHighUnexpected = unexpected.percentage > 35;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighUnexpected
            ? const Color(0xFFFF5D5D).withValues(alpha: 0.15)
            : const Color(0xFF06D6A0).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighUnexpected ? const Color(0xFFFF5D5D) : const Color(0xFF06D6A0),
          width: 1.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isHighUnexpected ? Icons.warning_amber_rounded : Icons.verified_rounded,
            color: isHighUnexpected ? const Color(0xFFFF5D5D) : const Color(0xFF06D6A0),
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isHighUnexpected
                  ? 'Pengeluaran tak terduga mencapai ${unexpected.percentage.toStringAsFixed(0)}%! Alokasikan dana darurat lebih ketat.'
                  : 'Rasio terencana sehat! Pengeluaran tak terduga terkendali di bawah 35%.',
              style: GoogleFonts.itim(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- OUTLIER DETECTOR SECTION ---

  Widget _buildOutliersSection(bool isDark) {
    final outliers = _outliers;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _neoCardDecoration(
        color: isDark ? const Color(0xFF1E2830) : Colors.white,
        radius: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5D5D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Detektor Outlier 🚨',
                    style: GoogleFonts.itim(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EB5D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.6),
                ),
                child: Text(
                  '${outliers.length} Anomali',
                  style: GoogleFonts.itim(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            'Pengeluaran yang nominalnya jauh lebih tinggi dari transaksi rata-rata:',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),

          const SizedBox(height: 14),

          if (outliers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF06D6A0).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF06D6A0), width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF06D6A0), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tidak ada outlier terdeteksi! Semua pengeluaran berada dalam rentang wajar ✨',
                      style: GoogleFonts.itim(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...outliers.map((item) {
              final exp = item['expense'] as ExpenseModel;
              final ratio = (item['ratio'] as double);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2424) : const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF5D5D), width: 2.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(3, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5D5D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exp.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.itim(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9EB5D),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.black, width: 1.2),
                                ),
                                child: Text(
                                  '${ratio.toStringAsFixed(1)}x rata-rata',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              Text(
                                DateFormat('dd MMM yyyy').format(exp.date),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _formatCurrency(exp.amount),
                            style: GoogleFonts.itim(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF5D5D),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        NeoBouncy(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              SmoothPageRoute(page: ExpenseEdit(expenseId: exp.id)),
                            );
                            _loadExpenses();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E2830) : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.black, width: 1.2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Edit',
                                  style: GoogleFonts.itim(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF5DF9FF) : const Color(0xFF007A99),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 11,
                                  color: isDark ? const Color(0xFF5DF9FF) : const Color(0xFF007A99),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
