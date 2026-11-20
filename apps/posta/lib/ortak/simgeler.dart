import 'package:flutter/material.dart';

/// Klasör rolüne göre simge (web kenar menüsüyle aynı: lucide Inbox, Send, FileText, Trash2, ShieldAlert, Archive,
/// AlarmClock, LayoutTemplate, Folder).
IconData klasorSimgesi(String? rol) => switch (rol) {
  'inbox' => Icons.inbox_outlined,
  'snoozed' => Icons.alarm_rounded,
  'drafts' => Icons.description_outlined,
  'sent' => Icons.send_outlined,
  'archive' => Icons.archive_outlined,
  'templates' => Icons.space_dashboard_outlined,
  'junk' => Icons.gpp_maybe_outlined,
  'trash' => Icons.delete_outline_rounded,
  _ => Icons.folder_outlined,
};

/// Web'deki renkli sistem klasörleri: Çöp kırmızı (red-500), Gereksiz turuncu (orange-500); diğerleri nötr (null).
Color? klasorRengi(String? rol) => switch (rol) {
  'trash' => const Color(0xFFEF4444),
  'junk' => const Color(0xFFF97316),
  _ => null,
};

/// Yıldız sarısı (web: fill-yellow-400 text-yellow-500).
const yildizRengi = Color(0xFFEAB308);

/// Görünüm simgeleri (web: Star sarı, TriangleAlert, Mail, BellRing; Tüm hesaplar Layers).
IconData gorunumSimgesi(String id) => switch (id) {
  'starred' => Icons.star_rounded,
  'important' => Icons.warning_amber_rounded,
  'unread' => Icons.mail_outline_rounded,
  'followup' => Icons.notifications_active_outlined,
  'attachments' => Icons.attach_file_rounded,
  'unified' => Icons.layers_outlined,
  _ => Icons.all_inbox_outlined,
};

Color? gorunumRengi(String id) => id == 'starred' ? yildizRengi : null;

/// Etiket renkleri (sunucudaki renk adları).
const etiketRenkleri = <String, Color>{
  'blue': Color(0xFF3B82F6),
  'green': Color(0xFF10B981),
  'purple': Color(0xFF8B5CF6),
  'orange': Color(0xFFF97316),
  'red': Color(0xFFEF4444),
  'yellow': Color(0xFFFBBF24),
  'teal': Color(0xFF14B8A6),
  'gray': Color(0xFFA1A1AA),
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
