; Inno Setup — Spark AI runtime graphical installer (Windows).
; Invoked by build_windows_installer.sh with /DVERSION /DSTAGE /DOUT /DARCH

#ifndef VERSION
  #define VERSION "0.6.0"
#endif
#ifndef STAGE
  #define STAGE "."
#endif
#ifndef OUT
  #define OUT "."
#endif
#ifndef ARCH
  #define ARCH "x86_64"
#endif

#define AppName "Spark AI Runtime"
#define AppPublisher "Spark Language"
#define AppURL "https://sparklang.dev"
#define KitName "spark-runtime-windows-" + ARCH + "-" + VERSION

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#VERSION}
AppVerName={#AppName} {#VERSION} ({#ARCH})
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}/downloads.html
DefaultDirName={autopf}\Spark
DefaultGroupName=Spark
DisableProgramGroupPage=no
AllowNoIcons=yes
OutputDir={#OUT}
OutputBaseFilename=spark-runtime-windows-{#ARCH}-{#VERSION}-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=120
DisableWelcomePage=no
PrivilegesRequired=admin
LicenseFile=
InfoBeforeFile=
InfoAfterFile=
#if ARCH == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
SetupLogging=yes
UninstallDisplayIcon={app}\README.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut to Spark README"; \
  GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "addpath"; Description: "Add Spark &bin folder to the system PATH (after first-run build)"; \
  GroupDescription: "Environment:"; Flags: checkedonce

[Files]
Source: "{#STAGE}\{#KitName}\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Spark AI Runtime"; Filename: "{app}\README.txt"; Comment: "Spark {#VERSION} ({#ARCH})"
Name: "{group}\Runtime AI guide"; Filename: "{app}\runtime-ai-guide.txt"
Name: "{group}\First-run build (Setup.bat)"; Filename: "{app}\Setup.bat"; \
  Comment: "Compile bootstrap + sparkasm (Git Bash required)"
Name: "{group}\Spark website"; Filename: "{#AppURL}"; Comment: "Documentation and downloads"
Name: "{commondesktop}\Spark README"; Filename: "{app}\README.txt"; Tasks: desktopicon

[Run]
Filename: "{app}\Setup.bat"; Description: "Compile bootstrap + sparkasm (first run)"; \
  Flags: postinstall skipifsilent nowait

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
  ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; \
  Tasks: addpath; Check: NeedsAddPath(ExpandConstant('{app}\bin'))

[Code]
function NeedsAddPath(Param: string): Boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Uppercase(Param) + ';', ';' + Uppercase(OrigPath) + ';') = 0;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpWelcome then
  begin
    WizardForm.WelcomeLabel2.Caption :=
      'Spark is an AI-first language runtime: ask, classify, extract, pipeline, ' +
      'review, model analyze, and voice — one reviewable .spark file per workflow.' + #13#10 + #13#10 +
      'This wizard installs the Spark bootstrap kit for Windows ({#ARCH}). ' +
      'Git Bash (or WSL) compiles bootstrap + sparkasm on first run.' + #13#10 + #13#10 +
      'Dry-run offline with fixtures; live ask uses any OpenAI-compatible API.' + #13#10 +
      'Optional: add bin to PATH after the post-install build step.';
  end;
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption :=
      'Spark AI runtime is installed under {app}.' + #13#10 + #13#10 +
      'Run Setup.bat from the Start menu (or allow the post-install step) to ' +
      'compile bootstrap and sparkasm.' + #13#10 + #13#10 +
      'Then: bin\spark-bootstrap --dry-run examples\hello.spark' + #13#10 +
      'Docs: https://sparklang.dev/docs/programming-guide.html';
  end;
end;

[Messages]
WelcomeLabel1=Welcome to the Spark AI Runtime Setup Wizard
WelcomeLabel2=This will install Spark on your computer.
FinishedLabel=Spark AI runtime is installed.%n%nRun Setup.bat from the Start menu (or allow the post-install step) to compile bootstrap and sparkasm, then dry-run examples\hello.spark offline.%n%nDocs: https://sparklang.dev/docs/programming-guide.html
ClickFinish=Launch first-run build now

[UninstallDelete]
Type: filesandordirs; Name: "{app}\bin"
