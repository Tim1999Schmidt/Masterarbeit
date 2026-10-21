function Empfangene_Spg = Spannungsmessung_func (handles)

    device = getappdata(0, 'device'); %wird für writeline benötigt

    Empfangene_Spg = [0,0,0,0];

    Zeilenanzahl_Spg = 4; % die 4. Zeile ist "Warten auf Befehl!", wird nur im Command Window ausgegeben

    % Sendet den Befehl über COM an SZ
    writeline(device, 'Befehl_Spg_Messung');

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_Spg);

    Empfangene_Spg = sscanf(Empfangene_Zeilen(3), "Spannungswerte;%f;%f;%f;%f;");

end