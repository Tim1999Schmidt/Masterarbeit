function Messung_Starten_func (handles)
    
    device = getappdata(0, 'device'); %wird für writeline benötigt

    %Button Enable/Disable
    set(handles.Messung_Starten, 'Enable', 'off');
    set(handles.Reset, 'Enable', 'off');
    set(handles.Einstellungen_uebernehmen, 'Enable', 'off');

    Zeilenanzahl_1 = 3;

    EIS_Popupmenu_Werte = getappdata(0, 'EIS_Popupmenu_Werte'); % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung, Verschaltung

    %% Ab hier Spannungsmessung für Textfile

    Verschalten_func (handles, [0, 0, 1, 0, 0, 1, 0, 0, 1]);

    akt_Spg_fuer_Textfile = Spannungsmessung_func(handles);

    setappdata(0, 'akt_Spg_fuer_Textfile', akt_Spg_fuer_Textfile);
    
    if true % hier false setzen für Evaluierungsmessung und true für normalen Betrieb
    %% Ab hier Kontakt_Check für Textfile
    if EIS_Popupmenu_Werte(7) ~= 1 %Wenn es nur eine Einzelmessung ist, wird kein Kontaktcheck ausgeführt
        Kontakt_Check_func(handles);
    end
    %% Ab hier Start Sensorposition setzen
    % für Parallelverschaltungen muss abhängig vom genutzten EIS_Chip die
    % Sensorposition angepasst werden, bei Einzelmessung alles auf aus also 1
    if EIS_Popupmenu_Werte(7) ~= 1 %Prüft ob es keine Einzelmessung ist
        
        if EIS_Popupmenu_Werte(1) == 0 %Prüft ob EIS_Chip_1 verwendet wird
            Sens_Pos_Werte = [1, 0, 0, 1, 1, 1, 1, 1];

        elseif EIS_Popupmenu_Werte(1) == 1 %Prüft ob EIS_Chip_2 verwendet wird
            Sens_Pos_Werte = [1, 1, 1, 0, 0, 1, 1, 1];

        elseif EIS_Popupmenu_Werte(1) == 2 %Prüft ob EIS_Chip_3 verwendet wird
            Sens_Pos_Werte = [1, 1, 1, 1, 1, 0, 0, 1];
        end
    else
        Sens_Pos_Werte = [1, 1, 1, 1, 1, 1, 1, 1]; % Fall für Einzelmessung
    end

    Sensor_Position_setzen_func (handles, Sens_Pos_Werte);

    pause(0.5) % Zeit damit Relais schalten können
    end
    %% Ab hier Start Verschaltung

    % Hier wird vor der EIS_Messung die richtige Verschaltung gewählt

    Auslesewerte = [0, 0, 0, 0, 0, 0, 0, 0, 0];

    if EIS_Popupmenu_Werte(7) == 0 % individuel
        Auslesewerte(1) = get(handles.Z1_direkt, 'Value');
        Auslesewerte(2) = get(handles.Z1_R, 'Value');
        Auslesewerte(3) = get(handles.Z1_GND, 'Value');
        Auslesewerte(4) = get(handles.Z2_direkt, 'Value');
        Auslesewerte(5) = get(handles.Z2_R, 'Value');
        Auslesewerte(6) = get(handles.Z2_GND, 'Value');
        Auslesewerte(7) = get(handles.Z3_direkt, 'Value');
        Auslesewerte(8) = get(handles.Z3_R, 'Value');
        Auslesewerte(9) = get(handles.Z3_GND, 'Value');
    elseif EIS_Popupmenu_Werte(7) == 1 % einzeln
        if EIS_Popupmenu_Werte(1) == 0 % EIS_Chip_1 wird verwendet
        Auslesewerte = [1, 0, 1, 0, 0, 0, 0, 0, 0]; % Kanal1 wird geschaltet
        elseif EIS_Popupmenu_Werte(1) == 1 % EIS_Chip_2 wird verwendet
        Auslesewerte = [0, 0, 0, 1, 0, 1, 0, 0, 0]; % Kanal2 wird geschaltet
        elseif EIS_Popupmenu_Werte(1) == 2 % EIS_Chip_3 wird verwendet
        Auslesewerte = [0, 0, 0, 0, 0, 0, 1, 0, 1]; % Kanal3 wird geschaltet
        end
    elseif EIS_Popupmenu_Werte(7) == 2 % Z1 || Z2
        Auslesewerte = [1, 0, 1, 1, 0, 1, 0, 0, 0];
    elseif EIS_Popupmenu_Werte(7) == 3 % Z1 || Z3
        Auslesewerte = [1, 0, 1, 0, 0, 0, 1, 0, 1];
    elseif EIS_Popupmenu_Werte(7) == 4 % Z2 || Z3
        Auslesewerte = [0, 0, 0, 1, 0, 1, 1, 0, 1];
    elseif EIS_Popupmenu_Werte(7) == 5 % Z1 || Z2 || Z3
        Auslesewerte = [1, 0, 1, 1, 0, 1, 1, 0, 1];
    end

    Antwort_von_Befehl = Verschalten_func (handles, Auslesewerte); % mit Rückgabewert falls Spg_differenz zu hoch ist


    if contains(Antwort_von_Befehl, "Verschaltung wurde ausgefuehrt")
        % >>> Fortsetzen der Funktion
    else
        %Button Enable/Disable
        set(handles.Reset, 'Enable', 'on');
        set(handles.Einstellungen_uebernehmen, 'Enable', 'on');
        % >>> Funktion hier beenden
        return;
    end


    %% Ab hier Start EIS-Messung
    logMsg(handles, 'EIS-Messung wurde gestartet'); %Funktionsaufruf um etwas in das logMsg zu schreiben

    %Stringbildung
    Einstellungen_String = sprintf('%d;', EIS_Popupmenu_Werte);
    Befehlsstring = 'Befehl_EIS;' + string(Einstellungen_String);

    % Sendet den Befehl über COM an SZ
    writeline(device, Befehlsstring); % String: Befehl_EIS;0;0;0;0;0;0
    logMsg(handles, '>>> ' + Befehlsstring); % Kontrollausgabe welcher String gesendet wurde

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1);

    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(1))); % rxBuffer
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(2))); % Befehl_EIS wurde erkannt
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(3))); % EIS_Messung wurde gestartet


    %% Ab hier werden die Messdaten empfangen
    Zeilenanzahl_2 = EIS_Popupmenu_Werte(3)-EIS_Popupmenu_Werte(2) + 5; % Berechnung wie viele Zeilen als Antwort erwartet werden

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2);

    logMsg(handles, 'EIS-Messung wurde beendet');

    Textdatei_erstellen_func (handles,Empfangene_Zeilen);
    
    %Button Enable/Disable
    set(handles.Reset, 'Enable', 'on');
    set(handles.Einstellungen_uebernehmen, 'Enable', 'on');

    %% Am Ende jeder Messung wird die Verschaltung wieder komplett aufgehoben und Sensorpositionen wieder auf Einzelmessung gesetzt

    Verschalten_func (handles, [0, 0, 0, 0, 0, 0, 0, 0, 0]);

    Sens_Pos_Werte = [1, 1, 1, 1, 1, 1, 1, 1];
    Sensor_Position_setzen_func (handles, Sens_Pos_Werte);

end