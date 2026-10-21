
% diese Funktion speichert die Eingabewerte und sendet sie an den Zellhalter
function Einstellungen_uebernehmen_func (handles)

%% Werte auslesen
    Zielordner = string(get(handles.Zielordner, 'String'));
    Filename = string(get(handles.Filename, 'String'));
    Kommentar = string(get(handles.Kommentar, 'String'));
    Zellenname_Z1 = string(get(handles.Zellenname_Z1, 'String'));
    Zellenname_Z2 = string(get(handles.Zellenname_Z2, 'String'));
    Zellenname_Z3 = string(get(handles.Zellenname_Z3, 'String'));

    Textfelder_Werte = [Zielordner, Filename, Kommentar, Zellenname_Z1, Zellenname_Z2, Zellenname_Z3];
    setappdata(0, 'EIS_Textfelder_Werte', Textfelder_Werte);

    EIS_Chip = get(handles.EIS_Chip, 'Value') - 1;             % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    EIS_Chip_str = get(handles.EIS_Chip, 'String');
    EIS_Chip_akt_str = string(EIS_Chip_str(EIS_Chip + 1));

    Start_Frequenz = get(handles.start_frq, 'Value') - 1;      % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    Start_Frequenz_str = get(handles.start_frq, 'String');
    Start_Frequenz_akt_str = string(Start_Frequenz_str(Start_Frequenz + 1));

    Stopp_Frequenz = get(handles.stopp_frq, 'Value') - 1;      % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    Stopp_Frequenz_str = get(handles.stopp_frq, 'String');
    Stopp_Frequenz_akt_str = string(Stopp_Frequenz_str(Stopp_Frequenz + 1));

    Amplitude = get(handles.Amplitude, 'Value') - 1;           % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    Amplitude_str = get(handles.Amplitude, 'String');
    Amplitude_akt_str = string(Amplitude_str(Amplitude + 1));

    SinRec = get(handles.SinRec, 'Value') - 1;                 % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    SinRec_str = get(handles.SinRec, 'String');
    SinRec_akt_str = string(SinRec_str(SinRec + 1));

    Mittelung = get(handles.Mittelung, 'Value');           % hier wird der Werte direkt gesendet, da er direkt in c verwendet wird
    Mittelung_str = get(handles.Mittelung, 'String');
    Mittelung_akt_str = string(Mittelung_str(Mittelung));

    Verschaltung = get(handles.Verschaltung, 'Value') - 1;           % hier - 1 da matlab die Nummerierung bei 1 startet und C-Code bei 0
    Verschaltung_str = get(handles.Verschaltung, 'String');
    Verschaltung_akt_str = string(Verschaltung_str(Verschaltung + 1));

    Popupmenu_Werte = [EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung, Verschaltung];
    setappdata(0, 'EIS_Popupmenu_Werte', Popupmenu_Werte);
    Popupmenu_Werte_akt_str = [EIS_Chip_akt_str, Start_Frequenz_akt_str, Stopp_Frequenz_akt_str, Amplitude_akt_str, SinRec_akt_str, Mittelung_akt_str, Verschaltung_akt_str];
    setappdata(0, 'EIS_Popupmenu_Werte_akt_str', Popupmenu_Werte_akt_str);
    %logMsg(handles, Popupmenu_Werte_akt_str);

    akt_Kontaktwerte_fuer_Textfile = [0, 0, 0];
    setappdata(0, 'akt_Kontaktwerte_fuer_Textfile', akt_Kontaktwerte_fuer_Textfile);

    %% Button Enable/Disable
    set(handles.Messung_Starten, 'Enable', 'on');

    logMsg(handles, 'Einstellungen übernommen'); %Funktionsaufruf um etwas in das logMsg zu schreiben
    logMsg(handles, ''); % leere Zeile einfügen
end