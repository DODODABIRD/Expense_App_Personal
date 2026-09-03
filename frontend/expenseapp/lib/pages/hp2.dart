import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ExpenseAddPage.dart';
import 'package:intl/intl.dart';
import '../services/databaseHelper.dart';
import '../services/ApiService.dart';
import 'ExpenseEdit.dart';



// FIXME


/*
Database Logic

If Database Doesnt Exist
  Create Database
  Initialize Database

If Database Empty:
  Display "List Is Empty, create new Expense"
Else
  For Item in Database:
    var item = databaseItem[index]
    make cardlist of Ite

*/














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
      toolbarHeight: 0,
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      centerTitle: true,
    );
  }
}

class ExpenseModel {
  final int? id;
  final String name;
  final int amount;
  final DateTime date;
  final String category;
  final String type;

  ExpenseModel({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.category,
    required this.type,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] as int?,
      name: map['name'] ?? 'Unknown',
      amount: map['amount'] is int
          ? map['amount'] as int
          : int.tryParse(map['amount']?.toString() ?? '0') ?? 0,
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      category: map['category'] ?? 'general',
      type: map['type'] ?? 'expected',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'date': date.toIso8601String().substring(0, 10),
      'category': category,
      'type': type,
    };
  }
}

class ListWithCards extends StatefulWidget {
  @override
  _ListWithCardsState createState() => _ListWithCardsState();
}

class _ListWithCardsState extends State<ListWithCards>
  with WidgetsBindingObserver {
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;
  ExpenseSort _sort = ExpenseSort.dateNewest;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPendingExpenses();
    }
  }

  Future<void> _syncPendingExpenses() async {
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      await Throw.syncPendingExpenses();

      if (!mounted) return;

      final data = await DatabaseHelp.getData();
      setState(() {
        _expenses = data.map((item) => ExpenseModel.fromMap(item)).toList();
      });
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await DatabaseHelp.initDB();
      unawaited(_syncPendingExpenses());
    } catch(e){
      print("Nigga The Database Aint Initialized");
    }



    try {
      // 1. Panggil getData() langsung dari class karena sudah static
      // Tidak perlu simpan hasil initDB() ke variabel baru
      final List<Map<String, dynamic>> data = await DatabaseHelp.getData();

      setState(() {
        // 2. Konversi List<Map> menjadi List<ExpenseModel>
        _expenses = data.map((item) => ExpenseModel.fromMap(item)).toList();
        _isLoading = false;
      });

    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }

  List<ExpenseModel> get _sortedExpenses {
    final result = [..._expenses];

    result.sort((a, b) {
      switch (_sort) {
        case ExpenseSort.dateNewest:
          return b.date.compareTo(a.date);
        case ExpenseSort.dateOldest:
          return a.date.compareTo(b.date);
        case ExpenseSort.amountHighest:
          return b.amount.compareTo(a.amount);
        case ExpenseSort.amountLowest:
          return a.amount.compareTo(b.amount);
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_expenses.isEmpty) {
      return const Center(child: Text('Data Kosong'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 8, 25, 4),
          child: Row(
            children: [
              const Icon(Icons.sort, size: 22),
              const SizedBox(width: 8),
              Text(
                'Sort by',
                style: GoogleFonts.itim(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ExpenseSort>(
                    value: _sort,
                    isDense: true,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    items: const [
                      DropdownMenuItem(
                        value: ExpenseSort.dateNewest,
                        child: Text('Newest'),
                      ),
                      DropdownMenuItem(
                        value: ExpenseSort.dateOldest,
                        child: Text('Oldest'),
                      ),
                      DropdownMenuItem(
                        value: ExpenseSort.amountHighest,
                        child: Text('Highest'),
                      ),
                      DropdownMenuItem(
                        value: ExpenseSort.amountLowest,
                        child: Text('Lowest'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sort = value);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _sortedExpenses.length,
              itemBuilder: (context, index) {
                return CardList(
                  expense: _sortedExpenses[index],
                  onRefresh: _loadData,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class CardList extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onRefresh;

  const CardList({super.key, required this.expense, required this.onRefresh});

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
    final amountValue = expense.amount;
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );
    return Container(
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
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 40),
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
                        Text(
                          DateFormat('dd MMM yyyy', 'id_ID').format(expense.date),
                          style: GoogleFonts.itim(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -8,
              bottom: -8,
              child: IconButton(
                tooltip: 'Edit expense',
                icon: const Icon(Icons.edit, color: Colors.black),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExpenseEdit(
                        expenseId: expense.id,
                      ),
                    ),
                  );

                  onRefresh();
                },
              ),
            ),
          ],
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

enum ExpenseSort {
  dateNewest,
  dateOldest,
  amountHighest,
  amountLowest,
}
