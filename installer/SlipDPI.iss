; SlipDPI installer (Inno Setup 6)
;
; Build:  package.ps1 in the repo root (calls ISCC with the right defines).
; Manual: ISCC /DAppVer=1.0.0 /DSourceDir=<package folder> /DOutputDir=<output folder> SlipDPI.iss
;
; The package installs straight into C:\Program Files\SlipDPI (the scripts assume this path, so the
; folder page is disabled). After the files are copied, install.ps1 -FromSetup runs; on uninstall,
; uninstall.ps1 -Silent runs first.

#ifndef AppVer
  #define AppVer "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir ".."
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
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
OutputDir={#OutputDir}
OutputBaseFilename=SlipDPI-setup-{#AppVer}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile={#SourceDir}\SlipDPI.ico
UninstallDisplayIcon={app}\SlipDPI.ico
UninstallDisplayName=SlipDPI
CloseApplications=no
RestartApplications=no
VersionInfoVersion={#AppVer}
VersionInfoDescription=SlipDPI Setup

[Languages]
; The setup asks for the language first; the choice is written to lang.txt and used by the scripts and
; the control window. The Windows display language is preselected.
Name: "en"; MessagesFile: "compiler:Default.isl";           InfoBeforeFile: "info.en.txt"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"; InfoBeforeFile: "info.tr.txt"

[CustomMessages]
en.ShortcutsGroup=Shortcuts:
tr.ShortcutsGroup=Kısayollar:
en.TaskStartMenu=Add a Start menu shortcut
tr.TaskStartMenu=Başlat menüsüne kısayol ekle
en.TaskDesktop=Add a desktop shortcut
tr.TaskDesktop=Masaüstüne kısayol ekle
en.OpenPanel=Open the SlipDPI control window
tr.OpenPanel=SlipDPI kontrol penceresini aç
en.StatusInstalling=Testing the line and installing the service (2-3 minutes). Keep the console window open...
tr.StatusInstalling=Hat test ediliyor ve servis kuruluyor (2-3 dakika sürebilir). Açılan pencereyi kapatmayın...
en.ScriptNotStarted=The setup script could not be started: %1
tr.ScriptNotStarted=Kurulum betiği başlatılamadı: %1
en.SetupIncomplete=The setup steps did not complete (code %1).%n%nDetails: %2%nYou can try again with the "Repair" button in the SlipDPI window.
tr.SetupIncomplete=Kurulum adımları tam tamamlanamadı (kod %1).%n%nAyrıntı: %2%nSlipDPI penceresindeki "Onar" düğmesiyle tekrar denenebilir.

[Files]
Source: "{#SourceDir}\bin\*";              DestDir: "{app}\bin";      Flags: ignoreversion
Source: "{#SourceDir}\filters\*";          DestDir: "{app}\filters";  Flags: ignoreversion
Source: "{#SourceDir}\lists\discord.txt";  DestDir: "{app}\lists";    Flags: ignoreversion
; The user's own lists: kept when installing over an existing copy
Source: "{#SourceDir}\lists\sites.txt";  DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#SourceDir}\lists\exclude.txt";    DestDir: "{app}\lists";    Flags: onlyifdoesntexist
Source: "{#SourceDir}\lang\*.psd1";      DestDir: "{app}\lang";     Flags: ignoreversion
Source: "{#SourceDir}\licenses\*";         DestDir: "{app}\licenses"; Flags: ignoreversion
Source: "{#SourceDir}\*.ps1";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\*.cmd";              DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\SlipDPI.ico";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\README.md";          DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\README.en.md";       DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\THIRD-PARTY.md";   DestDir: "{app}";          Flags: ignoreversion
Source: "{#SourceDir}\LICENSE";            DestDir: "{app}";          Flags: ignoreversion

; The wizard's "Additional tasks" page asks for the two shortcuts separately.
; A silent install uses the defaults; to change them: /TASKS="startmenu,desktop"
[Tasks]
Name: "startmenu"; Description: "{cm:TaskStartMenu}"; GroupDescription: "{cm:ShortcutsGroup}"
Name: "desktop";      Description: "{cm:TaskDesktop}";   GroupDescription: "{cm:ShortcutsGroup}"; Flags: unchecked

[Icons]
; Control window: status, stop/start, add/remove site, re-test, repair and uninstall all live here.
; No Start menu folder, a single shortcut: the guide and uninstall are inside the window.
Name: "{autoprograms}\SlipDPI";      Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: startmenu
Name: "{autodesktop}\SlipDPI";       Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\SlipDPI.ico"; Flags: runminimized; Tasks: desktop

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\panel.ps1"""; WorkingDir: "{app}"; Description: "{cm:OpenPanel}"; Flags: postinstall nowait skipifsilent runasoriginaluser runminimized

; When installing over an existing copy, delete the previous shortcuts; only the ones chosen now are recreated.
[InstallDelete]
Type: filesandordirs; Name: "{group}"
Type: files;          Name: "{autoprograms}\SlipDPI.lnk"
Type: files;          Name: "{autodesktop}\SlipDPI.lnk"

[UninstallRun]
Filename: "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"" -Silent"; Flags: waituntilterminated; RunOnceId: "slipdpi-uninstall"

[Registry]
; The language chosen in the control window; removed on uninstall.
Root: HKCU; Subkey: "Software\SlipDPI"; Flags: dontcreatekey uninsdeletekey

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
// Before files are copied, stop the running service and driver: otherwise winws.exe and
// WinDivert64.sys are locked and cannot be overwritten.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  rc: Integer;
begin
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
  ps, script: String;
begin
  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := CustomMessage('StatusInstalling');
    // The language chosen in the wizard becomes the program's language; a choice made earlier in the
    // control window (HKCU) is cleared so the new one takes effect.
    SaveStringToFile(ExpandConstant('{app}\lang.txt'), ActiveLanguage, False);
    RegDeleteValue(HKEY_CURRENT_USER, 'Software\SlipDPI', 'Language');
    ps := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
    script := ExpandConstant('{app}\install.ps1');
    if not Exec(ps, '-NoProfile -ExecutionPolicy Bypass -File "' + script + '" -FromSetup', ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, rc) then
      MsgBox(FmtMessage(CustomMessage('ScriptNotStarted'), [script]), mbError, MB_OK)
    else if rc <> 0 then
      MsgBox(FmtMessage(CustomMessage('SetupIncomplete'), [IntToStr(rc), ExpandConstant('{app}\local\install.log')]), mbError, MB_OK);
  end;
end;
