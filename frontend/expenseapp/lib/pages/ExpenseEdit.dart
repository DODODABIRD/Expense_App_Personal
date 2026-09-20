import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../main.dart';
import '../services/databaseHelper.dart';
import '../widgets/neo_animations.dart';

class ExpenseEdit extends StatefulWidget {
  final int? expenseId;
  const ExpenseEdit({super.key, required this.expenseId});

  @override
  State<ExpenseEdit> createState() => _ExpenseEditState();
}

class _ExpenseEditState extends State<ExpenseEdit> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'makanan';
  String _selectedType = 'expected';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;

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

  final List<String> _categories = [
    'makanan',
    'transportasi',
    'hiburan',
    'school supply',
    'baju',
    'elektronik',
    'kesehatan',
  ];

  final List<Map<String, dynamic>> _quickAmounts = [
    {'label': '+10k', 'value': 10000},
    {'label': '+50k', 'value': 50000},
    {'label': '+100k', 'value': 100000},
    {'label': '-10k', 'value': -10000},
    {'label': '-50k', 'value': -50000},
  ];

  @override
  void initState() {
    super.initState();
    _loadExpenseData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _formatNumberString(String value) {
    if (value.isEmpty) return '';
    final number = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (number == 0) return '';
    final formatter = NumberFormat('#,###', 'id_ID');
    return formatter.format(number);
  }

  void _onAmountChanged(String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      _amountController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }
    final formatted = _formatNumberString(clean);
    _amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _addQuickAmount(int val) {
    final currentVal =
        int.tryParse(
          _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    final newVal = (currentVal + val).clamp(0, 9999999999);
    final formatted = _formatNumberString(newVal.toString());
    setState(() {
      _amountController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
  }

  String get _currentCurrencySymbol {
    switch (appCurrency.value) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      default:
        return 'Rp';
    }
  }

  Future<void> _loadExpenseData() async {
    try {
      final data = await getDataById(widget.expenseId!);
      if (data != null && mounted) {
        final category = data['category']?.toString().trim().toLowerCase();
        final type = data['type']?.toString().trim().toLowerCase();
        final amountNum = data['amount']?.toString() ?? '0';

        setState(() {
          _nameController.text = data['name'] ?? '';
          _amountController.text = _formatNumberString(amountNum);
          _selectedCategory = _categories.contains(category)
              ? category!
              : 'makanan';
          _selectedType = (type == 'expected' ||
                  type == 'unexpected' ||
                  type == 'others')
              ? type!
              : 'others';
          _selectedDate =
              DateTime.tryParse(data['date']?.toString() ?? '') ??
              DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static Future<Map<String, dynamic>?> getDataById(int id) async {
    final Database db = await DatabaseHelp.initDB();
    List<Map<String, dynamic>> result = await db.query(
      'my_table',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  BoxDecoration _neoBoxDecoration({
    Color color = Colors.white,
    double radius = 16,
    double shadowOffset = 4,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.black, width: 2.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black,
          offset: Offset(shadowOffset, shadowOffset),
          blurRadius: 0,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: NeoBouncy(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: _neoBoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
              radius: 12,
              shadowOffset: 2,
            ),
            child: Icon(
              Icons.arrow_back,
              color: isDark ? Colors.white : Colors.black,
              size: 22,
            ),
          ),
        ),
        title: Text(
          'Edit Expense',
          style: GoogleFonts.itim(
            color: colors.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: NeoBouncy(
              onTap: _confirmDelete,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: _neoBoxDecoration(
                  color: const Color(0xFFFF5D5D),
                  radius: 12,
                  shadowOffset: 2,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.black,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Amount Card
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 50),
                    child: _buildHeroAmountCard(isDark),
                  ),
                  const SizedBox(height: 18),

                  // Name Field
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Expense Name'),
                        _buildNameInput(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Category Selector
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Category'),
                        _buildCategorySelector(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Expense Type Selector
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Expense Type'),
                        _buildTypeSelector(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Date Selector
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 250),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Date'),
                        _buildDateSelector(isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save Button
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 300),
                    child: NeoButton(
                      text: 'UPDATE EXPENSE',
                      icon: Icons.check_circle_outline_rounded,
                      isLoading: _isSaving,
                      backgroundColor: const Color(0xFF5DF9FF),
                      onPressed: _updateExpense,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Delete Alternate Button
                  FadeSlideAnimation(
                    delay: const Duration(milliseconds: 350),
                    child: NeoButton(
                      text: 'DELETE EXPENSE',
                      icon: Icons.delete_forever_rounded,
                      backgroundColor: const Color(0xFFFFD6D6),
                      textColor: const Color(0xFFD90429),
                      borderColor: Colors.black,
                      onPressed: _confirmDelete,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: GoogleFonts.itim(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildHeroAmountCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 20,
        shadowOffset: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AMOUNT',
                style: GoogleFonts.itim(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.grey.shade600,
                ),
              ),
              if (_amountController.text.isNotEmpty)
                NeoBouncy(
                  onTap: () => setState(() => _amountController.clear()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear, size: 14, color: Colors.black),
                        SizedBox(width: 2),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EB5D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  _currentCurrencySymbol,
                  style: GoogleFonts.itim(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  onChanged: _onAmountChanged,
                  style: GoogleFonts.itim(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _quickAmounts.map((quick) {
                final isNegative = (quick['value'] as int) < 0;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: NeoBouncy(
                    onTap: () => _addQuickAmount(quick['value'] as int),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isNegative
                            ? (isDark ? const Color(0xFF4A2020) : const Color(0xFFFFE5E5))
                            : (isDark ? const Color(0xFF333333) : const Color(0xFFF0F4F8)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: Text(
                        quick['label'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isNegative
                              ? (isDark ? const Color(0xFFFF8A8A) : const Color(0xFFD90429))
                              : (isDark ? Colors.white : Colors.black),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameInput(bool isDark) {
    return Container(
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 16,
        shadowOffset: 3,
      ),
      child: TextField(
        controller: _nameController,
        style: GoogleFonts.itim(
          fontSize: 18,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.shopping_bag_outlined,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
          hintText: 'Expense name...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySelector(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          final catColor = _categoryColors[cat] ?? const Color(0xFF5DF9FF);
          final catIcon = _categoryIcons[cat] ?? Icons.category_rounded;

          return Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 6),
            child: NeoBouncy(
              onTap: () => setState(() => _selectedCategory = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? catColor
                      : (isDark ? const Color(0xFF242424) : Colors.white),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.black,
                    width: isSelected ? 2.5 : 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      offset: isSelected
                          ? const Offset(3, 3)
                          : const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(catIcon, size: 20, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      cat[0].toUpperCase() + cat.substring(1),
                      style: GoogleFonts.itim(
                        fontSize: 16,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTypeSelector(bool isDark) {
    final types = [
      {
        'key': 'expected',
        'title': 'Expected',
        'color': const Color(0xFFF9EB5D),
        'icon': Icons.check_circle_outline_rounded,
      },
      {
        'key': 'unexpected',
        'title': 'Unexpected',
        'color': const Color(0xFFFF5D5D),
        'icon': Icons.bolt_rounded,
      },
      {
        'key': 'others',
        'title': 'Others',
        'color': const Color(0xFF5D9BFF),
        'icon': Icons.stars_rounded,
      },
    ];

    return Row(
      children: types.map((item) {
        final key = item['key'] as String;
        final isSelected = _selectedType == key;
        final color = item['color'] as Color;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: NeoBouncy(
              onTap: () => setState(() => _selectedType = key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color
                      : (isDark ? const Color(0xFF242424) : Colors.white),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.black,
                    width: isSelected ? 2.5 : 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      offset: isSelected
                          ? const Offset(3, 3)
                          : const Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      item['icon'] as IconData,
                      size: 22,
                      color: Colors.black,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['title'] as String,
                      style: GoogleFonts.itim(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateSelector(bool isDark) {
    final now = DateTime.now();
    final isToday =
        _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final isYesterday =
        _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day - 1;

    String dateLabel = DateFormat('dd MMM yyyy').format(_selectedDate);
    if (isToday) {
      dateLabel = 'Today ($dateLabel)';
    } else if (isYesterday) {
      dateLabel = 'Yesterday ($dateLabel)';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 16,
        shadowOffset: 3,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.black,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dateLabel,
                  style: GoogleFonts.itim(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              NeoBouncy(
                onTap: _pickCustomDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9EB5D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: const Text(
                    'Pick',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: NeoBouncy(
                  onTap: () => setState(() => _selectedDate = DateTime.now()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isToday
                          ? const Color(0xFF5DF9FF)
                          : (isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Center(
                      child: Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark && !isToday
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NeoBouncy(
                  onTap: () => setState(
                    () => _selectedDate = DateTime.now().subtract(
                      const Duration(days: 1),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isYesterday
                          ? const Color(0xFF5DF9FF)
                          : (isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFF5F5F5)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Center(
                      child: Text(
                        'Yesterday',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark && !isYesterday
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF5DF9FF),
              onPrimary: Colors.black,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(6, 6),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5D5D),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.black,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete Expense?',
                  style: GoogleFonts.itim(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to permanently remove "${_nameController.text}"?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: NeoBouncy(
                        onTap: () => Navigator.pop(context, false),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(3, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: NeoBouncy(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5D5D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(3, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Delete',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete == true) {
      await DatabaseHelp.deleteTs(widget.expenseId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF06D6A0),
          content: const Text(
            'Expense deleted successfully!',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _updateExpense() async {
    final cleanName = _nameController.text.trim();
    final cleanAmount = int.tryParse(
          _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;

    if (cleanName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFFFF5D5D),
          content: const Text(
            'Please enter an expense name!',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    if (cleanAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFFFF5D5D),
          content: const Text(
            'Please enter a valid amount!',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final formattedDate =
          "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

      await DatabaseHelp.updateTs(
        widget.expenseId,
        cleanName,
        cleanAmount,
        _selectedCategory,
        _selectedType,
        formattedDate,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF06D6A0),
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.black),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Expense updated successfully!',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFFFF5D5D),
          content: Text(
            'Failed to update: $e',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
  }
}
