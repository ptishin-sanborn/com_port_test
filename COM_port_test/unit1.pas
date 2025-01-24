unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  CPort, CPortCtl, StrUtils;

const
  SIZE_BUF = 1028;

type
  TCyclicBuffer = record
    Buffer: array[0..SIZE_BUF - 1] of Byte;
    Head: Word;
    Tail: Word;
    Count: Word;
  end;

  { TfrmMain }

  TfrmMain = class(TForm)
    btnOpenClose: TButton;
    btnClear: TButton;
    chbShow: TCheckBox;
    Combo1: TComComboBox;
    Combo2: TComComboBox;
    Combo3: TComComboBox;
    Combo4: TComComboBox;
    Combo5: TComComboBox;
    Combo6: TComComboBox;
    ComPort: TComPort;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    leditError: TLabeledEdit;
    leditTotal: TLabeledEdit;
    Memo1: TMemo;
    Panel1: TPanel;
    Panel2: TPanel;
    procedure btnClearClick(Sender: TObject);
    procedure btnOpenCloseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ComPortRxChar(Sender: TObject; Count: Integer);
  private
    function CalculateNMEAChecksum(nmeaSentence: string): string;
    function CyclicBuffer_Add(var CB: TCyclicBuffer; const Data: array of Byte; Length: Word): Boolean;
    function CyclicBuffer_ReadLine(var CB: TCyclicBuffer; var Line: string; MaxLength: Word): Word;
    procedure ApplySettings;
public

  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

{ TfrmMain }

var
  indxRX : integer;
  nmeaSentence : string ='';
  total, errors : integer;
  busy : boolean;
  SharedCyclicBuffer: TCyclicBuffer;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Memo1.Clear;
  Memo1.Lines.Add('FormCreate: Ready');
  ComPort.OnRxChar := @ComPortRxChar;
  ComPort.BaudRate := br115200;  // Set the correct baud rate
  indxRX := 0;
  total := 0;
  errors  := 0;
  busy := false;
  // Initialize cyclic buffer with 0
  FillChar(SharedCyclicBuffer, SizeOf(SharedCyclicBuffer), 0);
end;

procedure TfrmMain.btnOpenCloseClick(Sender: TObject);
begin
  if ComPort.Connected then
  begin
    Memo1.Lines.Add('Closing COM port: ' + ComPort.Port);
    ComPort.Close;
    Memo1.Lines.Add('COM port closed ');
    btnOpenClose.Caption := 'Open';
  end
  else
  begin
    // Initialize cyclic buffer with 0
    FillChar(SharedCyclicBuffer, SizeOf(SharedCyclicBuffer), 0);
    try
      ApplySettings;
      Memo1.Lines.Add('Opening COM port: ' + ComPort.Port);
      ComPort.Open;
      Memo1.Lines.Add('COM port opened successfully ' + DateTimeToStr(Now));
      btnOpenClose.Caption := 'Close';
    except
      on E: Exception do
      begin
        Memo1.Lines.Add('Failed to open COM port: ' + E.Message);
      end;
    end;
  end;
end;

procedure TfrmMain.btnClearClick(Sender: TObject);
begin
  Memo1.Lines.Clear;
  total := 0;
  errors := 0;
  leditTotal.Text := IntToStr(total);
  leditError.Text := IntToStr(errors);
end;

procedure TfrmMain.ComPortRxChar(Sender: TObject; Count: Integer);
var
  TempBuffer: array of Byte;
  BytesRead: Integer;
  Ok : string = 'Ok';
  sentenceChecksum : string;
  calculatedChecksum : string;
  nmeaSentence: string;
  Number: Integer;
