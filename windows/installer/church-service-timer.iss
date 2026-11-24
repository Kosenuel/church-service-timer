; Inno Setup script for the Church Service Timer installer.
; Built by scripts/Package-Windows.ps1, which passes the version and the
; folder that `flutter build windows --release` produced:
;   iscc /DAppVersion=0.39.0 /DVersionInfo=0.35.0.0 /DSourceDir=C:\...\Release church-service-timer.iss
; AppVersion is text and may carry a pre-release part (0.36.0-beta.1);
; VersionInfo must be four numbers (0.36.0.0), the same without that part.
;
; Installs for the current user by default, so no administrator password
; is needed in a church office; the person can choose "all users" instead.
; The installer is not code-signed (there is no certificate), so Windows
; SmartScreen warns before it runs.
;
; The look (dark wizard, artwork, a slideshow while files copy) needs Inno
; Setup 6.6 or newer: PNG wizard images came in 6.5, WizardStyle "dark" in
; 6.6, and CurInstallProgressChanged only works from 6.5.4. On an older
; compiler the Cinematic switch below stays off and the script builds the
; plain modern wizard it always did. Nothing the installer installs, and no
; setting that decides where or how, depends on it. See README.md here.

#define AppName "Church Service Timer"
#define AppExe "church_service_timer.exe"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef VersionInfo
  #define VersionInfo "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
; VER is Inno Setup's own version, as hex: 0x06060000 is 6.6.0.
#if VER >= 0x06060000
  #define Cinematic
#endif

