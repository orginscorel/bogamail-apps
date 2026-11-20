; BogaMail Windows kurulumu (Inno Setup 6). CI tanımları: Uygulama (posta|yonetim), Dosya, Surum, Kaynak, Cikti, Simge.
#if Uygulama == "posta"
  #define Ad "BogaMail"
  #define Exe "posta.exe"
  #define Kimlik "{{8E0F6E3B-6B2A-4C69-9C1D-2B7A0E5F4A11}"
#else
  #define Ad "BogaMail Yönetim"
  #define Exe "yonetim.exe"
  #define Kimlik "{{3C5D1B7E-2F4A-4E8B-A6D9-71C0B2E9F3D4}"
#endif

[Setup]
AppId={#Kimlik}
AppName={#Ad}
AppVersion={#Surum}
AppVerName={#Ad} {#Surum}
AppPublisher=Bogahost
AppPublisherURL=https://posta.bogahost.com
DefaultDirName={autopf}\Bogahost\{#Ad}
DefaultGroupName={#Ad}
DisableProgramGroupPage=yes
OutputDir={#Cikti}
OutputBaseFilename={#Dosya}
SetupIconFile={#Simge}
UninstallDisplayIcon={app}\{#Exe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "masaustu"; Description: "Masaüstüne kısayol oluştur"; GroupDescription: "Kısayollar:"

[Files]
Source: "{#Kaynak}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#Ad}"; Filename: "{app}\{#Exe}"
Name: "{autodesktop}\{#Ad}"; Filename: "{app}\{#Exe}"; Tasks: masaustu

[Run]
Filename: "{app}\{#Exe}"; Description: "{#Ad} uygulamasını başlat"; Flags: nowait postinstall skipifsilent
; Uygulama içinden sessiz güncellemede kurulum bitince yeniden aç.
Filename: "{app}\{#Exe}"; Flags: nowait; Check: WizardSilent
