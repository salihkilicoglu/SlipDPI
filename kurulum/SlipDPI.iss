; SlipDPI kurulum programi (Inno Setup 6)
;
; Derleme: depo kokundeki paketle.ps1 (ISCC'yi dogru tanimlarla cagirir).
; Elle:    ISCC /DAppVer=1.0.0 /DKaynak=<paket klasoru> /DCikti=<cikti klasoru> SlipDPI.iss
;
; Paket dogrudan C:\Program Files\SlipDPI altina kurulur (betikler bu yolu varsayar, o yuzden
; klasor secimi kapali). Dosyalar kopyalandiktan sonra kur.ps1 -Kurulumdan calistirilir; kaldirirken
; once kaldir.ps1 -Sessiz calisir.

#ifndef AppVer
  #define AppVer "0.0.0"
#endif
#ifndef Kaynak
  #define Kaynak ".."
#endif
#ifndef Cikti
  #define Cikti "..\cikti"
#endif

[Setup]
; Eski ad (dpi-lite) baska bir AppId kullaniyordu: 6F2B7C1E-3A5D-4E8B-9C41-7D2A5B8E1F36
AppId={{A3D94E57-1C6B-4F20-8E7A-52B9C0D4F18B}
AppName=SlipDPI
AppVersion={#AppVer}
AppVerName=SlipDPI {#AppVer}
AppPublisher=SlipDPI
AppPublisherURL=https://github.com/salihkilicoglu/SlipDPI
DefaultDirName={autopf}\SlipDPI
DisableDirPage=yes
UsePreviousAppDir=no
DefaultGroupName=SlipDPI
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Cikti}
OutputBaseFilename=SlipDPI-kurulum-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
InfoBeforeFile=bilgi.txt
SetupIconFile={#Kaynak}\SlipDPI.ico
UninstallDisplayIcon={app}\SlipDPI.ico
UninstallDisplayName=SlipDPI
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#AppVer}
VersionInfoDescription=SlipDPI kurulum

[Languages]
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[Files]
Source: "{#Kaynak}\bin\*";              DestDir: "{app}\bin";      Flags: ignoreversion
Source: "{#Kaynak}\filters\*";          DestDir: "{app}\filters";  Flags: ignoreversion
Source: "{#Kaynak}\lists\discord.txt";  DestDir: "{app}\lists";    Flags: ignoreversion
; Kullanicinin kendi listeleri: ustune kurulumda korunur
Source: "{#Kaynak}\lists\siteler.txt";  DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#Kaynak}\lists\haric.txt";    DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#Kaynak}\licenses\*";         DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#Kaynak}\*.ps1";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\*.cmd";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\SlipDPI.ico";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\README.md";          DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\README.en.md";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\UCUNCU-TARAF.md";   DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\LICENSE";            DestDir: "{app}";          Flags: ignoreversion

; Kurulum sihirbazi "Ek gorevler" sayfasinda iki kisayolu ayri ayri sorar.
; Sessiz kurulumda varsayilanlar gecerlidir; degistirmek icin: /TASKS="baslatmenusu,masaustu"
[Tasks]
Name: "baslatmenusu"; Description: "Başlat menüsüne kısayol ekle"; GroupDescription: "Kısayollar:"
Name: "masaustu";     Description: "Masaüstüne kısayol ekle";      GroupDescription: "Kısayollar:"; Flags: unchecked

[Icons]
; Kontrol penceresi: durum, durdur/baslat, site ekle/cikar, yeniden test, onar ve kaldir hepsi buradan.
; Baslat menusunde klasor yok, tek kisayol: kilavuz ve kaldirma pencerenin icinde.
Name: "{autoprograms}\SlipDPI";      Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: baslatmenusu
Name: "{autodesktop}\SlipDPI";       Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: masaustu

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; Description: "SlipDPI kontrol penceresini aç"; Flags: postinstall nowait skipifsilent runasoriginaluser runminimized

; Ustune kurulumda onceki kisayollari sil; ardindan yalnizca bu kurulumda secilenler yeniden olusturulur.
[InstallDelete]
Type: filesandordirs; Name: "{group}"
Type: files;          Name: "{autoprograms}\SlipDPI.lnk"
Type: files;          Name: "{autodesktop}\SlipDPI.lnk"

[UninstallRun]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\kaldir.ps1"" -Sessiz"; Flags: waituntilterminated; RunOnceId: "slipdpi-kaldir"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Dosyalar kopyalanmadan once calisan servisi ve surucuyu durdur: aksi halde winws.exe ve
// WinDivert64.sys kilitli oldugu icin ustune yazilamaz.
procedure Tasi(kaynak, hedef: String);
begin
  if FileExists(kaynak) and not FileExists(hedef) then CopyFile(kaynak, hedef, True);
end;

// Program eskiden "dpi-lite" adiyla kuruluyordu. O kurulum varsa listeleri ve secili ayari yeni
// klasore tasi, sonra eski kurulumu kendi kaldiricisiyla sessizce kaldir (servis, surucu, DNS kurali,
// tarayici ayari ve kisayollar onunla gider).
procedure EskiAdiKaldir;
var
  eski, yeni, kaldirici: String;
  rc, i: Integer;
begin
  eski := ExpandConstant('{autopf}\dpi-lite');
  yeni := ExpandConstant('{app}');
  kaldirici := eski + '\unins000.exe';
  if not FileExists(kaldirici) then exit;
  ForceDirectories(yeni + '\lists');
  ForceDirectories(yeni + '\yerel');
  Tasi(eski + '\otomatik.txt',        yeni + '\otomatik.txt');
  Tasi(eski + '\lists\siteler.txt',   yeni + '\lists\siteler.txt');
  Tasi(eski + '\lists\haric.txt',     yeni + '\lists\haric.txt');
  Tasi(eski + '\yerel\strateji.json', yeni + '\yerel\strateji.json');
  Exec(kaldirici, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, rc);
  for i := 1 to 60 do
  begin
    if not FileExists(kaldirici) then break;
    Sleep(500);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  rc: Integer;
begin
  EskiAdiKaldir;
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop SlipDPI', '', SW_HIDE, ewWaitUntilTerminated, rc);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im winws.exe', '', SW_HIDE, ewWaitUntilTerminated, rc);
  Sleep(800);
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop windivert', '', SW_HIDE, ewWaitUntilTerminated, rc);
  Exec(ExpandConstant('{sys}\sc.exe'), 'delete windivert', '', SW_HIDE, ewWaitUntilTerminated, rc);
  Sleep(500);
  Result := '';
end;

// Dosyalar kopyalandiktan sonra asil kurulumu (strateji testi, servis, DNS, dogrulama) calistir.
procedure CurStepChanged(CurStep: TSetupStep);
var
  rc: Integer;
  ps, betik: String;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Hat test ediliyor ve servis kuruluyor (2-3 dakika sürebilir). Açılan pencereyi kapatmayın...';
    ps := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
    betik := ExpandConstant('{app}\kur.ps1');
    if not Exec(ps, '-NoProfile -ExecutionPolicy Bypass -File "' + betik + '" -Kurulumdan', ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, rc) then
      MsgBox('Kurulum betiği başlatılamadı: ' + betik, mbError, MB_OK)
    else if rc <> 0 then
      MsgBox('Kurulum adımları tam tamamlanamadı (kod ' + IntToStr(rc) + ').' + #13#10 + #13#10 +
             'Ayrıntı: ' + ExpandConstant('{app}\yerel\kur.log') + #13#10 +
             'SlipDPI penceresindeki "Onar" düğmesiyle tekrar denenebilir.', mbError, MB_OK);
  end;
end;
