function Zellen_Check_func (handles)

    logMsg(handles, 'Spannung und Strommessung gestartet'); %Funktionsaufruf um etwas in das logMsg zu schreiben

%% Spannungsmessung
    Empfangene_Spg = Spannungsmessung_func(handles);

    set(handles.Text_Spg_Z1,'String',Empfangene_Spg(1));

    set(handles.Text_Spg_Z2,'String',Empfangene_Spg(2));

    set(handles.Text_Spg_Z3,'String',Empfangene_Spg(3));

%% Strommessung
    Empfangene_Str = Strommessung_func(handles);

    set(handles.Text_Str_Z1,'String',Empfangene_Str(1));

    set(handles.Text_Str_Z2,'String',Empfangene_Str(2));

    set(handles.Text_Str_Z3,'String',Empfangene_Str(3));

%%
    logMsg(handles, 'Spannung und Strommessung beendet'); %Funktionsaufruf um etwas in das logMsg zu schreiben
    logMsg(handles, ''); % leere Zeile einfügen

end