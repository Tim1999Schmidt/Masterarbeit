function Reset_func(handles)
            set(handles.Zielordner,'String','Y:\Desktop_Verknüpfungen\Matlab_Test\Zielordner_Text');
            set(handles.Filename,'String','Ordnername eingeben');
            set(handles.Kommentar, 'String','Hier bitte deinen Kommentar eingeben')
            set(handles.Zellenname_Z1,'String','Testzelle_A');
            set(handles.Zellenname_Z2,'String','Testzelle_B');
            set(handles.Zellenname_Z3,'String','Testzelle_C');

            set(handles.start_frq, 'Value', 1);
            set(handles.stopp_frq, 'Value', 1);
            set(handles.Amplitude, 'Value', 2);
            set(handles.SinRec, 'Value', 1);
            set(handles.Mittelung, 'Value', 1);
            set(handles.Verschaltung, 'Value', 1);

            logMsg(handles, 'Reset durchgeführt'); %Funktionsaufruf um etwas in das logMsg zu schreiben
            logMsg(handles, ''); % leere Zeile einfügen
end