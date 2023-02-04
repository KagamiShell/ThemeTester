program kstt;

uses
  Forms, ActiveX,
  main in 'main.pas' {MainForm};

{$R *.res}

begin
  OleInitialize(nil);
  Application.Initialize;
  Application.Title := 'KagamiShell Theme Tester';
  Application.CreateForm(TMainForm,MainForm);
  Application.Run;
end.
