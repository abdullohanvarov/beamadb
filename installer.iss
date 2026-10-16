; BeamADB Inno Setup Script
; Generates self-contained Windows Installer (.exe) for BeamADB

#define MyAppName "BeamADB"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Abdulloh Anvarov"
#define MyAppURL "https://github.com/abdullohanvarov/beamadb"
#define MyAppExeName "beamadb.exe"

[Setup]
AppId={{F5382834-8A87-4BF9-9749-B5B33A5F899D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=LICENSE
OutputDir=dist
OutputBaseFilename=BeamADB-{#MyAppVersion}-Setup
SetupIconFile=static\icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\static\icon.ico
ChangesEnvironment=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "addtopath"; Description: "Add BeamADB to PATH (allows typing 'beamadb' in any terminal)"; GroupDescription: "System Integration:"; Flags: unchecked

[Files]
; Standalone executable
Source: "dist\beamadb.exe"; DestDir: "{app}"; Flags: ignoreversion
; Static web assets
Source: "static\*"; DestDir: "{app}\static"; Flags: ignoreversion recursesubdirs createallsubdirs
; Bundled scrcpy & adb binaries for Windows
Source: "bin\scrcpy\windows\*"; DestDir: "{app}\bin\scrcpy\windows"; Flags: ignoreversion recursesubdirs createallsubdirs
; Batch scripts and documentation
Source: "beamadb.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "launch.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu Shortcuts
Name: "{group}\{#MyAppName} (Web GUI)"; Filename: "{app}\{#MyAppExeName}"; Parameters: "ui"; IconFilename: "{app}\static\icon.ico"; Comment: "Fast, accessible Android Wireless Debugging Web GUI"
Name: "{group}\{#MyAppName} Terminal CLI"; Filename: "cmd.exe"; Parameters: "/k """"{app}\{#MyAppExeName}"""" help"; IconFilename: "{app}\static\icon.ico"; Comment: "Open BeamADB CLI in Command Prompt"
Name: "{group}\{#MyAppName} QR Pairing Mode"; Filename: "cmd.exe"; Parameters: "/k """"{app}\{#MyAppExeName}"""" pair"; IconFilename: "{app}\static\icon.ico"; Comment: "Pair device with QR code directly in terminal"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
; Desktop Shortcut
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "ui"; IconFilename: "{app}\static\icon.ico"; Tasks: desktopicon; Comment: "BeamADB Android Wireless Debugging"

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "ui"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
; Add to User PATH if selected
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Tasks: addtopath; Check: NeedsAddPath(ExpandConstant('{app}'))

[Code]
function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + UpperCase(Param) + ';', ';' + UpperCase(OrigPath) + ';') = 0;
end;

procedure RemovePath(PathToRemove: string);
var
  OrigPath: string;
  P: Integer;
begin
  if RegQueryStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath) then
  begin
    P := Pos(';' + UpperCase(PathToRemove) + ';', ';' + UpperCase(OrigPath) + ';');
    if P > 0 then
    begin
      P := Pos(UpperCase(PathToRemove), UpperCase(OrigPath));
      if P > 0 then
      begin
        Delete(OrigPath, P, Length(PathToRemove));
        StringChangeEx(OrigPath, ';;', ';', True);
        if (Length(OrigPath) > 0) and (OrigPath[1] = ';') then
          Delete(OrigPath, 1, 1);
        if (Length(OrigPath) > 0) and (OrigPath[Length(OrigPath)] = ';') then
          Delete(OrigPath, Length(OrigPath), 1);
        RegWriteStringValue(HKEY_CURRENT_USER, 'Environment', 'Path', OrigPath);
      end;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemovePath(ExpandConstant('{app}'));
  end;
end;