begin
  if busy then Memo1.Lines.Add('nmeaSentence buffer overrun');
  busy := true;

  SetLength(TempBuffer, Count);
  BytesRead := ComPort.Read(TempBuffer[0], Count);

  if BytesRead > 0 then
  begin
    if not CyclicBuffer_Add(SharedCyclicBuffer, TempBuffer, BytesRead) then
      Memo1.Lines.Add(DateTimeToStr(Now) +' Cyclic buffer overflow');
  end;

  while True do
  begin
    Number := CyclicBuffer_ReadLine(SharedCyclicBuffer, nmeaSentence, SIZE_BUF);

    if Number <= 0 then
       Break;

    if chbShow.Checked then
    begin
      Memo1.Lines.Add(nmeaSentence);
      Continue;
    end;

    case nmeaSentence[1] of
    // NMEA sentense
      '$': begin
              calculatedChecksum := CalculateNMEAChecksum(nmeaSentence);
              sentenceChecksum := Copy(nmeaSentence, Pos('*', nmeaSentence) + 1, 2);
              if calculatedChecksum <> sentenceChecksum then
              begin
                   Ok := 'Error';
                   Memo1.Lines.Add(DateTimeToStr(Now) + '  == Error');
                   Memo1.Lines.Add(nmeaSentence + 'Checksum ' +
                                   sentenceChecksum + '->' + calculatedChecksum);
                   errors += 1;
              end;
              total += 1;
              leditTotal.Text := IntToStr(total);
              leditError.Text := IntToStr(errors);
           end;
    // Laser altimeter sentence
      'D': begin
              if length(nmeaSentence) <> 12 then
              begin
                Memo1.Lines.Add(DateTimeToStr(Now) + '  == Altimeter error');
                Memo1.Lines.Add(nmeaSentence);
                errors += 1;
              end;
              total += 1;
              leditTotal.Text := IntToStr(total);
              leditError.Text := IntToStr(errors);

           end;
    // Not recognized sentence
    else
      begin
        Memo1.Lines.Add(DateTimeToStr(Now) + '  ==  Not recognized message');
        Memo1.Lines.Add(nmeaSentence);
      end;
    // ------------------------
    end;
  end;
  busy := false;
end;

function TfrmMain.CalculateNMEAChecksum(nmeaSentence: string): string;
var
  nmeaCore: string;
  i: Integer;
  checksum: Byte;
begin
  // Remove the starting '$' and ending '*' and checksum part
  nmeaCore := Copy(nmeaSentence, 2, Pos('*', nmeaSentence) - 2);

  // Initialize checksum
  checksum := 0;

  // Perform XOR on each character in the message
  for i := 1 to Length(nmeaCore) do
  begin
    checksum := checksum xor Byte(nmeaCore[i]);
  end;

  // Format the checksum to a two-character hexadecimal string
  Result := IntToHex(checksum, 2);
end;

function TfrmMain.CyclicBuffer_Add(var CB: TCyclicBuffer; const Data: array of Byte; Length: Word): Boolean;
var
  FirstCopyLength: Word;
begin
  if CB.Count + Length > SIZE_BUF then
  begin
    Result := False; // Not enough space
    Exit;
  end;

  FirstCopyLength := SIZE_BUF - CB.Head;
  if Length < FirstCopyLength then
    FirstCopyLength := Length;

  Move(Data[0], CB.Buffer[CB.Head], FirstCopyLength);
  if Length > FirstCopyLength then
    Move(Data[FirstCopyLength], CB.Buffer[0], Length - FirstCopyLength);

  CB.Head := (CB.Head + Length) mod SIZE_BUF;
  CB.Count := CB.Count + Length;

  Result := True;
end;

function TfrmMain.CyclicBuffer_ReadLine(var CB: TCyclicBuffer; var Line: string; MaxLength: Word): Word;
var
  BytesRead, CurrentPos: Word;
  TempData: array[0..SIZE_BUF - 1] of Byte;
begin
  if CB.Count = 0 then
  begin
    Result := 0; // Buffer is empty
    Exit;
  end;

  BytesRead := 0;
  CurrentPos := CB.Tail;

  while (BytesRead < MaxLength) and (BytesRead < CB.Count) do
  begin
    TempData[BytesRead] := CB.Buffer[CurrentPos];
    if CB.Buffer[CurrentPos] = Ord(#10) then
    begin
      Inc(BytesRead);
      CB.Tail := (CB.Tail + BytesRead) mod SIZE_BUF;
      CB.Count := CB.Count - BytesRead;
      TempData[BytesRead] := 0;  // Null-terminate the string
      SetString(Line, PChar(@TempData[0]), BytesRead);
      Result := BytesRead;
      Exit;
    end;
    CurrentPos := (CurrentPos + 1) mod SIZE_BUF;
    Inc(BytesRead);
  end;

  Result := 0; // No newline found within MaxLength
end;

procedure TfrmMain.ApplySettings;
begin
  ComPort.BeginUpdate;
  Combo1.ApplySettings;
  Combo2.ApplySettings;
  Combo3.ApplySettings;
  Combo4.ApplySettings;
  Combo5.ApplySettings;
  Combo6.ApplySettings;
  ComPort.EndUpdate;
end;

end.

