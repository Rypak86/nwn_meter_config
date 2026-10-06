unit DogFriend_Build;

var
  NewFile, BaseAlch, BaseEffect, NewEffect, NewAlch, NewQuest: IInterface;
  Effects, EffectEntry, EFID, VMAD, Scripts, ScriptEntry, Group: IInterface;
  Info: TStringList;
  i: Integer;
  WhistleID: Cardinal;

function EnsureGroup(aFile: IInterface; aSig: string): IInterface;
begin
  Result := GroupBySignature(aFile, aSig);
  if not Assigned(Result) then
    Result := Add(aFile, aSig, True);
end;

function AttachScript(aRecord: IInterface; aScriptName: string): IInterface;
begin
  VMAD := ElementByPath(aRecord, 'VMAD');
  if not Assigned(VMAD) then
    VMAD := Add(aRecord, 'VMAD', True);

  Scripts := ElementByPath(VMAD, 'Scripts');
  if not Assigned(Scripts) then
    Scripts := Add(VMAD, 'Scripts', True);

  ScriptEntry := ElementAssign(Scripts, HighInteger, nil, False);
  SetElementEditValues(ScriptEntry, 'ScriptName', aScriptName);
  Result := ScriptEntry;
end;

function Initialize: Integer;
begin
  Result := 0;
  AddMessage('DogFriend: build started');

  BaseAlch := RecordByFormID(FileByIndex(0), $00023736, True);
  if not Assigned(BaseAlch) then begin
    AddMessage('DogFriend: Stimpak not found');
    Result := 1;
    Exit;
  end;

  Effects := ElementByPath(BaseAlch, 'Effects');
  if (not Assigned(Effects)) or (ElementCount(Effects) < 1) then begin
    AddMessage('DogFriend: Stimpak has no Effects');
    Result := 1;
    Exit;
  end;

  EffectEntry := ElementByIndex(Effects, 0);
  EFID := ElementByPath(EffectEntry, 'EFID');
  BaseEffect := LinksTo(EFID);
  if not Assigned(BaseEffect) then begin
    AddMessage('DogFriend: could not resolve base MGEF');
    Result := 1;
    Exit;
  end;

  NewFile := AddNewFileName('DogFriend.esp');
  if not Assigned(NewFile) then begin
    AddMessage('DogFriend: could not create plugin');
    Result := 1;
    Exit;
  end;
  AddMasterIfMissing(NewFile, 'Fallout4.esm');

  NewEffect := wbCopyElementToFile(BaseEffect, NewFile, True, True);
  SetElementEditValues(NewEffect, 'EDID', 'DF_SummonDogsEffect');
  if ElementExists(NewEffect, 'FULL') then
    SetElementEditValues(NewEffect, 'FULL', 'Call Dogs');
  if ElementExists(NewEffect, 'VMAD') then
    RemoveElement(NewEffect, 'VMAD');
  AttachScript(NewEffect, 'DogFriendSummonEffect');

  NewAlch := wbCopyElementToFile(BaseAlch, NewFile, True, True);
  SetElementEditValues(NewAlch, 'EDID', 'DF_DogWhistle');
  SetElementEditValues(NewAlch, 'FULL', 'Dog Whistle');
  if ElementExists(NewAlch, 'VMAD') then
    RemoveElement(NewAlch, 'VMAD');

  Effects := ElementByPath(NewAlch, 'Effects');
  for i := ElementCount(Effects) - 1 downto 1 do
    Remove(ElementByIndex(Effects, i));
  EffectEntry := ElementByIndex(Effects, 0);
  EFID := ElementByPath(EffectEntry, 'EFID');
  SetNativeValue(EFID, FormID(NewEffect));

  Group := EnsureGroup(NewFile, 'QUST');
  NewQuest := Add(Group, 'QUST', True);
  SetToDefault(NewQuest);
  SetElementEditValues(NewQuest, 'EDID', 'DF_StartupQuest');
  if Assigned(ElementByPath(NewQuest, 'DNAM - General\Flags')) then
    SetElementEditValues(NewQuest, 'DNAM - General\Flags', 'Start Game Enabled');
  AttachScript(NewQuest, 'DogFriendStartup');

  WhistleID := FormID(NewAlch) and $00FFFFFF;
  Info := TStringList.Create;
  try
    Info.Add('WHISTLE_FORMID=' + IntToHex(WhistleID, 6));
    Info.SaveToFile('C:\Fallout4_Modding\Projects\DogFriend\DogFriend.buildinfo');
  finally
    Info.Free;
  end;

  AddMessage('DogFriend: records created');
end;

function Finalize: Integer;
begin
  Result := 0;
  AddMessage('DogFriend: build finished');
end;

end.
