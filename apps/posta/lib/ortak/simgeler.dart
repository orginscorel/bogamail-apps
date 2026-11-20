import 'package:flutter/material.dart';

/// Klasör rolüne göre simge.
IconData klasorSimgesi(String? rol) => switch (rol) {
  'inbox' => Icons.inbox_rounded,
  'snoozed' => Icons.schedule_rounded,
  'drafts' => Icons.edit_note_rounded,
  'sent' => Icons.send_rounded,
  'archive' => Icons.archive_rounded,
  'templates' => Icons.description_outlined,
  'junk' => Icons.report_gmailerrorred_rounded,
  'trash' => Icons.delete_outline_rounded,
  _ => Icons.folder_outlined,
};

/// Etiket renkleri (sunucudaki renk adları).
const etiketRenkleri = <String, Color>{
  'blue': Color(0xFF3B82F6),
  'green': Color(0xFF10B981),
  'purple': Color(0xFF8B5CF6),
  'orange': Color(0xFFF97316),
  'red': Color(0xFFEF4444),
  'yellow': Color(0xFFF59E0B),
  'teal': Color(0xFF14B8A6),
  'gray': Color(0xFF94A3B8),
};

const etiketRenkAdlari = <String, String>{
  'blue': 'Mavi',
  'green': 'Yeşil',
  'purple': 'Mor',
  'orange': 'Turuncu',
  'red': 'Kırmızı',
  'yellow': 'Sarı',
  'teal': 'Camgöbeği',
  'gray': 'Gri',
};

Color etiketRengi(String ad) => etiketRenkleri[ad] ?? etiketRenkleri['gray']!;

/// Ek türüne göre simge.
IconData ekSimgesi(String tur, String ad) {
  final t = tur.toLowerCase();
  final a = ad.toLowerCase();
  if (t.startsWith('image/')) return Icons.image_outlined;
  if (t == 'application/pdf' || a.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (t.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (t.startsWith('video/')) return Icons.movie_outlined;
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(a)) return Icons.folder_zip_outlined;
  if (RegExp(r'\.(xls|xlsx|ods|csv)$').hasMatch(a)) return Icons.table_chart_outlined;
  if (RegExp(r'\.(doc|docx|odt|rtf|txt)$').hasMatch(a)) return Icons.article_outlined;
  if (RegExp(r'\.(ppt|pptx|odp)$').hasMatch(a)) return Icons.slideshow_outlined;
  if (t.contains('calendar') || a.endsWith('.ics')) return Icons.event_outlined;
  return Icons.insert_drive_file_outlined;
}
