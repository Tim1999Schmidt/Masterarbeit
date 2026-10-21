function Empfangene_Str = Strommessung_func (handles)

    device = getappdata(0, 'device'); %wird für writeline benötigt

    Empfangene_Str = [0,0,0,0];

    Zeilenanzahl_Str = 4; % die 4. Zeile ist "Warten auf Befehl!", wird nur im Command Window ausgegeben

    % Sendet den Befehl über COM an SZ
    writeline(device, 'Befehl_Str_Messung');

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_Str);

    Empfangene_Str = sscanf(Empfangene_Zeilen(3), "Stromwerte;%f;%f;%f;%f;");  

end