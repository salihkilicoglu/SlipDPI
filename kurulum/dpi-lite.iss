; dpi-lite kurulum programi (Inno Setup 6)
;
; Derleme: depo kokundeki paketle.ps1 (ISCC'yi dogru tanimlarla cagirir).
; Elle:    ISCC /DAppVer=1.0.0 /DKaynak=<paket klasoru> /DCikti=<cikti klasoru> dpi-lite.iss
;
; Paket dogrudan C:\Program Files\dpi-lite altina kurulur (betikler bu yolu varsayar, o yuzden
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
AppId={{6F2B7C1E-3A5D-4E8B-9C41-7D2A5B8E1F36}
AppName=dpi-lite
AppVersion={#AppVer}
AppVerName=dpi-lite {#AppVer}
AppPublisher=dpi-lite
AppPublisherURL=https://github.com/salihkilicoglu/dpi-lite
DefaultDirName={autopf}\dpi-lite
DisableDirPage=yes
UsePreviousAppDir=no
DefaultGroupName=dpi-lite
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Cikti}
OutputBaseFilename=dpi-lite-kurulum-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
InfoBeforeFile=bilgi.txt
UninstallDisplayName=dpi-lite
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#AppVer}
VersionInfoDescription=dpi-lite kurulum

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
Source: "{#Kaynak}\README.md";          DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\UCUNCU-TARAF.md";    DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\LICENSE";            DestDir: "{app}";          Flags: ignoreversion

[Icons]
Name: "{group}\Site ekle";            Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\site-ekle.ps1"""; WorkingDir: "{app}"
Name: "{group}\Otomatik liste";       Filename: "{app}\otomatik-liste.cmd"; WorkingDir: "{app}"
Name: "{group}\Durum";                Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\ac-kapat.ps1"" -Durum"; WorkingDir: "{app}"
Name: "{group}\Aç - Kapat";           Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\ac-kapat.ps1"""; WorkingDir: "{app}"
Name: "{group}\Yeniden kur (onar)";   Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\kur.ps1"""; WorkingDir: "{app}"
Name: "{group}\Strateji testi";       Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\strateji-test.ps1"""; WorkingDir: "{app}"
Name: "{group}\Kullanım kılavuzu";    Filename: "{win}\notepad.exe"; Parameters: """{app}\README.md"""
Name: "{group}\dpi-lite'ı kaldır";    Filename: "{uninstallexe}"

[UninstallRun]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\kaldir.ps1"" -Sessiz"; Flags: waituntilterminated; RunOnceId: "dpilite-kaldir"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Dosyalar kopyalanmadan once calisan servisi ve surucuyu durdur: aksi halde winws.exe ve
// WinDivert64.sys kilitli oldugu icin ustune yazilamaz.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  rc: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop dpi-lite', '', SW_HIDE, ewWaitUntilTerminated, rc);
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
             'Başlat menüsündeki "Yeniden kur (onar)" ile tekrar denenebilir.', mbError, MB_OK);
  end;
end;
