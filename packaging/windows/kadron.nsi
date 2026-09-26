; Kadron installer. Built by packaging/windows/package.sh, which passes
; VERSION, ROOT, STAGE, DIST and SIZE_KB.
;
; Per-user install (no administrator prompt) into %LOCALAPPDATA%\Programs\Kadron,
; like most modern desktop apps. The uninstaller removes only the files it
; installed, never the folder's other contents, and leaves user data alone.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!define APP "Kadron"
!define PUBLISHER "Aleks Szotek"
!define URL "https://github.com/al3ksh/Kadron"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Kadron"

Name "${APP}"
Caption "${APP} ${VERSION} Setup"
OutFile "${DIST}\Kadron-${VERSION}-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Kadron"
InstallDirRegKey HKCU "Software\Kadron" "InstallDir"
BrandingText "${APP} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APP} Setup"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${PUBLISHER}. GPL-3.0."

!include "MUI2.nsh"
!include "FileFunc.nsh"
!define MUI_ICON "${ROOT}\assets\kadron.ico"
!define MUI_UNICON "${ROOT}\assets\kadron.ico"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_NODESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\kadron.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Start Kadron"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${ROOT}\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; Files in use cannot be replaced. Kadron's own updater starts this installer
; as it exits, so wait up to 10 s before asking the user to close it (a silent
; install gives up instead of waiting for an answer nobody can see).
!macro EnsureClosed
    StrCpy $1 0
    retry:
    ClearErrors
    IfFileExists "$INSTDIR\kadron.exe" 0 done
    FileOpen $0 "$INSTDIR\kadron.exe" a
    IfErrors 0 closeHandle
    IntOp $1 $1 + 1
    IntCmp $1 20 ask 0 ask
    Sleep 500
    Goto retry
    ask:
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Kadron is running. Close it and choose Retry." /SD IDCANCEL IDRETRY retry
    Abort
    closeHandle:
    FileClose $0
    done:
!macroend

Section "Kadron" SecApp
    SectionIn RO
    !insertmacro EnsureClosed
    ; Let the previous version remove exactly its own files, so no stale DLL
    ; stays behind; _?= keeps it in place and makes ExecWait actually wait.
    IfFileExists "$INSTDIR\uninstall.exe" 0 fresh
        ExecWait '"$INSTDIR\uninstall.exe" /S _?=$INSTDIR'
        Delete "$INSTDIR\uninstall.exe"
    fresh:
    SetOutPath "$INSTDIR"
    File /r "${STAGE}\*.*"
    WriteUninstaller "$INSTDIR\uninstall.exe"

    CreateShortcut "$SMPROGRAMS\Kadron.lnk" "$INSTDIR\kadron.exe"
    WriteRegStr HKCU "Software\Kadron" "InstallDir" "$INSTDIR"

    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "${URL}"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\kadron.exe"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" ${SIZE_KB}
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Open .kadr projects with Kadron" SecAssociate
    WriteRegStr HKCU "Software\Classes\.kadr" "" "Kadron.Project"
    WriteRegStr HKCU "Software\Classes\Kadron.Project" "" "Kadron project"
    WriteRegStr HKCU "Software\Classes\Kadron.Project\DefaultIcon" "" "$INSTDIR\kadron.exe,0"
    WriteRegStr HKCU "Software\Classes\Kadron.Project\shell\open\command" "" '"$INSTDIR\kadron.exe" "%1"'
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section /o "Desktop shortcut" SecDesktop
    CreateShortcut "$DESKTOP\Kadron.lnk" "$INSTDIR\kadron.exe"
SectionEnd

; Kadron's updater passes /relaunch so the new version opens when it is done.
Function .onInstSuccess
    ${GetParameters} $0
    ClearErrors
    ${GetOptions} $0 "/relaunch" $1
    IfErrors +2
    Exec '"$INSTDIR\kadron.exe"'
FunctionEnd

Section "Uninstall"
    !insertmacro EnsureClosed
    !include "${DIST}\uninstall-files.nsh"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"

    Delete "$SMPROGRAMS\Kadron.lnk"
    Delete "$DESKTOP\Kadron.lnk"
    ; Only undo the association if it still points at this install.
    ReadRegStr $0 HKCU "Software\Classes\Kadron.Project\shell\open\command" ""
    StrCmp $0 '"$INSTDIR\kadron.exe" "%1"' 0 +4
        DeleteRegKey HKCU "Software\Classes\Kadron.Project"
        DeleteRegValue HKCU "Software\Classes\.kadr" ""
        DeleteRegKey /ifempty HKCU "Software\Classes\.kadr"
    System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
    DeleteRegKey HKCU "${UNINSTALL_KEY}"
    DeleteRegValue HKCU "Software\Kadron" "InstallDir"
SectionEnd
