import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;


class PdfService {
  static Future<void> exportPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Center(
          child: pw.Text('Expense Report'),
        ),
      ),
    );

    final Uint8List bytes = await pdf.save();

    await FileSaver.instance.saveFile(
      name: 'expense_report',
      bytes: bytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}