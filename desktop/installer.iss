; CI passes the version: ISCC.exe /DAppVer=1.1.0 installer.iss
#ifndef AppVer
  #define AppVer "1.0.5"
#endif

[Setup]
; Kept from the InstantFaceAI installer so existing installs upgrade in place.
AppId=InstantFaceAI
AppName=RealFaceAI
AppVersion={#AppVer}
DefaultDirName={autopf}\RealFaceAI
DefaultGroupName=RealFaceAI
OutputDir=installer_output
OutputBaseFilename=RealFaceAI-Setup-{#AppVer}
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "installer\VC_redist.x64.exe"; \
    DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "installer\MicrosoftEdgeWebview2Setup.exe"; \
    DestDir: "{tmp}"; Flags: deleteafterinstall

[UninstallDelete]
; Saved login tokens + settings (shared_preferences: %APPDATA%\CompanyName\
; ProductName). Without this, a reinstall finds the old session and signs
; the user straight back in.
Type: filesandordirs; Name: "{userappdata}\RealFaceAI\RealFaceAI"

[Icons]
Name: "{group}\RealFaceAI"; Filename: "{app}\RealFaceAI.exe"
Name: "{commondesktop}\RealFaceAI"; Filename: "{app}\RealFaceAI.exe"

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Visual C++ Runtime..."; \
    Flags: waituntilterminated
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; \
    Parameters: "/silent /install"; \
    StatusMsg: "Installing WebView2 Runtime..."; \
    Flags: waituntilterminated
Filename: "{app}\RealFaceAI.exe"; \
    Description: "Launch RealFaceAI"; Flags: nowait postinstall skipifsilent