import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/ApiService.dart';
import '../services/databaseHelper.dart';
import '../widgets/neo_animations.dart';

class ReceiptScanPage extends StatefulWidget {
  const ReceiptScanPage({super.key});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptItemDraft {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final int originalQuantity;
  int selectedQuantity;
  int unitPrice;
  String category;
  String type;
  bool checked = true;

  _ReceiptItemDraft({
    required this.nameController,
    required this.amountController,
    required this.originalQuantity,
    required this.selectedQuantity,
    required this.unitPrice,
    required this.category,
    required this.type,
  });

  int get amount =>
      int.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;
}

class _ReceiptScanPageState extends State<ReceiptScanPage> {
  final _picker = ImagePicker();

  static const _categories = [
    'makanan',
    'transportasi',
    'hiburan',
    'school supply',
    'baju',
    'elektronik',
    'kesehatan',
  ];

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

  static const _types = {
    'expected': 'Expected',
    'unexpected': 'Unexpected',
    'others': 'Others',
  };

  File? _imageFile;
  bool _isProcessing = false;
  bool _isCancelling = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  List<_ReceiptItemDraft> _items = [];
  ReceiptScanOperation? _scanOperation;
  double _scanProgress = 0;
  String _scanStatus = '';
  List<String> _scanLogs = [];

  @override
  void dispose() {
    _scanOperation?.cancel();
    for (final item in _items) {
      item.nameController.dispose();
      item.amountController.dispose();
    }
    super.dispose();
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

  String get _currentCurrencyLocale {
    switch (appCurrency.value) {
      case 'USD':
        return 'en_US';
      case 'EUR':
        return 'de_DE';
      default:
        return 'id_ID';
    }
  }

  int get _currentCurrencyDecimalDigits {
    switch (appCurrency.value) {
      case 'USD':
      case 'EUR':
        return 2;
      default:
        return 0;
    }
  }

  BoxDecoration _neoBoxDecoration({
    Color color = Colors.white,
    double radius = 16,
    double shadowOffset = 4,
    double borderWidth = 2.5,
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

  Future<void> _pickImage(ImageSource source) async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 65,
        maxWidth: 1600,
        maxHeight: 1600,
      );
    } catch (error) {
      setState(
        () => _errorMessage = source == ImageSource.camera
            ? 'Could not open the camera: $error.'
            : 'Could not open the gallery: $error',
      );
      return;
    }
    if (picked == null) return;
    setState(() {
      _imageFile = File(picked!.path);
      _errorMessage = null;
    });
    await _scanReceipt();
  }

  Future<void> _scanReceipt() async {
    if (_imageFile == null) return;
    setState(() {
      _isProcessing = true;
      _isCancelling = false;
      _scanProgress = 0;
      _scanStatus = 'Preparing receipt image';
      _scanLogs = ['Preparing receipt image'];
      _errorMessage = null;
    });

    final operation = Throw.parseReceipt(
      _imageFile!,
      onProgress: _updateScanProgress,
    );
    _scanOperation = operation;

    try {
      final parsedReceipt = await operation.future;
      final rawItems = parsedReceipt['items'] as List<Map<String, dynamic>>;
      final detectedDate = DateTime.tryParse(
        parsedReceipt['date']?.toString() ?? '',
      );
      for (final item in _items) {
        item.nameController.dispose();
        item.amountController.dispose();
      }
      setState(() {
        if (detectedDate != null) _selectedDate = detectedDate;
        _items = rawItems.map((item) {
          final category = item['category']?.toString() ?? 'makanan';
          final type = item['type']?.toString() ?? 'others';
          final rawAmount = item['amount'] is int
              ? item['amount'] as int
              : int.tryParse(item['amount']?.toString() ?? '0') ?? 0;
          final qty = item['quantity'] is int
              ? item['quantity'] as int
              : int.tryParse(item['quantity']?.toString() ?? '1') ?? 1;
          final validQty = qty > 0 ? qty : 1;
          final unitPrice = (rawAmount / validQty).round();
          final formatter = NumberFormat('#,###', 'id_ID');

          return _ReceiptItemDraft(
            nameController: TextEditingController(
              text: item['name']?.toString() ?? 'Unknown item',
            ),
            amountController: TextEditingController(
              text: formatter.format(rawAmount),
            ),
            originalQuantity: validQty,
            selectedQuantity: validQty,
            unitPrice: unitPrice > 0 ? unitPrice : rawAmount,
            category: _categories.contains(category) ? category : 'makanan',
            type: _types.containsKey(type) ? type : 'others',
          );
        }).toList();

        final provider = parsedReceipt['provider'] == 'azure'
            ? 'Azure AI Document Intelligence'
            : 'Gemini AI';
        _scanStatus = 'Processed with $provider';
        if (_scanLogs.isEmpty || _scanLogs.last != _scanStatus) {
          _scanLogs = [..._scanLogs, _scanStatus];
        }
      });
    } on ReceiptScanCancelledException {
      if (mounted) {
        setState(() {
          _scanStatus = 'Scan cancelled';
          _scanLogs = [..._scanLogs, _scanStatus];
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not scan receipt: $error');
      }
    } finally {
      if (identical(_scanOperation, operation)) _scanOperation = null;
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isCancelling = false;
        });
      }
    }
  }

