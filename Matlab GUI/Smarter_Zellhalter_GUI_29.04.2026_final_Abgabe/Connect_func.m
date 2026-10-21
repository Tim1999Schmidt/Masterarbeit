function Connect_func (handles)

port = ['COM' num2str(get(handles.COM, 'Value'))]; % hier wird z.B. 5 zu COM5
baud = 38400;

logMsg(handles, 'Verbindung wird aufgebaut'); %Funktionsaufruf um etwas in das logMsg zu schreiben
logMsg(handles, 'COM: ' + string(port));

device = serialport(port, baud);
configureTerminator(device, "LF");   % ggf. "CR" oder "CR/LF"
device.Timeout = 10000; % Zeit, so lange auf eine Antwort gewartet wird
configureCallback(device, "off");   % sicherheitshalber

setappdata(0, 'device', device);

Zeilenanzahl = 5;

% Sendet den Befehl über COM an SZ
writeline(device, 'Befehl_Connect');
% Empfängt Zeilen über COM von SZ
werte = COM_Auslesen_func(device, Zeilenanzahl);

logMsg(handles, '<<< ' + string(werte(1))); % Befehl_Connect wurde erkannt
logMsg(handles, '<<< ' + string(werte(2))); % Verbindung wurde hergestellt
logMsg(handles, '<<< ' + string(werte(3))); % Testprojekt_31_03_2026_v1 ist aktiv
logMsg(handles, '<<< ' + string(werte(4))); % Warten auf Befehl!

logMsg(handles, ''); % leere Zeile einfügen

end