import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// Klasör rolüne göre simge (web kenar menüsüyle aynı: lucide Inbox, Send, FileText, Trash2, ShieldAlert, Archive,
/// AlarmClock, LayoutTemplate, Folder).
IconData klasorSimgesi(String? rol) => switch (rol) {
  'inbox' => Simge.gelen,
  'snoozed' => Simge.alarm,
  'drafts' => Simge.belge,
  'sent' => Simge.gonder,
  'archive' => Simge.arsiv,
  'templates' => Simge.pano,
  'junk' => Simge.gereksiz,
  'trash' => Simge.sil,
  _ => Simge.klasor,
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
  'starred' => Simge.yildizDolu,
  'important' => Simge.uyari,
  'unread' => Simge.posta,
  'followup' => Simge.hatirlatma,
  'attachments' => Simge.ek,
  'unified' => Simge.katmanlar,
  _ => Simge.tumPosta,
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
  if (t.startsWith('image/')) return Simge.gorsel;
  if (t == 'application/pdf' || a.endsWith('.pdf')) return Simge.pdf;
  if (t.startsWith('audio/')) return Simge.ses;
  if (t.startsWith('video/')) return Simge.film;
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(a)) return Simge.arsivDosya;
  if (RegExp(r'\.(xls|xlsx|ods|csv)$').hasMatch(a)) return Simge.tablo;
  if (RegExp(r'\.(doc|docx|odt|rtf|txt)$').hasMatch(a)) return Simge.makale;
  if (RegExp(r'\.(ppt|pptx|odp)$').hasMatch(a)) return Simge.sunum;
  if (t.contains('calendar') || a.endsWith('.ics')) return Simge.etkinlik;
  return Simge.dosya;
}