  void _updateScanProgress(double progress, String message) {
    if (!mounted) return;
    setState(() {
      _scanProgress = progress.clamp(0.0, 1.0).toDouble();
      _scanStatus = message;
      if (_scanLogs.isEmpty || _scanLogs.last != message) {
        _scanLogs = [..._scanLogs, message];
      }
    });
  }

  void _cancelScan() {
    if (_scanOperation == null || _isCancelling) return;
    setState(() {
      _isCancelling = true;
      _scanStatus = 'Cancelling scan';
      _scanLogs = [..._scanLogs, _scanStatus];
    });
    _scanOperation!.cancel();
  }

  int get _selectedTotal => _items
      .where((item) => item.checked)
      .fold(0, (total, item) => total + item.amount);

  void _toggleSelectAll() {
    final allSelected = _items.every((item) => item.checked);
    setState(() {
      for (final item in _items) {
        item.checked = !allSelected;
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      final removed = _items.removeAt(index);
      removed.nameController.dispose();
      removed.amountController.dispose();
    });
  }

  void _changeQuantity(_ReceiptItemDraft item, int newQty) {
    if (newQty < 1) return;
    setState(() {
      item.selectedQuantity = newQty;
      final calculatedAmount = item.unitPrice * newQty;
      final formatter = NumberFormat('#,###', 'id_ID');
      item.amountController.value = TextEditingValue(
        text: formatter.format(calculatedAmount),
        selection: TextSelection.collapsed(
          offset: formatter.format(calculatedAmount).length,
        ),
      );
    });
  }

  void _onAmountChanged(_ReceiptItemDraft item, String val) {
    final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) {
      item.amountController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      setState(() {});
      return;
    }
    final number = int.tryParse(clean) ?? 0;
    if (item.selectedQuantity > 0) {
      item.unitPrice = (number / item.selectedQuantity).round();
    }
    final formatter = NumberFormat('#,###', 'id_ID');
    final formatted = formatter.format(number);
    item.amountController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() {});
  }

  Future<void> _saveSelectedItems() async {
    final selected = _items.where((item) => item.checked).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFFFF5D5D),
          content: const Text(
            'Select at least one item to save.',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.black)),
    );

    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      for (final item in selected) {
        String itemName = item.nameController.text.trim();
        if (itemName.isEmpty) itemName = 'Unknown item';
        
        // If the user modified the portions eaten e.g. 2 out of 5 burgers
        if (item.selectedQuantity < item.originalQuantity) {
          itemName = '$itemName (${item.selectedQuantity}/${item.originalQuantity} porsi)';
        }

        await DatabaseHelp.insertData(
          itemName,
          item.amount,
          dateStr,
          item.category,
          item.type,
        );
      }
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFF06D6A0),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.black),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saved ${selected.length} item(s) from receipt!',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          backgroundColor: const Color(0xFFFF5D5D),
          content: Text(
            'Could not save items: $error',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
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
          'Scan Receipt',
          style: GoogleFonts.itim(
            color: colors.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeSlideAnimation(
                      delay: const Duration(milliseconds: 50),
                      child: _buildImagePicker(isDark),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: _neoBoxDecoration(
                          color: const Color(0xFFFFD6D6),
                          radius: 12,
                          shadowOffset: 2,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFD90429)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Color(0xFFD90429),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_isProcessing) ...[
                      const SizedBox(height: 18),
                      FadeSlideAnimation(
                        child: _buildProcessingPanel(isDark),
                      ),
                    ],
                    if (!_isProcessing && _items.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      FadeSlideAnimation(
                        delay: const Duration(milliseconds: 100),
                        child: _buildDatePicker(isDark),
                      ),
                      const SizedBox(height: 18),
                      FadeSlideAnimation(
                        delay: const Duration(milliseconds: 150),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Detected Items (${_items.length})',
                              style: GoogleFonts.itim(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                              ),
                            ),
                            NeoBouncy(
                              onTap: _toggleSelectAll,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: _neoBoxDecoration(
                                  color: const Color(0xFF5DF9FF),
                                  radius: 10,
                                  shadowOffset: 2,
                                  borderWidth: 1.8,
                                ),
                                child: Text(
                                  _items.every((item) => item.checked)
                                      ? 'Deselect All'
                                      : 'Select All',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._items.asMap().entries.map((entry) {
                        return FadeSlideAnimation(
                          delay: Duration(
                            milliseconds: (entry.key * 40).clamp(0, 300),
                          ),
                          child: _buildItemTile(entry.key, entry.value, isDark),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            if (!_isProcessing && _items.isNotEmpty) _buildSaveBar(isDark),
          ],
        ),
      ),
    );
  }

  void _openImagePreview(BuildContext context) {
    if (_imageFile == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ReceiptImagePreviewModal(
            imageFile: _imageFile!,
            animation: animation,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildImagePicker(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 20,
        shadowOffset: 4,
      ),
      child: Column(
        children: [
          if (_imageFile != null)
            Stack(
              children: [
                GestureDetector(
                  onTap: () => _openImagePreview(context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Hero(
                        tag: 'receipt_image_preview_hero',
                        child: Image.file(
                          _imageFile!,
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom-left inspection badge
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () => _openImagePreview(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DF9FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black, width: 2),
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
                          const Icon(
                            Icons.zoom_in_rounded,
                            size: 16,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap untuk Preview 🔍',
                            style: GoogleFonts.itim(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top-right close/remove button
                Positioned(
                  top: 8,
                  right: 8,
                  child: NeoBouncy(
                    onTap: () => setState(() => _imageFile = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5D5D),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              height: 130,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9FBFD),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.black,
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignCenter,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9EB5D),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 28,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Snap or upload your receipt photo',
                    style: GoogleFonts.itim(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: NeoBouncy(
                  onTap: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: _neoBoxDecoration(
                      color: const Color(0xFF5DF9FF),
                      radius: 12,
                      shadowOffset: 3,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded, color: Colors.black, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Camera',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NeoBouncy(
                  onTap: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: _neoBoxDecoration(
                      color: const Color(0xFFF9EB5D),
                      radius: 12,
                      shadowOffset: 3,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_rounded, color: Colors.black, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Gallery',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
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

  Widget _buildProcessingPanel(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 18,
        shadowOffset: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scanStatus,
                      style: GoogleFonts.itim(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      'AI Scanning in progress...',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9EB5D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  '${(_scanProgress * 100).round()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF333333) : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _scanProgress,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5DF9FF)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._scanLogs.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    entry.key == _scanLogs.length - 1
                        ? Icons.bolt_rounded
                        : Icons.check_circle_rounded,
                    size: 18,
                    color: entry.key == _scanLogs.length - 1
                        ? const Color(0xFF5DF9FF)
                        : const Color(0xFF06D6A0),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: NeoBouncy(
              onTap: _isCancelling ? null : _cancelScan,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  _isCancelling ? 'Cancelling...' : 'Cancel Scan',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 14,
        shadowOffset: 3,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.black),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RECEIPT DATE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy').format(_selectedDate),
                    style: GoogleFonts.itim(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ),
          NeoBouncy(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF9EB5D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black, width: 1.5),
              ),
              child: const Text(
                'Change',
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
    );
  }

  Widget _buildItemTile(int index, _ReceiptItemDraft item, bool isDark) {
    final catColor = _categoryColors[item.category] ?? const Color(0xFF5DF9FF);
    final formatter = NumberFormat('#,###', 'id_ID');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _neoBoxDecoration(
        color: isDark ? const Color(0xFF242424) : Colors.white,
        radius: 16,
        shadowOffset: 3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Custom Neo-checkbox
          NeoBouncy(
            onTap: () => setState(() => item.checked = !item.checked),
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 4, right: 10),
              decoration: BoxDecoration(
                color: item.checked ? const Color(0xFF5DF9FF) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: item.checked
                  ? const Icon(Icons.check, size: 20, color: Colors.black)
                  : null,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item Name Header & Delete button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: item.nameController,
                        style: GoogleFonts.itim(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Item name...',
                        ),
                      ),
                    ),
                    NeoBouncy(
                      onTap: () => _removeItem(index),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1.2),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Portion & Quantity Stepper Bar (e.g. 2 / 5 burger)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF333333) : const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.restaurant_menu_rounded, size: 16, color: Colors.black87),
                          const SizedBox(width: 6),
                          Text(
                            item.originalQuantity > 1
                                ? 'Porsi: ${item.selectedQuantity} dari ${item.originalQuantity}'
                                : 'Qty: ${item.selectedQuantity}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Minus button
                          NeoBouncy(
                            onTap: item.selectedQuantity > 1
                                ? () => _changeQuantity(item, item.selectedQuantity - 1)
                                : null,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: item.selectedQuantity > 1
                                    ? Colors.white
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black, width: 1.2),
                              ),
                              child: const Icon(Icons.remove, size: 14, color: Colors.black),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '${item.selectedQuantity}x',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          // Plus button
                          NeoBouncy(
                            onTap: () => _changeQuantity(item, item.selectedQuantity + 1),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: const Color(0xFF5DF9FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.black, width: 1.2),
                              ),
                              child: const Icon(Icons.add, size: 14, color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Amount Input Box with unit price hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9EB5D),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Text(
                          _currentCurrencySymbol,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: item.amountController,
                          keyboardType: TextInputType.number,
                          onChanged: (val) => _onAmountChanged(item, val),
                          style: GoogleFonts.itim(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '0',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                      if (item.selectedQuantity > 1 || item.originalQuantity > 1)
                        Text(
                          '(@ $_currentCurrencySymbol${formatter.format(item.unitPrice)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Category & Type Dropdowns
                Row(
                  children: [
                    // Category Badge Dropdown
                    Expanded(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: catColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: item.category,
                            isExpanded: true,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 20),
                            dropdownColor: Colors.white,
                            items: _categories.map((c) {
                              final icon = _categoryIcons[c] ?? Icons.category_rounded;
                              return DropdownMenuItem(
                                value: c,
                                child: Row(
                                  children: [
                                    Icon(icon, size: 16, color: Colors.black),
                                    const SizedBox(width: 6),
                                    Text(
                                      c[0].toUpperCase() + c.substring(1),
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => item.category = val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Type Badge Dropdown
                    Expanded(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: item.type == 'expected'
                              ? const Color(0xFFF9EB5D)
                              : (item.type == 'unexpected'
                                  ? const Color(0xFFFF5D5D)
                                  : const Color(0xFF5D9BFF)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black, width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: item.type,
                            isExpanded: true,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 20),
                            dropdownColor: Colors.white,
                            items: _types.entries.map((e) {
                              return DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => item.type = val);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar(bool isDark) {
    final formatter = NumberFormat.currency(
      locale: _currentCurrencyLocale,
      symbol: _currentCurrencySymbol,
      decimalDigits: _currentCurrencyDecimalDigits,
    );
    final count = _items.where((item) => item.checked).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: const Border(top: BorderSide(color: Colors.black, width: 2.5)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, -3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TOTAL SELECTED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  formatter.format(_selectedTotal * appExchangeRate.value),
                  style: GoogleFonts.itim(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          NeoButton(
            text: 'SAVE ($count)',
            icon: Icons.check_circle_outline_rounded,
            height: 48,
            fontSize: 16,
            backgroundColor: const Color(0xFF5DF9FF),
            onPressed: _saveSelectedItems,
          ),
        ],
      ),
    );
  }
}

class _ReceiptImagePreviewModal extends StatelessWidget {
  final File imageFile;
  final Animation<double> animation;

  const _ReceiptImagePreviewModal({
    required this.imageFile,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred & Darkened Backdrop
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: Colors.black.withValues(alpha: 0.82),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Navigation Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Badge Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DF9FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black, width: 2.2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset(3, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.black,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'RECEIPT PREVIEW',
                              style: GoogleFonts.itim(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Red Neobrutalist Close Button ('X')
                      NeoBouncy(
                        scaleFactor: 0.88,
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5D5D),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black,
                                offset: Offset(3, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Hero Zoomable Image Container
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4.5,
                        clipBehavior: Clip.none,
                        child: Hero(
                          tag: 'receipt_image_preview_hero',
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.black, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(6, 6),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(17),
                              child: Image.file(
                                imageFile,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Hint Pill
                Padding(
                  padding: const EdgeInsets.only(bottom: 16, top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9EB5D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black, width: 2),
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
                        const Icon(
                          Icons.pinch_rounded,
                          size: 18,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pinch untuk zoom • Cek detail strukmu',
                          style: GoogleFonts.itim(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
}
