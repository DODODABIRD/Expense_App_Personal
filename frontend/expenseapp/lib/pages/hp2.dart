import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'ExpenseAddPage.dart';
import 'package:intl/intl.dart';

class HomePage2 extends StatelessWidget {
  const HomePage2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      appBar: BarApp(),
      body: ListWithCards(),
      floatingActionButton: NeoAddButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  AppBar BarApp() {
    return AppBar(
      toolbarHeight: 100,
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      title: const Text('Expense Tracker'),
      titleTextStyle: GoogleFonts.itim(
        color: const Color.fromARGB(255, 0, 0, 0),
        fontSize: 35,
        fontWeight: FontWeight.bold,
        shadows: <Shadow>[
          const Shadow(
            offset: Offset(5.0, 5.0),
            blurRadius: 8.0,
            color: Color.fromARGB(158, 0, 0, 0),
          ),
        ],
      ),
      centerTitle: true,
    );
  }
}

class ExpenseModel {
  final String name;
  final String amount;
  final String date;
  final String category;
  final String type;

  ExpenseModel({
    required this.name,
    required this.amount,
    required this.date,
    required this.category,
    required this.type,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      name: map['name'] ?? 'Unknown',
      amount: map['amount']?.toString() ?? '0',
      date: map['date'] ?? '',
      category: map['category'] ?? 'general',
      type: map['type'] ?? 'expected',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'date': date,
      'category': category,
      'type': type,
    };
  }
}

class ListWithCards extends StatefulWidget {
  @override
  _ListWithCardsState createState() => _ListWithCardsState();
}

class _ListWithCardsState extends State<ListWithCards> {
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Mendapatkan path file lokal
  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/expenses.json');
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final file = await _localFile;
      String jsonString;

      if (await file.exists()) {
        // Jika file lokal ada, baca dari sana
        jsonString = await file.readAsString();
      } else {
        // Jika belum ada, baca dari assets lalu simpan ke lokal untuk pertama kali
        jsonString = await rootBundle.loadString('assets/json_data/data.json');
        await file.writeAsString(jsonString);
      }

      final List<dynamic> jsonData = json.decode(jsonString);
      setState(() {
        _expenses = jsonData.map((item) => ExpenseModel.fromMap(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_expenses.isEmpty) {
      return const Center(child: Text('Data Kosong'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _expenses.length,
        itemBuilder: (context, index) {
          // Kita balik urutannya agar data terbaru di atas
          final expense = _expenses[_expenses.length - 1 - index];
          return CardList(expense: expense);
        },
      ),
    );
  }
}

class CardList extends StatelessWidget {
  final ExpenseModel expense;

  const CardList({super.key, required this.expense});

  Color _getBackgroundColor() {
    switch (expense.type.toLowerCase()) {
      case 'expected':
        return const Color(0xFFF9EB5D);
      case 'unexpected':
        return const Color(0xFFFF5D5D);
      case 'others':
        return const Color(0xFF5D9BFF);
      default:
        return const Color(0xFFD9D9D9);
    }
  }

  IconData _getCategoryIcon() {
    switch (expense.category.toLowerCase()) {
      case 'makanan':
        return Icons.fastfood;
      case 'school supply':
        return Icons.school;
      case 'baju':
        return Icons.checkroom;
      case 'elektronik':
        return Icons.devices;
      case 'transportasi':
        return Icons.directions_car;
      case 'kesehatan':
        return Icons.medical_services;
      case 'hiburan':
        return Icons.celebration;
      default:
        return Icons.receipt_long;
    }
  }
  // BOX BUAT NGASIH LIAT BARANG2 NYA
  @override
  Widget build(BuildContext context) {
    final double amountValue = double.tryParse(expense.amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );
    return GestureDetector(
      // onDoubleTap: await Navigator.push(
      //   context,
      //   MaterialPageRoute(builder: (context)=> const ExpenseAddPage())
      // ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 25),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(8, 8)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Icon(_getCategoryIcon(), color: Colors.black, size: 35),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.name,
                    style: GoogleFonts.itim(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    formatter.format(amountValue).replaceAll(',', '.'),
                    style: GoogleFonts.itim(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(expense.date, style: GoogleFonts.itim(fontSize: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NeoAddButton extends StatelessWidget {
  const NeoAddButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF5DF9FF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: RawMaterialButton(
        onPressed: () async {
          // Tunggu sampai user kembali dari halaman Add
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ExpenseAddPage()),
          );

          // Refresh data setelah kembali
          final state = context.findAncestorStateOfType<_ListWithCardsState>();
          state?._loadData();

          // Karena NeoAddButton di luar ListWithCards, kita perlu cara untuk memberitahu ListWithCards.
          // Cara termudah: restart aplikasi atau gunakan GlobalKey/Provider.
          // Namun di sini kita bisa memaksa rebuild via Navigator result atau callback.
          // Mari kita buat navigasi yang lebih cerdas.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage2()),
          );
        },
        child: const Icon(
          Icons.add,
          color: Colors.black,
          size: 35,
          weight: 900.0,
        ),
      ),
    );
  }
}
