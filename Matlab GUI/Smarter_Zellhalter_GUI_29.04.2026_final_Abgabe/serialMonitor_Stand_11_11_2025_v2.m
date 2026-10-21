% === Serieller Monitor mit dynamischem Ordner & Dateiname (robust) ===

port = "COM5";
baud = 38400;

logRoot = "Y:\Desktop_Verknüpfungen\Matlab_Test";      % "" = aktueller Ordner
if ~isempty(logRoot) && ~exist(logRoot, 'dir')
    mkdir(logRoot);
end

device = serialport(port, baud);
configureTerminator(device, "LF");   % ggf. "CR" oder "CR/LF"
device.Timeout = 5;

% --- UserData initialisieren ---
ud = struct( ...
    'logRoot',     logRoot, ...
    'recording',   false, ...
    'waitingName', false, ...
    'fileID',      -1, ...
    'filename',    "", ...
    'foldername',  "" ...
);
device.UserData = ud;

% --- Callback aktivieren --- Automatisches Mitlesen aktivieren (Zeile für Zeile) ---
configureCallback(device, "terminator", @serialCallback);

% Kleine „Sende-Funktion“ für das Command Window
sendLine = @(txt) writeline(device, string(txt));

disp("Serieller Monitor läuft.");
disp("Nach 'Anfang Messergebnisse' wird nächste Zeile als Dateiname genutzt.");
disp("Es wird ein gleichnamiger Ordner mit Textdatei angelegt.");

% ======= Lokale Callback-Funktion =======
function serialCallback(src, ~)
    try
        % --- Safety: UserData prüfen ---
        if ~isstruct(src.UserData)
            ud = struct('logRoot',"",'recording',false,'waitingName',false,'fileID',-1,'filename',"",'foldername',"");
        else
            ud = src.UserData;
            neededFields = {'logRoot','recording','waitingName','fileID','filename','foldername'};
            for f = neededFields
                if ~isfield(ud, f{1})
                    ud.(f{1}) = [];
                end
            end
            % Standardwerte ergänzen
            if isempty(ud.logRoot),     ud.logRoot = ""; end
            if isempty(ud.recording),   ud.recording = false; end
            if isempty(ud.waitingName), ud.waitingName = false; end
            if isempty(ud.fileID),      ud.fileID = -1; end
            if isempty(ud.filename),    ud.filename = ""; end
            if isempty(ud.foldername),  ud.foldername = ""; end
        end

        % --- Zeile lesen ---
        raw  = readline(src);
        line = strtrim(string(raw));
        if line == ""; return; end

        % --- Alles im Command Window anzeigen ---
        disp("<<< " + line);

        % === Marker: Anfang Messergebnisse ===
        if strcmpi(line, "Anfang Messergebnisse")
            if ud.recording && ud.fileID > 0
                fclose(ud.fileID);
            end
            ud.waitingName = true;
            ud.recording   = false;
            ud.fileID      = -1;
            ud.filename    = "";
            ud.foldername  = "";
            src.UserData = ud;
            return;
        end

        % === Marker: Ende Messergebnisse ===
        if strcmpi(line, "Ende Messergebnisse")
            if ud.recording && ud.fileID > 0
                fclose(ud.fileID);
                disp(">>> Logdatei geschlossen: " + ud.filename);
            end
            ud.recording   = false;
            ud.waitingName = false;
            ud.fileID      = -1;
            ud.filename    = "";
            ud.foldername  = "";
            src.UserData = ud;
            return;
        end

        % === Nächste Zeile nach 'Anfang Messergebnisse' = Basisname ===
        if ud.waitingName
            ts = char(datetime('now','Format','yyyy-MM-dd_HHmmss'));
            baseName = line + "_" + string(ts);

            % Neuen Unterordner anlegen
            if ~isempty(ud.logRoot)
                folder = fullfile(ud.logRoot, baseName);
            else
                folder = baseName;
            end
            if ~exist(folder, 'dir')
                mkdir(folder);
            end

            % Datei im Ordner anlegen
            fname = fullfile(folder, baseName + ".txt");
            fid = fopen(fname, "w");
            assert(fid > 0, "Konnte Logdatei nicht öffnen: %s", fname);

            % Kopfzeile
            fprintf(fid, 'freq/Hz\tRe(Z)/Ohm\tIm(Z)/Ohm\n');

            ud.fileID      = fid;
            ud.filename    = fname;
            ud.foldername  = folder;
            ud.recording   = true;
            ud.waitingName = false;
            src.UserData = ud;

            disp(">>> Neuer Ordner: " + folder);
            disp(">>> Neue Logdatei: " + fname);
            return;
        end

        % === Datenzeilen verarbeiten ===
        if ud.recording && ud.fileID > 0
            vals = sscanf(line, '%f %f %f');
            if numel(vals) == 3
                f  = vals(1);
                Re = vals(2) / 1000;
                Im = vals(3) / 1000;
                out_line = sprintf('%14.7E\t%14.7E\t%14.7E', f, Re, Im);
                out_line = strrep(out_line, '.', ',');
                fprintf(ud.fileID, '%s\n', out_line);
            end
        end

    catch ME
        warning("Callback-Fehler: " + ME.message);
    end
end


% serialMonitor_Stand_11_11_2025_v2
% im Command Window kann über den Befehl
% sendLine('abc')
% eine Zeile gesendet werden
% die Empfangenden Daten werden dann automatisch aufgelistet

% Zum Beenden in Command Window
% configureCallback(device, "off");
% clear device

% Zum Oszitest den Schwarzen knopf am Nucleo drücken0