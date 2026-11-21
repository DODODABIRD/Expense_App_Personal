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
    final parsedDate = DateTime.tryParse(map['date']?.toString() ?? '');
    return ExpenseModel(
      id: map['id'] as int?,
      name: map['name']?.toString().trim().isNotEmpty == true
          ? map['name'].toString()
          : 'Unknown',
      amount: map['amount'] is int
          ? map['amount'] as int
          : int.tryParse(map['amount']?.toString() ?? '0') ?? 0,
      date: parsedDate ?? DateTime.now(),
      category: map['category']?.toString().trim().isNotEmpty == true
          ? map['category'].toString().trim().toLowerCase()
          : 'general',
      type: map['type']?.toString().trim().isNotEmpty == true
          ? map['type'].toString().trim().toLowerCase()
          : 'others',
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