[Setup]
; Identifies the app to Windows across versions. Never change it: a new
; value would install a second copy instead of updating.
AppId={{6C1E0A4B-93D7-4F5E-8B2A-5D0F7C3E91A4}
AppName={#AppName}
AppVersion={#AppVersion}
VersionInfoVersion={#VersionInfo}
AppVerName={#AppName} {#AppVersion}
AppPublisher=I-Proton
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Church-Service-Timer-{#AppVersion}-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
#ifdef Cinematic
; A dark wizard whatever the Windows setting, to match the artwork. Each
; image directive lists one file per scaling step (100% to 250%); setup uses
; the smallest that is big enough. The artwork is drawn by
; tool/make_installer_art.py.
WizardStyle=modern dark
WizardImageFile=art\welcome-220.png,art\welcome-331.png,art\welcome-441.png,art\welcome-551.png
WizardSmallImageFile=art\header-64.png,art\header-80.png,art\header-96.png,art\header-128.png,art\header-160.png
#else
WizardStyle=modern
#endif
; Ask a running copy to close, so its files can be replaced.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

#ifdef Cinematic
[Messages]
; Words for the first and last pages, in plain language.
SetupWindowTitle=Set up %1
WelcomeLabel1=Welcome to [name]
WelcomeLabel2=Time the whole service from one screen. Set the program, press start, and everyone sees how long is left: the speaker on stage, the band, and people on their phones.%n%nSetup will install [name/ver] on this computer.%n%nIf Windows warned about an unknown publisher, that is expected: this installer is not code-signed.
FinishedHeadingLabel=[name] is ready
FinishedLabel=Start it from the Start menu or your desktop. A step-by-step guide is at immanuelokose.github.io/church-service-timer-guide
FinishedLabelNoIcons=[name] is installed. A step-by-step guide is at immanuelokose.github.io/church-service-timer-guide
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

#ifdef Cinematic
; Pictures for the pages, kept inside the installer and unpacked by the code
; below. dontcopy means they are never installed on the computer.
Source: "art\scene-1.png"; Flags: dontcopy
Source: "art\scene-2.png"; Flags: dontcopy
Source: "art\scene-3.png"; Flags: dontcopy
Source: "art\scene-4.png"; Flags: dontcopy
Source: "art\scene-5.png"; Flags: dontcopy
Source: "art\scene-6.png"; Flags: dontcopy
Source: "art\ready-220.png"; Flags: dontcopy
Source: "art\ready-331.png"; Flags: dontcopy
Source: "art\ready-441.png"; Flags: dontcopy
Source: "art\ready-551.png"; Flags: dontcopy
#endif

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Lists the app under "Open with" for program files (.json, .csv) without
; taking those file types away from whatever opens them now.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".json"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".csv"; ValueData: ""

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Saved services, programs and reports live in the user's AppData folder
; and are deliberately left in place when the app is removed.

#ifdef Cinematic
[Code]
{ Everything here is decoration. Each part is wrapped so that if a picture
  cannot be loaded, the wizard simply stays as setup draws it. A silent
  install (/SILENT or /VERYSILENT) does none of it. }

const
  SceneCount = 6;

var
  SceneImages: array [0..5] of TBitmapImage;
  SceneCaption: TNewStaticText;
  SceneShown: Integer;
  SceneReady: Boolean;

{ Scales a size given for a 417 pixel wide page to the real page width. }
function Fit(N, PageWidth: Integer): Integer;
begin
  Result := MulDiv(N, PageWidth, 417);
end;

function SceneText(Index: Integer): String;
begin
  case Index of
    0: Result := 'The countdown, big and clear for the speaker';
    1: Result := 'Running over? The screen can turn red';
    2: Result := 'Or a flip clock between segments';
    3: Result := 'Song words and Bible verses on the big screen';
    4: Result := 'Phones and web browsers follow along';
    5: Result := 'Pick a look that suits your church';
  else
    Result := '';
  end;
end;

procedure ShowScene(Index: Integer);
var
  I: Integer;
begin
  if not SceneReady then
    Exit;
  if (Index < 0) or (Index >= SceneCount) or (Index = SceneShown) then
    Exit;
  try
    for I := 0 to SceneCount - 1 do
      SceneImages[I].Visible := (I = Index);
    SceneCaption.Caption := SceneText(Index);
    SceneShown := Index;
  except
    SceneReady := False;
  end;
end;

{ Puts the six pictures and a caption above the progress bar on the page
  that shows while files are copied. Nothing is moved until every picture
  has loaded. }
procedure BuildSlideshow;
var
  PageWidth, I: Integer;
begin
  PageWidth := WizardForm.ProgressGauge.Width;
  if PageWidth < 200 then
    Exit;
  try
    for I := 0 to SceneCount - 1 do
    begin
      ExtractTemporaryFile('scene-' + IntToStr(I + 1) + '.png');
      SceneImages[I] := TBitmapImage.Create(WizardForm);
      SceneImages[I].Stretch := True;
      SceneImages[I].Left := 0;
      SceneImages[I].Top := 0;
      SceneImages[I].Width := PageWidth;
      SceneImages[I].Height := Fit(140, PageWidth);
      SceneImages[I].PngImage.LoadFromFile(ExpandConstant('{tmp}\scene-' + IntToStr(I + 1) + '.png'));
      SceneImages[I].Visible := (I = 0);
      SceneImages[I].Parent := WizardForm.InstallingPage;
    end;
    SceneCaption := TNewStaticText.Create(WizardForm);
    SceneCaption.AutoSize := False;
    SceneCaption.Left := 0;
    SceneCaption.Top := Fit(146, PageWidth);
    SceneCaption.Width := PageWidth;
    SceneCaption.Height := Fit(18, PageWidth);
    SceneCaption.Caption := SceneText(0);
    SceneCaption.Parent := WizardForm.InstallingPage;
    WizardForm.StatusLabel.Top := Fit(170, PageWidth);
    WizardForm.FilenameLabel.Top := Fit(186, PageWidth);
    WizardForm.ProgressGauge.Top := Fit(208, PageWidth);
    SceneShown := 0;
    SceneReady := True;
  except
    SceneReady := False;
    for I := 0 to SceneCount - 1 do
      if SceneImages[I] <> nil then
        SceneImages[I].Visible := False;
  end;
end;

{ The last page gets its own picture, the finished ring. The file is chosen
  to match the size of the picture area, so it stays sharp. }
procedure BuildCurtainCall;
var
  AreaWidth: Integer;
  Size: String;
begin
  AreaWidth := WizardForm.WizardBitmapImage2.Width;
  if AreaWidth <= 224 then
    Size := '220'
  else if AreaWidth <= 335 then
    Size := '331'
  else if AreaWidth <= 445 then
    Size := '441'
  else
    Size := '551';
  try
    ExtractTemporaryFile('ready-' + Size + '.png');
    WizardForm.WizardBitmapImage2.PngImage.LoadFromFile(ExpandConstant('{tmp}\ready-' + Size + '.png'));
  except
    { keep the Welcome picture on this page }
    Log('The finished-page picture could not be loaded.');
  end;
end;

procedure InitializeWizard;
begin
  if WizardSilent then
    Exit;
  BuildSlideshow;
  BuildCurtainCall;
end;

{ Moves to the next picture as the copy gets a sixth further along. }
procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
var
  Index, I: Integer;
begin
  if not SceneReady then
    Exit;
  if MaxProgress <= 0 then
    Exit;
  try
    Index := 0;
    for I := 1 to SceneCount - 1 do
      if CurProgress / MaxProgress >= I / SceneCount then
        Index := I;
    ShowScene(Index);
  except
    SceneReady := False;
  end;
end;
#endif
