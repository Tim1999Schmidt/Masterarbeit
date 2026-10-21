function Kontakt_Check_func (handles)

device = getappdata(0, 'device'); %wird für writeline benötigt

Zeilenanzahl_1 = 3;
Zeilenanzahl_2 = 5;

logMsg(handles, 'Kontakt_Check gestartet'); %Funktionsaufruf um etwas in das logMsg zu schreiben

%% Reset Verschaltung und Sensor Position
Sens_Pos_Werte = [1, 1, 1, 1, 1, 1, 1, 1]; % P0, P1, P2, P3, P4, P5, P6, P7
                                           % nc, K1, K2, K3, K4, K5, K6, nc

Sensor_Position_setzen_func (handles, Sens_Pos_Werte); % alle Relais ausschalten

pause(0.2) % Wert noch nicht festgelegt

Verschaltungswerte = [0, 0, 0, 0, 0, 0, 0, 0, 0]; % Verschaltung rücksetzen; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.5) % Wert noch nicht festgelegt

%% EIS-Messung Z1 direkt
Verschaltungswerte = [1, 0, 1, 0, 0, 0, 0, 0, 0]; % Verschaltung auf Kanal_1; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;0;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z1_direkt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z1_direkt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z1_direkt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z1_direkt(3));

pause(0.1) % Wert noch nicht festgelegt

%% EIS-Messung Z2 direkt
Verschaltungswerte = [0, 0, 0, 1, 0, 1, 0, 0, 0]; % Verschaltung auf Kanal_2; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;1;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z2_direkt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z2_direkt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z2_direkt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z2_direkt(3));

pause(0.1) % Wert noch nicht festgelegt

%% EIS-Messung Z3 direkt
Verschaltungswerte = [0, 0, 0, 0, 0, 0, 1, 0, 1]; % Verschaltung auf Kanal_3; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;2;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z3_direkt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z3_direkt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z3_direkt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z3_direkt(3));

pause(0.1) % Wert noch nicht festgelegt

%% nur für Evaluierung der konstanten Widerstände auf dem Board verwenden, normal auskommentieren!!!
%Verschaltungswerte = [1, 0, 1, 1, 0, 1, 0, 0, 0]; % Verschaltung auf Einzelmessung setzen; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
%Verschalten_func (handles, Verschaltungswerte);

%% EIS-Messung Z1 mit Kontaktwiderstand
Verschaltungswerte = [1, 0, 1, 0, 0, 0, 0, 0, 0]; % Verschaltung auf Kanal_1; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

Sens_Pos_Werte = [1, 0, 0, 1, 1, 1, 1, 1];
Sensor_Position_setzen_func (handles, Sens_Pos_Werte);

pause(0.5) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;0;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z1_mit_Kontakt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z1_mit_Kontakt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z1_mit_Kontakt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z1_mit_Kontakt(3));

pause(0.1) % Wert noch nicht festgelegt

%% EIS-Messung Z2 mit Kontaktwiderstand
Verschaltungswerte = [0, 0, 0, 1, 0, 1, 0, 0, 0]; % Verschaltung auf Kanal_2; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

Sens_Pos_Werte = [1, 1, 1, 0, 0, 1, 1, 1];
Sensor_Position_setzen_func (handles, Sens_Pos_Werte);

pause(0.5) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;1;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z2_mit_Kontakt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z2_mit_Kontakt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z2_mit_Kontakt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z2_mit_Kontakt(3));

pause(0.1) % Wert noch nicht festgelegt

%% EIS-Messung Z3 mit Kontaktwiderstand
Verschaltungswerte = [0, 0, 0, 0, 0, 0, 1, 0, 1]; % Verschaltung auf Kanal_3; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

pause(0.2) % Wert noch nicht festgelegt

Sens_Pos_Werte = [1, 1, 1, 1, 1, 0, 0, 1];
Sensor_Position_setzen_func (handles, Sens_Pos_Werte);

pause(0.5) % Wert noch nicht festgelegt

writeline(device, 'Befehl_EIS;2;28;28;1;0;5'); % String: Befehl_EIS;0;0;0;0;0;0 % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_1); % Empfängt Zeilen über COM von SZ

Empfangene_Zeilen = COM_Auslesen_func(device, Zeilenanzahl_2); % Empfangen der Ergebnisse

Ergebnisse_Z3_mit_Kontakt = round(sscanf(Empfangene_Zeilen{2}, '%f'), 2).';
fprintf("<<< %.2f\n", Ergebnisse_Z3_mit_Kontakt(1));
fprintf("<<< %.2f\n", Ergebnisse_Z3_mit_Kontakt(2));
fprintf("<<< %.2f\n", Ergebnisse_Z3_mit_Kontakt(3));

pause(0.1) % Wert noch nicht festgelegt

%% Reset Relais + Verschaltung
Sens_Pos_Werte = [1, 1, 1, 1, 1, 1, 1, 1];
Sensor_Position_setzen_func (handles, Sens_Pos_Werte); % alle Relais ausschalten

pause(0.5) % Wert noch nicht festgelegt

Verschaltungswerte = [0, 0, 0, 0, 0, 0, 0, 0, 0]; % Verschaltung rücksetzen; Z1_direkt, Z1_R, Z1_GND, Z2_direkt, Z2_R, Z2_GND, Z3_direkt, Z3_R, Z3_GND,
Verschalten_func (handles, Verschaltungswerte);

%%
% Berechnung der Kontaktwiderstände
Kontaktwiderstand_Z1 = Ergebnisse_Z1_mit_Kontakt(2) - Ergebnisse_Z1_direkt(2);
fprintf("Kontaktwiderstand_Z1: %.2f\n", Kontaktwiderstand_Z1);
Kontaktwiderstand_Z2 = Ergebnisse_Z2_mit_Kontakt(2) - Ergebnisse_Z2_direkt(2);
fprintf("Kontaktwiderstand_Z2: %.2f\n", Kontaktwiderstand_Z2);
Kontaktwiderstand_Z3 = Ergebnisse_Z3_mit_Kontakt(2) - Ergebnisse_Z3_direkt(2);
fprintf("Kontaktwiderstand_Z3: %.2f\n", Kontaktwiderstand_Z3);

% Rückgabe der Ergebnisse
set(handles.Text_Kontakt_Z1,'String',Kontaktwiderstand_Z1);

set(handles.Text_Kontakt_Z2,'String',Kontaktwiderstand_Z2);

set(handles.Text_Kontakt_Z3,'String',Kontaktwiderstand_Z3);

akt_Kontaktwerte_fuer_Textfile = [Kontaktwiderstand_Z1, Kontaktwiderstand_Z2, Kontaktwiderstand_Z3];
setappdata(0, 'akt_Kontaktwerte_fuer_Textfile', akt_Kontaktwerte_fuer_Textfile);

logMsg(handles, 'Kontakt_Check beendet'); %Funktionsaufruf um etwas in das logMsg zu schreiben

logMsg(handles, ''); % leere Zeile einfügen

end