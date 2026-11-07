; Inno Setup script for PDF Search. Build: iscc windows\pdfsearch.iss  (output: dist\PDFSearch-Setup.exe)
#define AppName "PDF Search"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{6B1B7C0A-4C55-4A52-9D7B-5D1C3E9F7A10}
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={autopf}\PDFSearch
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=PDFSearch-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}

[Files]
Source: "..\linux\*"; DestDir: "{app}\linux"; Flags: recursesubdirs
Source: "..\ingest_folder.py"; DestDir: "{app}"
Source: "setup-wsl.ps1"; DestDir: "{app}\windows"
Source: "start-pdfsearch.ps1"; DestDir: "{app}\windows"
Source: "stop-pdfsearch.ps1"; DestDir: "{app}\windows"
Source: "uninstall-wsl.ps1"; DestDir: "{app}\windows"
Source: "collect-diagnostics.ps1"; DestDir: "{app}\windows"
Source: "..\SETUP-GUIDE.md"; DestDir: "{app}"; Flags: isreadme

[Icons]
Name: "{autodesktop}\PDF Search"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\start-pdfsearch.ps1"""; Comment: "Open PDF Search"
Name: "{autoprograms}\PDF Search\PDF Search"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\start-pdfsearch.ps1"""
Name: "{autoprograms}\PDF Search\Finish setup (re-run after restart)"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\setup-wsl.ps1"" {code:SetupArgs}"
Name: "{autoprograms}\PDF Search\Collect diagnostics"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\collect-diagnostics.ps1"""
Name: "{autoprograms}\PDF Search\Stop PDF Search"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\windows\stop-pdfsearch.ps1"""

[Code]
var
  PdfPage, DataPage: TInputDirWizardPage;
  PerfPage: TWizardPage;
  RamEdit, CpuEdit: TNewEdit;
  ModelCombo: TNewComboBox;

procedure InitializeWizard;
var
  L: TNewStaticText;
begin
  PdfPage := CreateInputDirPage(wpSelectDir, 'Your PDF library', 'Where are your PDF files?',
    'Select the folder that contains your PDFs (sub-folders are included). The files are only read, never changed or moved.', False, '');
  PdfPage.Add('PDF folder:');
  PdfPage.Values[0] := 'C:\';

  DataPage := CreateInputDirPage(PdfPage.ID, 'Search index location', 'Where should the search index be stored?',
    'The index and search engine are stored here and grow with your library (plan for roughly 5-10% of the PDF size, more for scanned documents). Choose a drive with plenty of free space.', False, '');
  DataPage.Add('Index folder:');
  DataPage.Values[0] := 'C:\PDFSearchData';

  PerfPage := CreateCustomPage(DataPage.ID, 'Performance', 'How much of this PC may PDF Search use? More memory and CPU cores make indexing faster. Leave at least 4 GB of RAM free for Windows.');

  L := TNewStaticText.Create(PerfPage);
  L.Parent := PerfPage.Surface; L.Caption := 'Memory (GB):'; L.Top := 0; L.Left := 0;
  RamEdit := TNewEdit.Create(PerfPage);
  RamEdit.Parent := PerfPage.Surface; RamEdit.Top := 20; RamEdit.Left := 0; RamEdit.Width := 80; RamEdit.Text := '12';

  L := TNewStaticText.Create(PerfPage);
  L.Parent := PerfPage.Surface; L.Caption := 'CPU cores:'; L.Top := 56; L.Left := 0;
  CpuEdit := TNewEdit.Create(PerfPage);
  CpuEdit.Parent := PerfPage.Surface; CpuEdit.Top := 76; CpuEdit.Left := 0; CpuEdit.Width := 80; CpuEdit.Text := '4';

  L := TNewStaticText.Create(PerfPage);
  L.Parent := PerfPage.Surface; L.Caption := 'Search model:'; L.Top := 112; L.Left := 0;
  ModelCombo := TNewComboBox.Create(PerfPage);
  ModelCombo.Parent := PerfPage.Surface; ModelCombo.Top := 132; ModelCombo.Left := 0; ModelCombo.Width := 400;
  ModelCombo.Style := csDropDownList;
  ModelCombo.Items.Add('Fast, English (bge-small, needs ~12 GB RAM)');
  ModelCombo.Items.Add('Best quality, multilingual (bge-m3, needs 32 GB RAM or more)');
  ModelCombo.ItemIndex := 0;

  if ExpandConstant('{param:pdfdir|}') <> '' then PdfPage.Values[0] := ExpandConstant('{param:pdfdir|}');
  if ExpandConstant('{param:datadir|}') <> '' then DataPage.Values[0] := ExpandConstant('{param:datadir|}');
end;

function ModelName: String;
begin
  if ModelCombo.ItemIndex = 1 then Result := 'BAAI/bge-m3' else Result := 'BAAI/bge-small-en-v1.5';
end;

{ Quote a path for a Windows command line: a trailing backslash would otherwise escape the closing quote. }
function Q(Path: String): String;
begin
  Path := Trim(Path);
  if (Length(Path) > 0) and (Path[Length(Path)] = '\') then Path := Path + '\';
  Result := '"' + Path + '"';
end;

function SetupArgs(Param: String): String;
begin
  Result := '-InstallDir ' + Q(DataPage.Values[0]) + ' -PdfDir ' + Q(PdfPage.Values[0]) + ' -RamGB ' + RamEdit.Text +
            ' -Cpus ' + CpuEdit.Text + ' -Model ' + ModelName;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = PerfPage.ID then
  begin
    if (StrToIntDef(RamEdit.Text, 0) < 6) or (StrToIntDef(CpuEdit.Text, 0) < 2) then
    begin
      MsgBox('Please enter at least 6 GB of memory and 2 CPU cores.', mbError, MB_OK);
      Result := False;
    end;
  end;
  if (CurPageID = PdfPage.ID) and (not DirExists(PdfPage.Values[0])) then
  begin
    MsgBox('That PDF folder does not exist.', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Code: Integer;
  Params: String;
begin
  if (CurStep = ssPostInstall) and ((not WizardSilent) or (ExpandConstant('{param:runsetup|0}') = '1')) then
  begin
    Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}') + '\windows\setup-wsl.ps1" ' + SetupArgs('');
    if not Exec('powershell.exe', Params, '', SW_SHOW, ewWaitUntilTerminated, Code) then
      MsgBox('Could not start the setup script.', mbError, MB_OK)
    else if Code = 10 then
      MsgBox('Windows needs to restart to finish enabling its Linux feature.' + #13#10 +
             'After restarting, open the Start menu > PDF Search > "Finish setup".', mbInformation, MB_OK)
    else if Code <> 0 then
      MsgBox('Setup did not complete (code ' + IntToStr(Code) + ').' + #13#10 +
             'Details: ' + DataPage.Values[0] + '\setup.log' + #13#10 +
             'You can retry from Start menu > PDF Search > "Finish setup".', mbError, MB_OK);
  end;
end;
