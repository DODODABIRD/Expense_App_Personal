import 'package:expenseapp/main.dart';
import 'package:expenseapp/services/pdf_export_service.dart';
import 'package:expenseapp/services/pdf_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // Raw rows exactly as DatabaseHelp.getData() returns them.
  final expenses = <Map<String, dynamic>>[
    {
      'id': 3,
      'mongoId': 'm3',
      'ownerId': 'u1',
      'name': 'Nasi Goreng Spesial',
      'amount': 25000,
      'date': '2026-01-05',
      'category': 'makanan',
      'type': 'expected',
      'synced': 1,
    },
    {
      'id': 2,
      'mongoId': 'm2',
      'ownerId': 'u1',
      'name': 'Buku Tulis dan Alat Sekolah Lengkap Untuk Semester Baru',
      'amount': 150000,
      'date': '2026-01-03',
      'category': 'school supply',
      'type': 'unexpected',
      'synced': 1,
    },
    {
      'id': 1,
      'mongoId': 'm1',
      'ownerId': 'u1',
      'name': 'Taksi Bandara',
      'amount': 950,
      'date': '2026-01-01',
      'category': 'transportasi',
      'type': 'others',
      'synced': 1,
    },
  ];

  // Rows after normalization on import, in export order (date descending).
  const expectedRows = [
    {
      'name': 'Nasi Goreng Spesial',
      'amount': 25000,
      'date': '2026-01-05',
      'category': 'makanan',
      'type': 'expected',
    },
    {
      'name': 'Buku Tulis dan Alat Sekolah Lengkap Untuk Semester Baru',
      'amount': 150000,
      'date': '2026-01-03',
      'category': 'school supply',
      'type': 'unexpected',
    },
    {
      'name': 'Taksi Bandara',
      'amount': 950,
      'date': '2026-01-01',
      'category': 'transportasi',
      'type': 'others',
    },
  ];

  setUp(() {
    appCurrency.value = 'IDR';
    appExchangeRate.value = 1;
  });

  test('restores rows exactly from the embedded backup payload', () async {
    final bytes = await PdfExportService.buildExpenseReportBytes(expenses);

    final result = await PdfImportService.parse(bytes);

    expect(result.fromBackupData, isTrue);
    expect(result.currency, 'IDR');
    expect(result.expenses, expectedRows);
  });

  test('recovers rows from the printed table of older reports', () async {
    final bytes = await PdfExportService.buildExpenseReportBytes(expenses);

    final result = await PdfImportService.parse(
      bytes,
      ignoreBackupPayload: true,
    );

    expect(result.fromBackupData, isFalse);
    expect(result.currency, 'IDR');
    expect(result.expenses, expectedRows);
  });

  test('keeps names intact through the printed table', () async {
    final bytes = await PdfExportService.buildExpenseReportBytes(expenses);

    final result = await PdfImportService.parse(
      bytes,
      ignoreBackupPayload: true,
    );

    // The long second name wraps inside its cell and must be rejoined with
    // single spaces exactly as exported.
    expect(result.expenses[1]['name'],
        'Buku Tulis dan Alat Sekolah Lengkap Untuk Semester Baru');
  });

  test('converts legacy non-IDR amounts back to IDR', () async {
    appCurrency.value = 'USD';
    appExchangeRate.value = 0.0001;
    final usdExpenses = [
      {
        'name': 'Nasi Goreng Spesial',
        'amount': 25000,
        'date': '2026-01-05',
        'category': 'makanan',
        'type': 'expected',
      },
      {
        'name': 'Kursus Bahasa',
        'amount': 150000,
        'date': '2026-01-03',
        'category': 'hiburan',
        'type': 'unexpected',
      },
      {
        'name': 'Pulsa',
        'amount': 35000,
        'date': '2026-01-01',
        'category': 'elektronik',
        'type': 'others',
      },
    ];
    final bytes = await PdfExportService.buildExpenseReportBytes(usdExpenses);

    final result = await PdfImportService.parse(
      bytes,
      ignoreBackupPayload: true,
      exchangeRateFor: (currency) async => 0.0001,
    );

    expect(result.currency, 'USD');
    expect(result.expenses, [
      {
        'name': 'Nasi Goreng Spesial',
        'amount': 25000,
        'date': '2026-01-05',
        'category': 'makanan',
        'type': 'expected',
      },
      {
        'name': 'Kursus Bahasa',
        'amount': 150000,
        'date': '2026-01-03',
        'category': 'hiburan',
        'type': 'unexpected',
      },
      {
        'name': 'Pulsa',
        'amount': 35000,
        'date': '2026-01-01',
        'category': 'elektronik',
        'type': 'others',
      },
    ]);
  });

  test('rejects PDFs that are not expense reports', () async {
    final document = pw.Document();
    document.addPage(
      pw.Page(build: (context) => pw.Text('Hello world, not a report')),
    );
    final bytes = await document.save();

    await expectLater(
      PdfImportService.parse(bytes, ignoreBackupPayload: true),
      throwsA(isA<FormatException>()),
    );
  });
}
