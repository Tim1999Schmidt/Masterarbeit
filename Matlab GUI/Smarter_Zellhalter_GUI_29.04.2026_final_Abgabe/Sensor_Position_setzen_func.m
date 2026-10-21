function Sensor_Position_setzen_func (handles, Auslesewerte)

    device = getappdata(0, 'device'); %wird für writeline benötigt

    Zeilenanzahl = 4; % die 4. Zeile ist "Warten auf Befehl!", wird nur im Command Window ausgegeben

    Sensor_Position = sprintf('%d;', Auslesewerte);

    Befehlsstring = 'Befehl_Sens_Pos;' + string(Sensor_Position); % String: Befehl_Sens_Pos;1;1;1;1;1;1;1;1

    % Sendet den Befehl über COM an SZ
    writeline(device, Befehlsstring); %String: Befehl_Sens_Pos;1;1;1;1;1;1;1;1
    logMsg(handles, '>>> ' + Befehlsstring); % Kontrollausgabe welcher String gesendet wurde

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl);

    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(1))); % rxBuffer (Befehl_Sens_Pos;1;1;1;1;1;1;1;1)
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(2))); % Befehl_Sens_Pos wurde erkannt
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(3))); % Befehl_Sens_Pos wurde ausgefuehrt oder Ungueltige Befehlseingabe

    logMsg(handles, ''); % leere Zeile einfügen
    
end