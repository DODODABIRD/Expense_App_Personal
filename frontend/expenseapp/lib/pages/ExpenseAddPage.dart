import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

class ExpenseAddPage extends StatefulWidget {
  const ExpenseAddPage({super.key});

  @override
  State<ExpenseAddPage> createState() => _ExpenseAddPageState();
}

class _ExpenseAddPageState extends State<ExpenseAddPage> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = 'makanan';
  String _selectedType = 'expected';
  DateTime _selectedDate = DateTime.now();

  Future<void> _saveToMongo(Map<String, dynamic> expenseData) async {
    final db = await mongo.Db.create(
      "mongodb+srv://orlando:34313431@do2d.ypoboeu.mongodb.net/expense",
    );

    try {
      await db.open();
      var collection = db.collection('user0');

      // Insert the map directly
      await collection.insertOne(expenseData);
      print("Cloud Sync: Success");
    } catch (e) {
      print("Cloud Sync Error: $e");
      // We rethrow to handle it in the main save function
      rethrow;
    } finally {
      await db.close();
    }
  }

  final Map<String, IconData> _categoryIcons = {
    'makanan': Icons.fastfood,
    'school supply': Icons.school,
    'baju': Icons.checkroom,
    'elektronik': Icons.devices,
    'transportasi': Icons.directions_car,
    'kesehatan': Icons.medical_services,
    'hiburan': Icons.theater_comedy,
  };

  final List<String> _categories = [
    'makanan',
    'school supply',
    'baju',
    'elektronik',
    'transportasi',
    'kesehatan',
    'hiburan',
  ];

  final Map<String, String> _types = {
    'expected': 'Expected (Kuning)',
    'unexpected': 'Unexpected (Merah)',
    'others': 'Others (Biru)',
  };

  // Mendapatkan path file lokal
  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/expenses.json');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Expense',
          style: GoogleFonts.itim(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Expense Name'),
            _buildTextField(_nameController, 'U beli apa?'),
            const SizedBox(height: 20),

            _buildLabel('Amount (Rp)'),
            _buildTextField(_amountController, 'e.g. 50.000', isNumber: true),
            const SizedBox(height: 20),

            _buildLabel('Category'),
            _buildDropdown(
              value: _selectedCategory,
              items: _categories,
              onChanged: (val) => setState(() => _selectedCategory = val!),
            ),
            const SizedBox(height: 20),

            _buildLabel('Expense Type'),
            _buildDropdown(
              value: _selectedType,
              items: _types.keys.toList(),
              displayMap: _types,
              onChanged: (val) => setState(() => _selectedType = val!),
            ),
            const SizedBox(height: 20),

            _buildLabel('Date'),
            GestureDetector(
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
                padding: const EdgeInsets.all(15),
                decoration: _neoBoxDecoration(Colors.white),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
                      style: GoogleFonts.itim(fontSize: 18),
                    ),
                    const Icon(Icons.calendar_today, color: Colors.black),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Save Button
            GestureDetector(
              onTap: _saveExpense,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: _neoBoxDecoration(const Color(0xFF5DF9FF)),
                child: Center(
                  child: Text(
                    'SAVE EXPENSE',
                    style: GoogleFonts.itim(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 5),
      child: Text(
        label,
        style: GoogleFonts.itim(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
  }) {
    return Container(
      decoration: _neoBoxDecoration(Colors.white),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: GoogleFonts.itim(fontSize: 18),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(15),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    Map<String, String>? displayMap,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: _neoBoxDecoration(Colors.white),
      // clipBehavior ensures the child doesn't bleed over the border radius
      clipBehavior: Clip.antiAlias,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.black,
            size: 30,
          ),
          // This ensures the pop-up menu also has rounded corners
          borderRadius: BorderRadius.circular(15),
          // This ensures the pop-up menu background is white
          dropdownColor: Colors.white,
          items: items.map((String item) {
            IconData? iconData = _categoryIcons[item];

            return DropdownMenuItem<String>(
              value: item,
              child: Row(
                children: [
                  if (iconData != Null) ...[
                    Icon(iconData, color: Colors.black, size: 24),
                    const SizedBox(width: 12),
                  ],

                  Text(
                    displayMap != null ? displayMap[item]! : item,
                    style: GoogleFonts.itim(fontSize: 18),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  BoxDecoration _neoBoxDecoration(Color color) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.black, width: 3),
      boxShadow: const [
        BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
      ],
    );
  }

  Future<void> _saveExpense() async {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields!')));
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
    // 1. Prepare Data
    final newEntry = {
      "name": _nameController.text,
      "amount": _amountController.text,
      "date": "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}",
      "category": _selectedCategory,
      "type": _selectedType,
      "createdAt": DateTime.now().toIso8601String(),
    };

    // 2. Save Locally FIRST
    // We do this first so the map is "clean" (no ObjectId yet)
    final file = await _localFile;
    List<dynamic> jsonData = [];
    if (await file.exists()) {
      final String content = await file.readAsString();
      jsonData = json.decode(content);
    }
    jsonData.add(newEntry);
    await file.writeAsString(json.encode(jsonData));

    // 3. Save to MongoDB Atlas using a CLONE of the map
    // Using Map.from() ensures MongoDB's _id doesn't mess up our local newEntry
    await _saveToMongo(Map.from(newEntry));

      // Close Loading
      if (mounted) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Saved Locally & Synced to Cloud!'),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      // Close Loading on Error
      if (mounted) Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Failed to sync. Check internet. Error: $e'),
        ),
      );
    }
  }
}
