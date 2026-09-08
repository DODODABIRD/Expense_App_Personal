import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/ApiService.dart';
import '../services/databaseHelper.dart';

class ReceiptScanPage extends StatefulWidget {
  const ReceiptScanPage({super.key});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptItemDraft {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final int quantity;
  String category;
  String type;
  bool checked;

  _ReceiptItemDraft({
    required this.nameController,
    required this.amountController,
    required this.quantity,
    required this.category,
    required this.type,
    this.checked = true,
  });

  int get amount =>
      int.tryParse(amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;
}

class _ReceiptScanPageState extends State<ReceiptScanPage> {
  final _picker = ImagePicker();

  static const _categories = [
    'makanan',
    'school supply',
    'baju',
    'elektronik',
    'transportasi',
    'kesehatan',
    'hiburan',
  ];

  static const _types = {
    'expected': 'Expected',
    'unexpected': 'Unexpected',
    'others': 'Others',
  };

  File? _imageFile;
  bool _isProcessing = false;
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();
  List<_ReceiptItemDraft> _items = [];

  @override
  void dispose() {
    for (final item in _items) {
      item.nameController.dispose();
      item.amountController.dispose();
    }
    super.dispose();
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
            ? 'Could not open the camera: $error. Emulators without a '
                  'configured virtual camera (AVD "Camera" set to None) or '
                  'without the Camera app installed will fail here - try '
                  'the Gallery option or a real device instead.'
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
      _errorMessage = null;
    });

    try {
      final rawItems = await Throw.parseReceipt(_imageFile!);
      for (final item in _items) {
        item.nameController.dispose();
        item.amountController.dispose();
      }
      setState(() {
        _items = rawItems.map((item) {
          final category = item['category']?.toString() ?? 'makanan';
          final type = item['type']?.toString() ?? 'others';
          return _ReceiptItemDraft(
            nameController: TextEditingController(
              text: item['name']?.toString() ?? 'Unknown item',
            ),
            amountController: TextEditingController(
              text: (item['amount'] ?? 0).toString(),
            ),
            quantity: item['quantity'] is int
                ? item['quantity'] as int
                : int.tryParse(item['quantity']?.toString() ?? '1') ?? 1,
            category: _categories.contains(category) ? category : 'makanan',
            type: _types.containsKey(type) ? type : 'others',
          );
        }).toList();
      });
    } catch (error) {
      setState(() => _errorMessage = 'Could not scan receipt: $error');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  int get _selectedTotal => _items
      .where((item) => item.checked)
      .fold(0, (total, item) => total + item.amount);

  Future<void> _saveSelectedItems() async {
    final selected = _items.where((item) => item.checked).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one item to save.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
      for (final item in selected) {
        await DatabaseHelp.insertData(
          item.nameController.text.trim().isEmpty
              ? 'Unknown item'
              : item.nameController.text.trim(),
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
          backgroundColor: Colors.green,
          content: Text('Saved ${selected.length} item(s) from receipt.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save items: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(
          'Scan Receipt',
          style: GoogleFonts.itim(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 26,
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
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImagePicker(),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    if (_isProcessing) ...[
                      const SizedBox(height: 24),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 8),
                      const Center(child: Text('Reading receipt...')),
                    ],
                    if (!_isProcessing && _items.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildDatePicker(),
                      const SizedBox(height: 16),
                      Text(
                        'Detected items',
                        style: GoogleFonts.itim(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._items.map(_buildItemTile),
                    ],
                  ],
                ),
              ),
            ),
            if (!_isProcessing && _items.isNotEmpty) _buildSaveBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          if (_imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(_imageFile!, height: 180, fit: BoxFit.cover),
            )
          else
            Container(
              height: 120,
              alignment: Alignment.center,
              child: const Text('Take or pick a photo of your receipt'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('dd MMM yyyy').format(_selectedDate),
              style: const TextStyle(color: Colors.black),
            ),
            const Icon(Icons.calendar_today, color: Colors.black, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(_ReceiptItemDraft item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.checked,
            onChanged: (value) =>
                setState(() => item.checked = value ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: item.nameController,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
                Row(
                  children: [
                    Text('x${item.quantity}  '),
                    Expanded(
                      child: TextField(
                        controller: item.amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixText: 'Rp ',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    DropdownButton<String>(
                      value: item.category,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => item.category = value);
                        }
                      },
                    ),
                    DropdownButton<String>(
                      value: item.type,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: _types.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => item.type = value);
                      },
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

  Widget _buildSaveBar() {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: Colors.black, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total: ${formatter.format(_selectedTotal)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _saveSelectedItems,
            child: const Text('Save Selected'),
          ),
        ],
      ),
    );
  }
}
