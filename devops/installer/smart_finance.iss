; Inno Setup script - tạo bộ cài 1 file SmartFinance_Setup_x.y.z.exe
; build.ps1 tự gọi nếu máy có Inno Setup 6 (https://jrsoftware.org/isdl.php)
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildNumber
  #define BuildNumber "1"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\frontend\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\releases"
#endif
#ifndef ExeName
  #define ExeName "SmartFinance.exe"
#endif

[Setup]
AppId={{7E3F2A4C-5B1D-4C8E-9A61-2F0D5C8B1A11}
AppName=Smart Finance
AppVersion={#AppVersion}+{#BuildNumber}
AppPublisher=Smart Finance
DefaultDirName={localappdata}\Programs\SmartFinance
DefaultGroupName=Smart Finance
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=SmartFinance_Setup_{#AppVersion}+{#BuildNumber}
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#ExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Smart Finance"; Filename: "{app}\{#ExeName}"
Name: "{autodesktop}\Smart Finance"; Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchProgram,Smart Finance}"; Flags: nowait postinstall skipifsilent
