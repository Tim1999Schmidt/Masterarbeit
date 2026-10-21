function letzte_Zeile = Verschalten_func (handles, Auslesewerte)

    device = getappdata(0, 'device'); %wird für writeline benötigt

    Zeilenanzahl = 4; % die 4. Zeile ist "Warten auf Befehl!", wird nur im Command Window ausgegeben

    Verschaltung = sprintf('%d;', Auslesewerte);

    Befehlsstring = 'Befehl_Verschalten;' + string(Verschaltung); % String: Befehl_Verschalten;0,0,0,0,0,0,0,0,0

    % Sendet den Befehl über COM an SZ
    writeline(device, Befehlsstring); %String: Befehl_Verschalten;0,0,0,0,0,0,0,0,0
    logMsg(handles, '>>> ' + Befehlsstring); % Kontrollausgabe welcher String gesendet wurde

    % Empfängt Zeilen über COM von SZ
    Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl);

    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(1))); % rxBuffer
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(2))); % Befehl Verschaltung wurde erkannt
    logMsg(handles, '<<< ' + string(Empfangene_Zeilen(3))); % Verschaltung wrude ausgeführt / Spannungsdifferenz zu hoch / Ungueltige Befehlseingabe

    logMsg(handles, ''); % leere Zeile einfügen

    letzte_Zeile = Empfangene_Zeilen(3);


    %% Einfärben der Verbindungslinien
    objNames = {'L_Z1_d', 'L_Z1_R', 'L_Z1_GND','L_Z2_d', 'L_Z2_R', 'L_Z2_GND','L_Z3_d', 'L_Z3_R', 'L_Z3_GND'};
    
    % Schleife über alle 9 Werte
    for i = 1:9
        if Empfangene_Zeilen(3) == "Verschaltung wurde ausgefuehrt"
            if Auslesewerte(i) == 1
              set(handles.hZ.(objNames{i}), 'Color', [1 0 1]);   % magenta
            else
              set(handles.hZ.(objNames{i}), 'Color', [1 1 1]);   % weiß
            end
        end
    end

end