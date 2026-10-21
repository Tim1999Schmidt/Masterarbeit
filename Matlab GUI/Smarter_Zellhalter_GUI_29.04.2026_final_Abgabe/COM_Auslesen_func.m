function zeilen = COM_Auslesen_func(device, nZeilen)
% zeilen = leseZeilen(dev, nZeilen)
%  device  : serialport-Objekt
%  nZeilen : Anzahl erwarteter Textzeilen
%
% Rückgabe:
%  zeilen  : String-Array mit nZeilen Einträgen

    flush(device, "input"); %leert den input Buffer des COMs um immer von neu zu beginnen

    zeilen = strings(1, nZeilen);   % Platz reservieren
    
    pause(0.01)   % ansonsten werden die ersten paar Zeichen evtl nicht richtig gelesen

    for k = 1:nZeilen
        % Zeile lesen
        zeile = strtrim(readline(device));

        % Debug-Ausgabe
        fprintf("<<< %s\n", zeile);

        % direkt speichern
        zeilen(k) = zeile;
    end

    fprintf("\n");

    pause(0.01)   % ansonsten wird eine Folgeabfrage evtl nicht richtig ausgeführt

end