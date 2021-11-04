program Cubes;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMain in 'FMain.pas' {FormMain},
  Components in 'Components.pas',
  Systems in 'Systems.pas',
  SimpleECS in '..\SimpleECS.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
