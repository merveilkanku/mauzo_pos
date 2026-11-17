import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core.dart';
import '../state.dart';

// Remplace les rares caractères que la police standard du PDF ne sait pas dessiner.
String _safe(String s) => s.replaceAll('’', "'").replaceAll('≈', '~').replaceAll('→', '->').replaceAll('…', '...');

Future<Uint8List> pdfOf(String text, int paperMm) async {
  final doc = pw.Document();
  final fmt = paperMm == 58 ? PdfPageFormat.roll57 : (paperMm == 80 ? PdfPageFormat.roll80 : PdfPageFormat.a4);
  final size = paperMm == 58 ? 6.5 : (paperMm == 80 ? 8.0 : 10.0);
  doc.addPage(pw.Page(
    pageFormat: fmt,
    build: (ctx) => pw.Text(_safe(text), style: pw.TextStyle(font: pw.Font.courier(), fontSize: size)),
  ));
  return doc.save();
}

/// Imprime un texte. [direct] envoie sans aperçu à l'imprimante choisie dans les réglages.
/// Retourne un message d'erreur, ou null si tout s'est bien passé.
Future<String?> printText(String text, String name, {int? paperMm, bool direct = false}) async {
  try {
    final bytes = await pdfOf(text, paperMm ?? app.paperMm);
    if (direct && app.printerName.isNotEmpty) {
      for (final p in await Printing.listPrinters()) {
        if (p.name == app.printerName) {
          await Printing.directPrintPdf(printer: p, onLayout: (_) async => bytes, name: name);
          return null;
        }
      }
    }
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
    return null;
  } catch (e) {
    return 'Impression impossible : $e';
  }
}

Future<String?> printSale(Sale s, {bool a4 = false, bool direct = false}) =>
    printText(a4 ? invoiceText(s) : receipt(s), 'Ticket ${s.no}', paperMm: a4 ? 210 : null, direct: direct);

Future<String?> printTest() => printText(
    '${app.shop}\nTEST D\'IMPRESSION\nPapier : ${app.paperMm == 210 ? 'A4' : '${app.paperMm} mm'}\n--------------------------------\n'
    '12345678901234567890123456789012\nAccents : e é è à ç ô\nTotal : 12,50 \$ = ${cdf(12.5 * app.rate)}\n--------------------------------\nSi tout est lisible, l\'imprimante est prête.',
    'Test impression');

Future<List<String>> printerNames() async {
  try {
    return (await Printing.listPrinters()).map((p) => p.name).toList();
  } catch (_) {
    return [];
  }
}
