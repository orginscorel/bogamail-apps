// Kurum imza şablonu yardımcıları (web: lib/webmail-productivity.ts renderSignature, SIGNATURE_LAYOUTS).

const _sosyal = {'linkedin', 'x', 'instagram', 'facebook', 'youtube'};
const _takma = {
  'name': 'ad',
  'adsoyad': 'ad',
  'title': 'unvan',
  'phone': 'telefon',
  'mobile': 'cep',
  'department': 'departman',
  'company': 'sirket',
  'şirket': 'sirket',
  'email': 'eposta',
};

String _kacir(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// İmza şablonunu örnek değerlerle doldurur (değerler kaçırılır, boş data-optional blokları kaldırılır).
String imzaDoldur(String sablon, Map<String, String> d) {
  String? bul(String k) {
    final a = k.toLowerCase();
    final v = d[_takma[a] ?? a];
    if (v != null) return v;
    if (_sosyal.contains(a)) return '';
    return null;
  }

  var c = sablon;
  final istege = RegExp(r'<(span|div|p|tr|td|a|li)\b[^>]*\bdata-optional="([a-zA-Z_]+)"[^>]*>[\s\S]*?</\1>', caseSensitive: false);
  for (var i = 0; i < 3; i++) {
    final s = c.replaceAllMapped(istege, (m) {
      final v = bul(m.group(2)!);
      return v != null && v.trim().isEmpty ? '' : m.group(0)!;
    });
    if (s == c) break;
    c = s;
  }
  return c.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-ZçğıöşüÇĞİÖŞÜ_]+)\s*\}\}'), (m) {
    final v = bul(m.group(1)!);
    return v == null ? m.group(0)! : _kacir(v);
  });
}

const imzaOrnekDegerleri = {
  'ad': 'Ayşe Yılmaz',
  'unvan': 'Satış Müdürü',
  'departman': 'Satış',
  'telefon': '0212 000 00 00',
  'cep': '',
  'sirket': 'Örnek A.Ş.',
  'eposta': 'ayse@ornek.com.tr',
  'web': 'https://ornek.com.tr',
};

/// Hazır imza düzenleri (logo olmadan, #1d4ed8 rengiyle; web ile aynı HTML).
const imzaDuzenleri = <(String, String)>[
  (
    'Klasik',
    '<table cellpadding="0" cellspacing="0" style="font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.45;color:#333333">'
        '<tr><td style="vertical-align:top;border-left:3px solid #1d4ed8;padding-left:12px">'
        '<div style="font-size:15px;font-weight:bold;color:#1d4ed8">{{ad}}</div>'
        '<div data-optional="unvan">{{unvan}}</div><div data-optional="departman" style="color:#666666">{{departman}}</div>'
        '<div style="margin-top:6px"><b>{{sirket}}</b></div>'
        '<div data-optional="telefon">Tel: {{telefon}}</div><div data-optional="cep">Cep: {{cep}}</div>'
        '<div><a href="mailto:{{eposta}}" style="color:#1d4ed8;text-decoration:none">{{eposta}}</a></div>'
        '<div data-optional="web"><a href="{{web}}" style="color:#1d4ed8;text-decoration:none">{{web}}</a></div>'
        '</td></tr></table>',
  ),
  (
    'Modern',
    '<div style="font-family:\'Segoe UI\',Arial,sans-serif;font-size:13px;line-height:1.5;color:#2b2b2b">'
        '<div style="font-size:16px;font-weight:600">{{ad}}</div>'
        '<div data-optional="unvan" style="color:#1d4ed8;font-weight:600">{{unvan}}</div>'
        '<div style="height:2px;width:48px;background:#1d4ed8;margin:8px 0"></div>'
        '<div>{{sirket}}<span data-optional="departman"> · {{departman}}</span></div>'
        '<div><span data-optional="telefon">{{telefon}} · </span><a href="mailto:{{eposta}}" style="color:#2b2b2b">{{eposta}}</a></div>'
        '<div data-optional="web"><a href="{{web}}" style="color:#1d4ed8">{{web}}</a></div>'
        '<div style="margin-top:6px"><a data-optional="linkedin" href="{{linkedin}}" style="color:#1d4ed8;margin-right:8px">LinkedIn</a>'
        '<a data-optional="x" href="{{x}}" style="color:#1d4ed8;margin-right:8px">X</a>'
        '<a data-optional="instagram" href="{{instagram}}" style="color:#1d4ed8;margin-right:8px">Instagram</a></div>'
        '</div>',
  ),
  (
    'Kompakt',
    '<div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.4;color:#444444">'
        '<b style="color:#1d4ed8">{{ad}}</b><span data-optional="unvan"> | {{unvan}}</span> | {{sirket}}<br>'
        '<span data-optional="telefon">T: {{telefon}} | </span><a href="mailto:{{eposta}}" style="color:#444444">{{eposta}}</a>'
        '<span data-optional="web"> | <a href="{{web}}" style="color:#1d4ed8">{{web}}</a></span>'
        '</div>',
  ),
  (
    'Kurumsal',
    '<table cellpadding="0" cellspacing="0" style="font-family:Georgia,\'Times New Roman\',serif;font-size:13px;line-height:1.5;color:#222222">'
        '<tr><td style="border-top:1px solid #1d4ed8;padding-top:8px">'
        '<div style="font-size:15px"><b>{{ad}}</b></div><div data-optional="unvan"><i>{{unvan}}</i></div>'
        '<div data-optional="departman">{{departman}}</div><div>{{sirket}}</div>'
        '<div style="margin-top:4px;color:#555555"><span data-optional="telefon">T {{telefon}}&nbsp;&nbsp;</span>'
        '<span data-optional="cep">M {{cep}}&nbsp;&nbsp;</span>E {{eposta}}</div>'
        '<div data-optional="web"><a href="{{web}}" style="color:#1d4ed8">{{web}}</a></div>'
        '<div style="margin-top:8px;font-size:10px;color:#888888">Bu e-posta ve ekleri yalnızca alıcısına yöneliktir. '
        'Yanlışlıkla size ulaştıysa lütfen gönderene bildirip siliniz.</div>'
        '</td></tr></table>',
  ),
];
