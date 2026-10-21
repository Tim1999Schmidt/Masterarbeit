
% Ctrl + C um Programm zu stoppen

% Die Tastenkombination zum Verschieben dder GUI
% ALT + Leertaste → V → Pfeiltasten → ENTER

% erstellen der GUI
%handles = Smarter_Zellhalter_GUI(); %optimierte Größe für großen Bildschirm
handles = Smarter_Zellhalter_mini_GUI(); %optimierte Größe für Laptop
logMsg(handles, 'GUI erfolgreich erstellt'); %Funktionsaufruf um etwas in das logMsg zu schreiben
logMsg(handles, ''); % leere Zeile einfügen

% Stellt verbindung mit Smarten Zellhalter her
set(handles.Connect, 'Callback', @(src,evt) Connect_func(handles));

% Hebt Verschaltung der Zellen auf
set(handles.Entkoppeln, 'Callback', @(src,evt) Entkoppeln_func(handles));

% Hebt Verschaltung der Zellen auf
set(handles.Koppeln, 'Callback', @(src,evt) Koppeln_func(handles));

% Überprüft Spannungs und Stromwerte der Zellen
set(handles.Zellen_Check, 'Callback', @(src,evt) Zellen_Check_func(handles));

% Bestimmt die Kontaktwiderstände der Zellen
set(handles.Kontakt_Check, 'Callback', @(src,evt) Kontakt_Check_func(handles));

% Setzt Einstellungen auf Anfangswerte zurück
set(handles.Reset, 'Callback', @(src,evt) Reset_func(handles));

% Einstellungen für EIS-Messung übernehmen
set(handles.Einstellungen_uebernehmen, 'Callback', @(src,evt) Einstellungen_uebernehmen_func(handles));

% Startet die EIS-Messung
set(handles.Messung_Starten, 'Callback', @(src,evt) Messung_Starten_func(handles));

% Stoppt die EIS-Messung
set(handles.Messung_Abbrechen, 'Callback', @(src,evt) Messung_Abbrechen_func(handles));