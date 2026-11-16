; SlipDPI installer (Inno Setup 6)
;
; Build:  package.ps1 in the repo root (calls ISCC with the right defines).
; Manual: ISCC /DAppVer=1.0.0 /DKaynak=<package folder> /DCikti=<output folder> SlipDPI.iss
;
; The package installs straight into C:\Program Files\SlipDPI (the scripts assume this path, so the
; folder page is disabled). After the files are copied, install.ps1 -Kurulumdan runs; on uninstall,
; uninstall.ps1 -Sessiz runs first.

#ifndef AppVer
  #define AppVer "0.0.0"
#endif
#ifndef Kaynak
  #define Kaynak ".."
#endif
#ifndef Cikti
  #define Cikti "..\dist"
#endif

[Setup]
; The old name (dpi-lite) used a different AppId: 6F2B7C1E-3A5D-4E8B-9C41-7D2A5B8E1F36
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
OutputBaseFilename=SlipDPI-setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
InfoBeforeFile=info.txt
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
; The user's own lists: kept when installing over an existing copy
Source: "{#Kaynak}\lists\sites.txt";  DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#Kaynak}\lists\exclude.txt";    DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#Kaynak}\licenses\*";         DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#Kaynak}\*.ps1";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\*.cmd";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\SlipDPI.ico";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\README.md";          DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\README.en.md";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\THIRD-PARTY.md";   DestDir: "{app}";          Flags: ignoreversion
Source: "{#Kaynak}\LICENSE";            DestDir: "{app}";          Flags: ignoreversion

; The wizard's "Additional tasks" page asks for the two shortcuts separately.
; A silent install uses the defaults; to change them: /TASKS="baslatmenusu,masaustu"
[Tasks]
Name: "baslatmenusu"; Description: "Başlat menüsüne kısayol ekle"; GroupDescription: "Kısayollar:"
Name: "masaustu";     Description: "Masaüstüne kısayol ekle";      GroupDescription: "Kısayollar:"; Flags: unchecked

[Icons]
; Control window: status, stop/start, add/remove site, re-test, repair and uninstall all live here.
; No Start menu folder, a single shortcut: the guide and uninstall are inside the window.
Name: "{autoprograms}\SlipDPI";      Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: baslatmenusu
Name: "{autodesktop}\SlipDPI";       Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: masaustu

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; Description: "SlipDPI kontrol penceresini aç"; Flags: postinstall nowait skipifsilent runasoriginaluser runminimized

; When installing over an existing copy, delete the previous shortcuts; only the ones chosen now are recreated.
[InstallDelete]
Type: filesandordirs; Name: "{group}"
Type: files;          Name: "{autoprograms}\SlipDPI.lnk"
Type: files;          Name: "{autodesktop}\SlipDPI.lnk"

[UninstallRun]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"" -Sessiz"; Flags: waituntilterminated; RunOnceId: "slipdpi-uninstall"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Copy a file unless the target already exists.
procedure Tasi(kaynak, hedef: String);
begin
  if FileExists(kaynak) and not FileExists(hedef) then CopyFile(kaynak, hedef, True);
end;

// The program used to be installed under the name "dpi-lite". If that install exists, carry the lists
// and the chosen strategy over to the new folder (old Turkish file names -> new ones), then remove the
// old install silently with its own uninstaller (service, driver, DNS rule, browser policy and
// shortcuts go with it).
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
  ForceDirectories(yeni + '\local');
  Tasi(eski + '\otomatik.txt',        yeni + '\auto.txt');
  Tasi(eski + '\lists\siteler.txt',   yeni + '\lists\sites.txt');
  Tasi(eski + '\lists\haric.txt',     yeni + '\lists\exclude.txt');
  Tasi(eski + '\yerel\strateji.json', yeni + '\local\strategy.json');
  Exec(kaldirici, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, rc);
  for i := 1 to 60 do
  begin
    if not FileExists(kaldirici) then break;
    Sleep(500);
  end;
end;

// Before files are copied, stop the running service and driver: otherwise winws.exe and
// WinDivert64.sys are locked and cannot be overwritten.
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

// After the files are copied, run the real setup (strategy test, service, DNS, verification).
procedure CurStepChanged(CurStep: TSetupStep);
var
  rc: Integer;
  ps, betik: String;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Hat test ediliyor ve servis kuruluyor (2-3 dakika sürebilir). Açılan pencereyi kapatmayın...';
    ps := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
    betik := ExpandConstant('{app}\install.ps1');
    if not Exec(ps, '-NoProfile -ExecutionPolicy Bypass -File "' + betik + '" -Kurulumdan', ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, rc) then
      MsgBox('Kurulum betiği başlatılamadı: ' + betik, mbError, MB_OK)
    else if rc <> 0 then
      MsgBox('Kurulum adımları tam tamamlanamadı (kod ' + IntToStr(rc) + ').' + #13#10 + #13#10 +
             'Ayrıntı: ' + ExpandConstant('{app}\local\install.log') + #13#10 +
             'SlipDPI penceresindeki "Onar" düğmesiyle tekrar denenebilir.', mbError, MB_OK);
  end;
end;
