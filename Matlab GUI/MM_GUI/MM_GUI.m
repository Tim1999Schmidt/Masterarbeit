function MM_GUI()
% MM_GUI  Bedienoberflaeche fuer das Batteriespeicher-Testsystem (MM + BMs + PMs)
%
% Die GUI spricht nur mit dem Mastermodul (MM, Nucleo-F303RE) ueber den
% virtuellen COM-Port des ST-LINK (115200 Baud). Das MM koordiniert die
% Boards am I2C-Bus:
%   BM (Batteriemodul)  : Zellspannung, -strom, Tab-Temperatur, EIS-Messung
%   PM (Peltiermodul)   : Temperaturregelung der Zelle
%
% Zu jeder Zelle gehoeren ein BM (EIS-Messung) und ein PM (Temperaturregelung):
% BM k und PM k (k-te Adresse der jeweiligen Liste) bilden Zelle k.
%
% Funktionen
%   - Boardliste (Adressen der BMs/PMs) lesen, aendern, im MM speichern, Bus-Scan
%   - Zellenuebersicht: je Zelle eine Spalte mit den Werten von BM und PM
%     (wird jede Sekunde abgefragt)
%   - Temperaturregelung der PMs: Sollwert, Start/Stopp, Stromgrenze, Temperaturquelle
%   - EIS-Messung: einzelne Zelle, Stack, alle Zellen nacheinander (+ Stack);
%     Ergebnis je Messung als Textdatei (Punkt- und Komma-Version) wie bei der
%     Zellhalter-GUI, Nyquist-Plot
%
% Protokoll: siehe MM/Core/Inc/host_comm.h
%
% Start: MM_GUI   (beendet wird ueber das Schliessen des Fensters)

    %% ---- Konstanten ----------------------------------------------------------
    BAUD_RATE            = 115200;
    STAT_PERIOD_S        = 1;          % Statusabfrage der Boards
    SERIAL_TIMEOUT_S     = 2;
    NUM_FREQ             = 52;         % Frequenzindex 0..51 (wie BM)
    F_MAX_CENTI_HZ       = 781250;     % Index 0 = 7812.50 Hz
    FREQ_STEPS_PER_OCTAVE = 4;
    CENTI                = 100;        % Werte in 1/100 (degC x100, Hz x100)
    MILLI                = 1000;       % mA -> A
    PERMILLE_PER_PERCENT = 10;         % Duty Cycle: Promille -> %
    MICRO_TO_MILLI       = 1e-3;       % uOhm -> mOhm (Plot)
    MAX_AVERAGES         = 9;
    DEFAULT_START_INDEX  = 0;
    DEFAULT_STOP_INDEX   = NUM_FREQ - 1;
    DEFAULT_AMPLITUDE    = 2;          % 100 mA (Listeneintrag)
    DEFAULT_TSET_DEGC    = 25;
    DEFAULT_ILIM_A       = 3;          % = Standard und Maximum des PM
    PROGRESS_IDLE        = 255;
    FIRST_CELL_LETTER    = 'A';        % Standard-Zellnamen Zelle_A, Zelle_B, ...

    % Zellenuebersicht: Zeilen {Schluessel, Beschriftung}; Schluessel mit '#' = Abschnittsueberschrift
    GRID_ROWS = { ...
        'name',    'Zellname';
        '#BM',     'BM - EIS-Messung';
        'bmAddr',  'Adresse';
        'bmState', 'Zustand';
        'u',       'Spannung [mV]';
        'i',       'Strom [mA]';
        'tTab',    'T Tab [°C]';
        'eis',     'EIS-Chips';
        'conz',    'CONNECT_Z';
        '#PM',     'PM - Temperaturregelung';
        'pmAddr',  'Adresse';
        'pmState', 'Zustand';
        'tSet',    'T Soll [°C]';
        'tAct',    'T Ist [°C]';
        'tPt',     'T PT1000 [°C]';
        'iPm',     'Strom [A]';
        'duty',    'Duty [%]';
        'ilim',    'I max [A]';
        'src',     'Regelt nach'};
    GRID_LABEL_WIDTH     = 0.22;       % Anteil der Beschriftungsspalte an der Breite
    GRID_FONT_SIZE       = 9;
    COLOR_HEADER         = [0.80 0.86 0.95];   % Kopfzeile "Zelle k"
    COLOR_SECTION        = [0.90 0.90 0.90];   % Abschnitt BM / PM
    COLOR_LABEL          = [0.96 0.96 0.96];   % Beschriftungsspalte
    COLOR_VALUE          = [1 1 1];
    COLOR_STATE_OK       = [0.85 0.97 0.85];   % bereit / aus
    COLOR_STATE_ACTIVE   = [1.00 0.97 0.75];   % EIS laeuft / regelt
    COLOR_STATE_ERROR    = [1.00 0.82 0.82];
    COLOR_STATE_OFFLINE  = [0.85 0.85 0.85];
    COLOR_NO_BOARD       = [0.93 0.93 0.93];   % Zelle ohne BM bzw. PM

    % STATUS-Bits (bm_regs.h / pm_regs.h)
    BM_ST_EIS_BUSY = 1;  BM_ST_ERROR = 4;  BM_ST_TEMP_VALID = 8;
    BM_NUM_EIS_WITH_STACK = 2;         % BM mit zweitem TLE9010 fuer den Stack
    PM_ST_RUNNING  = 1;  PM_ST_ERROR = 2;  PM_ST_COOLING = 4;  PM_ST_TEMP_VALID = 8;

    BM_ERROR_TEXT = {'kein Fehler', 'EIS-Parameter', 'beschaeftigt', 'EIS-Kommunikation', ...
                     'CONNECT_Z passt nicht', 'Tab-Temperatursensor', 'TLE9015 ERRQ', 'Flash', ...
                     'EIS-ADC uebersteuert'};
    PM_ERROR_TEXT = {'kein Fehler', 'Ueberstrom beim Start', 'Ueberstrom im Betrieb', ...
                     'Plausibilitaet (Regelung)', 'PT1000 unplausibel', 'externe Temperatur fehlt', ...
                     'kein Peltier angeschlossen', 'Temperaturkalibrierung'};
    EIS_REASON_TEXT = containers.Map( ...
        {'OFFLINE', 'UDIFF', 'NOSTACK', 'CONNECTZ', 'START', 'SWEEP', 'STALL', 'READ', 'ABORTED'}, ...
        {'BM antwortet nicht', 'Spannungsdifferenz der Zellen zu hoch (> 50 mV)', ...
         'kein BM mit Stack-Chip', 'CONNECT_Z hat nicht geschaltet', 'Messung startete nicht', ...
         'Messung ohne Ergebnis beendet', 'kein Fortschritt (Timeout)', ...
         'Ergebnisse nicht lesbar', 'abgebrochen'});

    AMPLITUDE_TEXT = {'50 mA', '100 mA', '200 mA', '300 mA', '400 mA', '500 mA'};
    WAVEFORM_TEXT  = {'Sinus', 'Rechteck'};
    FREQ_HZ        = frequencyTable();
    FREQ_TEXT      = arrayfun(@(k) sprintf('(%2d) %8.2f Hz', k - 1, FREQ_HZ(k)), 1:NUM_FREQ, ...
                              'UniformOutput', false);

    %% ---- Zustand (von allen verschachtelten Funktionen geteilt) -------------
    device     = [];              % serialport-Objekt
    statTimer  = [];
    cfg        = struct('bmAddr', {{}}, 'pmAddr', {{}}, 'pmSource', []);
    cellNames  = strings(1, 0);              % Zellnamen (in der Zellenuebersicht editierbar)
    gridH      = struct();                   % Handles der Zellenuebersicht: gridH.<Zeile>(Zelle)
    numCells   = 0;                          % Spalten der Zellenuebersicht
    bmLast     = struct('u', {}, 't', {});   % letzte Messwerte je BM (fuer die Datei)
    pmLast     = struct('tAct', {}, 'tPt', {}, 'tSet', {});
    meas       = containers.Map();           % laufende Messung je Ziel ('C1', 'S', ...)
    jobInfo    = struct('folder', pwd, 'baseName', 'Messung', 'timestamp', '', 'comment', '', ...
                        'cellNames', strings(0, 1), 'settings', struct('fStart', DEFAULT_START_INDEX, ...
                        'fStop', DEFAULT_STOP_INDEX, 'amplitude', '', 'waveform', '', 'averages', 1));  % laufender Auftrag
    plotHandles = containers.Map();

    %% ---- Fenster ---------------------------------------------------------------
    figs = findall(0, 'Type', 'figure', 'Tag', 'MM_GUI');
    delete(figs);
    fig = figure('Name', 'Batteriespeicher-Testsystem (MM)', 'Tag', 'MM_GUI', ...
                 'NumberTitle', 'off', 'MenuBar', 'none', 'Units', 'pixels', ...
                 'Position', [40 40 1320 880], 'CloseRequestFcn', @onClose);

    % Verbindung
    pConn = uipanel(fig, 'Title', 'Verbindung', 'Units', 'normalized', 'Position', [0.005 0.935 0.49 0.06]);
    hCom  = uicontrol(pConn, 'Style', 'popupmenu', 'String', {'-'}, 'Units', 'normalized', 'Position', [0.01 0.15 0.18 0.7]);
    uicontrol(pConn, 'Style', 'pushbutton', 'String', 'Ports suchen', 'Units', 'normalized', ...
              'Position', [0.20 0.1 0.15 0.8], 'Callback', @(~, ~) refreshPorts());
    hConnect = uicontrol(pConn, 'Style', 'pushbutton', 'String', 'Verbinden', 'Units', 'normalized', ...
              'Position', [0.36 0.1 0.15 0.8], 'Callback', @(~, ~) toggleConnection());
    hConnState = uicontrol(pConn, 'Style', 'text', 'String', 'nicht verbunden', 'Units', 'normalized', ...
              'Position', [0.53 0.1 0.46 0.65], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    % Zellenuebersicht: je Zelle eine Spalte, darunter BM und PM der Zelle
    pBoards = uipanel(fig, 'Title', 'Zellen (BM + PM)', 'Units', 'normalized', 'Position', [0.005 0.47 0.49 0.46]);
    pGrid = uipanel(pBoards, 'BorderType', 'none', 'Units', 'normalized', 'Position', [0.005 0.10 0.99 0.895]);
    uicontrol(pBoards, 'Style', 'text', 'String', 'BM-Adr.:', 'Units', 'normalized', 'Position', [0.01 0.015 0.08 0.06], 'HorizontalAlignment', 'left');
    hBmAddr = uicontrol(pBoards, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.09 0.015 0.17 0.07], ...
        'TooltipString', 'z. B. 0x10, 0x11 (Reihenfolge = Zelle 1, Zelle 2, ...)');
    uicontrol(pBoards, 'Style', 'text', 'String', 'PM-Adr.:', 'Units', 'normalized', 'Position', [0.27 0.015 0.08 0.06], 'HorizontalAlignment', 'left');
    hPmAddr = uicontrol(pBoards, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.35 0.015 0.17 0.07], ...
        'TooltipString', 'z. B. 0x20, 0x21 (Reihenfolge = Zelle 1, Zelle 2, ...)');
    uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Liste übernehmen', 'Units', 'normalized', ...
        'Position', [0.53 0.01 0.16 0.08], 'Callback', @(~, ~) applyBoardList());
    uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Im MM speichern', 'Units', 'normalized', ...
        'Position', [0.70 0.01 0.15 0.08], 'Callback', @(~, ~) sendCommand('SAVE'));
    uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Bus-Scan', 'Units', 'normalized', ...
        'Position', [0.86 0.01 0.13 0.08], 'Callback', @(~, ~) sendCommand('SCAN'));

    % Temperaturregelung
    pTemp = uipanel(fig, 'Title', 'Temperaturregelung (PM)', 'Units', 'normalized', 'Position', [0.005 0.30 0.49 0.165]);
    uicontrol(pTemp, 'Style', 'text', 'String', 'Zelle:', 'Units', 'normalized', 'Position', [0.01 0.62 0.05 0.25], 'HorizontalAlignment', 'left');
    hPmSelect = uicontrol(pTemp, 'Style', 'popupmenu', 'String', {'alle Zellen'}, 'Units', 'normalized', 'Position', [0.06 0.62 0.15 0.28]);
    uicontrol(pTemp, 'Style', 'text', 'String', 'T Soll [°C]:', 'Units', 'normalized', 'Position', [0.23 0.62 0.11 0.25], 'HorizontalAlignment', 'left');
    hTset = uicontrol(pTemp, 'Style', 'edit', 'String', num2str(DEFAULT_TSET_DEGC), 'Units', 'normalized', 'Position', [0.34 0.62 0.08 0.28]);
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Sollwert setzen', 'Units', 'normalized', 'Position', [0.43 0.62 0.15 0.28], ...
        'Callback', @(~, ~) pmSetpoint());
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Start', 'Units', 'normalized', 'Position', [0.60 0.62 0.12 0.28], ...
        'Callback', @(~, ~) pmCommand('PMSTART'));
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Stopp', 'Units', 'normalized', 'Position', [0.73 0.62 0.12 0.28], ...
        'Callback', @(~, ~) pmCommand('PMSTOP'));
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Fehler löschen', 'Units', 'normalized', 'Position', [0.86 0.62 0.13 0.28], ...
        'Callback', @(~, ~) pmCommand('PMCLR'));
    uicontrol(pTemp, 'Style', 'text', 'String', 'I max [A]:', 'Units', 'normalized', 'Position', [0.01 0.15 0.09 0.25], 'HorizontalAlignment', 'left');
    hIlim = uicontrol(pTemp, 'Style', 'edit', 'String', num2str(DEFAULT_ILIM_A), 'Units', 'normalized', 'Position', [0.10 0.15 0.07 0.28]);
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Setzen', 'Units', 'normalized', 'Position', [0.18 0.15 0.09 0.28], ...
        'Callback', @(~, ~) pmCurrentLimit());
    uicontrol(pTemp, 'Style', 'text', 'String', 'Regelt nach:', 'Units', 'normalized', 'Position', [0.30 0.15 0.11 0.25], 'HorizontalAlignment', 'left');
    hPmSource = uicontrol(pTemp, 'Style', 'popupmenu', 'String', {'PT1000 am PM'}, 'Units', 'normalized', 'Position', [0.41 0.15 0.26 0.28]);
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Quelle setzen', 'Units', 'normalized', 'Position', [0.68 0.15 0.14 0.28], ...
        'Callback', @(~, ~) pmSourceSet());
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Neu kalibrieren', 'Units', 'normalized', 'Position', [0.83 0.15 0.16 0.28], ...
        'Callback', @(~, ~) pmCommand('PMRECAL'));

    % EIS
    pEis = uipanel(fig, 'Title', 'EIS-Messung (BM)', 'Units', 'normalized', 'Position', [0.005 0.005 0.49 0.29]);
    labelsLeft = {'Messung:', 'Start-Frequenz:', 'Stopp-Frequenz:', 'Amplitude:', 'Signalform:', 'Mittelung:'};
    LABEL_ROW_STEP = 0.13;
    for row = 1:numel(labelsLeft)
        uicontrol(pEis, 'Style', 'text', 'String', labelsLeft{row}, 'Units', 'normalized', ...
            'Position', [0.01 0.86 - (row - 1) * LABEL_ROW_STEP 0.15 0.1], 'HorizontalAlignment', 'left');
    end
    hTarget = uicontrol(pEis, 'Style', 'popupmenu', 'String', {'Zelle 1'}, 'Units', 'normalized', 'Position', [0.16 0.86 0.26 0.11]);
    hFstart = uicontrol(pEis, 'Style', 'popupmenu', 'String', FREQ_TEXT, 'Value', DEFAULT_START_INDEX + 1, 'Units', 'normalized', 'Position', [0.16 0.73 0.26 0.11]);
    hFstop  = uicontrol(pEis, 'Style', 'popupmenu', 'String', FREQ_TEXT, 'Value', DEFAULT_STOP_INDEX + 1, 'Units', 'normalized', 'Position', [0.16 0.60 0.26 0.11]);
    hAmp    = uicontrol(pEis, 'Style', 'popupmenu', 'String', AMPLITUDE_TEXT, 'Value', DEFAULT_AMPLITUDE, 'Units', 'normalized', 'Position', [0.16 0.47 0.26 0.11]);
    hWave   = uicontrol(pEis, 'Style', 'popupmenu', 'String', WAVEFORM_TEXT, 'Units', 'normalized', 'Position', [0.16 0.34 0.26 0.11]);
    hAvg    = uicontrol(pEis, 'Style', 'popupmenu', 'String', arrayfun(@num2str, 1:MAX_AVERAGES, 'UniformOutput', false), ...
                        'Units', 'normalized', 'Position', [0.16 0.21 0.26 0.11]);
    labelsRight = {'Zielordner:', 'Dateiname:', 'Kommentar:'};
    for row = 1:numel(labelsRight)
        uicontrol(pEis, 'Style', 'text', 'String', labelsRight{row}, 'Units', 'normalized', ...
            'Position', [0.45 0.86 - (row - 1) * LABEL_ROW_STEP 0.11 0.1], 'HorizontalAlignment', 'left');
    end
    hFolder   = uicontrol(pEis, 'Style', 'edit', 'String', pwd, 'Units', 'normalized', 'Position', [0.56 0.87 0.36 0.1]);
    uicontrol(pEis, 'Style', 'pushbutton', 'String', '...', 'Units', 'normalized', 'Position', [0.93 0.87 0.06 0.1], ...
        'Callback', @(~, ~) chooseFolder());
    hFilename = uicontrol(pEis, 'Style', 'edit', 'String', 'Messung', 'Units', 'normalized', 'Position', [0.56 0.74 0.43 0.1]);
    hComment  = uicontrol(pEis, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.56 0.61 0.43 0.1]);
    uicontrol(pEis, 'Style', 'text', 'String', 'Zellnamen: in der Zellenübersicht oben eintragen', 'Units', 'normalized', ...
        'Position', [0.45 0.47 0.54 0.1], 'HorizontalAlignment', 'left', 'ForegroundColor', [0.4 0.4 0.4]);
    hStart = uicontrol(pEis, 'Style', 'pushbutton', 'String', 'Messung starten', 'Units', 'normalized', 'Position', [0.45 0.22 0.26 0.14], ...
        'FontWeight', 'bold', 'Callback', @(~, ~) startEis());
    hAbort = uicontrol(pEis, 'Style', 'pushbutton', 'String', 'Abbrechen', 'Units', 'normalized', 'Position', [0.73 0.22 0.26 0.14], ...
        'Enable', 'off', 'Callback', @(~, ~) sendCommand('ABORT'));
    hProgress = uicontrol(pEis, 'Style', 'text', 'String', 'keine Messung aktiv', 'Units', 'normalized', ...
        'Position', [0.01 0.02 0.98 0.12], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    % Nyquist-Plot und Log
    ax = axes(fig, 'Units', 'normalized', 'Position', [0.55 0.42 0.43 0.54]);
    grid(ax, 'on'); hold(ax, 'on'); axis(ax, 'equal');
    xlabel(ax, 'Re(Z) [m\Omega]'); ylabel(ax, '-Im(Z) [m\Omega]'); title(ax, 'Nyquist');
    hLog = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', 'Position', [0.50 0.005 0.495 0.36], ...
        'FontName', 'Consolas', 'FontSize', 8, 'Max', 2, 'Min', 0, 'String', {});

    refreshPorts();
    setConnectedUi(false);
    logMsg('GUI gestartet');

    %% =========================================================================
    %  Verbindung
    %  =========================================================================
    function refreshPorts()
        ports = serialportlist("available");
        if isempty(ports)
            ports = "-";
        end
        set(hCom, 'String', cellstr(ports), 'Value', 1);
    end

    function toggleConnection()
        if isempty(device)
            connect();
        else
            disconnect();
        end
    end

    function connect()
        ports = get(hCom, 'String');
        port = ports{get(hCom, 'Value')};
        if strcmp(port, '-')
            logMsg('kein COM-Port gefunden');
            return;
        end
        try
            device = serialport(port, BAUD_RATE, 'Timeout', SERIAL_TIMEOUT_S);
            configureTerminator(device, "LF");
            flush(device);
            configureCallback(device, "terminator", @onSerialLine);
        catch ex
            device = [];
            logMsg(['Verbindung fehlgeschlagen: ' ex.message]);
            return;
        end
        logMsg(['verbunden mit ' port]);
        setConnectedUi(true);
        sendCommand('HELLO');
        sendCommand('CFG?');
        statTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', STAT_PERIOD_S, ...
                          'BusyMode', 'drop', 'TimerFcn', @(~, ~) sendCommand('STAT', false));
        start(statTimer);
    end

    function disconnect()
        if ~isempty(statTimer) && isvalid(statTimer)
            stop(statTimer);
            delete(statTimer);
        end
        statTimer = [];
        if ~isempty(device)
            configureCallback(device, "off");
            delete(device);
        end
        device = [];
        setConnectedUi(false);
        logMsg('Verbindung getrennt');
    end

    function setConnectedUi(connected)
        if connected
            set(hConnect, 'String', 'Trennen');
            set(hConnState, 'String', 'verbunden');
        else
            set(hConnect, 'String', 'Verbinden');
            set(hConnState, 'String', 'nicht verbunden');
        end
    end

    function onClose(~, ~)
        disconnect();
        delete(fig);
    end

    function sendCommand(cmd, logIt)
        if nargin < 2
            logIt = true;
        end
        if isempty(device)
            if logIt
                logMsg('nicht verbunden');
            end
            return;
        end
        writeline(device, cmd);
        if logIt
            logMsg(['>>> ' cmd]);
        end
    end

    %% =========================================================================
    %  Empfang: jede Zeile des MM
    %  =========================================================================
    function onSerialLine(src, ~)
        try
            rxLine = strtrim(readline(src));
        catch
            return;
        end
        if strlength(rxLine) == 0
            return;
        end
        f = split(rxLine, ';');
        try
            switch f(1)
                case "BM",       onBmStatus(f);
                case "PM",       onPmStatus(f);
                case "MM",       onMmStatus(f);
                case "CFG",      onConfig(f);
                case "EISBEGIN", onEisBegin(f);
                case "EISCELL",  onEisCell(f);
                case "PROG",     onEisProgress(f);
                case "RES",      onEisResult(f);
                case "EISEND",   onEisEnd(f);
                case "EISDONE",  onEisDone(f);
                case "OK"
                    if f(2) ~= "STAT"          % zyklische Abfrage nicht protokollieren
                        logMsg(['<<< ' char(rxLine)]);
                    end
                otherwise
                    logMsg(['<<< ' char(rxLine)]);
            end
        catch ex
            logMsg(['Fehler bei Zeile "' char(rxLine) '": ' ex.message]);
        end
    end

    function onBmStatus(f)
        % BM;k;addr;online;status;err;u_mV;i_mA;t_cdegC;numEis;progress;connectZ
        k = str2double(f(2));
        if k > numCells
            return;                                % Uebersicht noch nicht aufgebaut
        end
        status = str2double(f(5));  err = str2double(f(6));
        online = str2double(f(4)) == 1;
        bmLast(k).u = str2double(f(7));
        bmLast(k).t = str2double(f(9)) / CENTI;
        [stateText, stateColor] = bmState(online, status, err, str2double(f(11)));
        setGrid('bmState', k, stateText, stateColor);
        if ~online
            setGrid({'u', 'i', 'tTab', 'eis', 'conz'}, k, '-');
            return;
        end
        tText = 'ungültig';
        if bitand(status, BM_ST_TEMP_VALID)
            tText = sprintf('%.2f', bmLast(k).t);
        end
        eisText = sprintf('%d', str2double(f(10)));
        if str2double(f(10)) >= BM_NUM_EIS_WITH_STACK
            eisText = [eisText ' (Zelle + Stack)'];
        end
        setGrid('u',    k, sprintf('%d', bmLast(k).u));
        setGrid('i',    k, sprintf('%d', str2double(f(8))));
        setGrid('tTab', k, tText);
        setGrid('eis',  k, eisText);
        setGrid('conz', k, onOffText(str2double(f(12)) == 1));
    end

    function onPmStatus(f)
        % PM;k;addr;online;status;err;tset;tact;tpt;i_mA;duty;ilim;src
        k = str2double(f(2));
        if k > numCells
            return;                                % Uebersicht noch nicht aufgebaut
        end
        status = str2double(f(5));  err = str2double(f(6));
        online = str2double(f(4)) == 1;
        src = str2double(f(13));
        pmLast(k).tSet = str2double(f(7)) / CENTI;
        pmLast(k).tAct = str2double(f(8)) / CENTI;
        pmLast(k).tPt  = str2double(f(9)) / CENTI;
        [stateText, stateColor] = pmState(online, status, err);
        setGrid('pmState', k, stateText, stateColor);
        setGrid('src', k, sourceText(src));
        if ~online
            setGrid({'tSet', 'tAct', 'tPt', 'iPm', 'duty', 'ilim'}, k, '-');
            return;
        end
        setGrid('tSet', k, sprintf('%.2f', pmLast(k).tSet));
        setGrid('tAct', k, sprintf('%.2f', pmLast(k).tAct));
        setGrid('tPt',  k, sprintf('%.2f', pmLast(k).tPt));
        setGrid('iPm',  k, sprintf('%.2f', str2double(f(10)) / MILLI));
        setGrid('duty', k, sprintf('%.1f', str2double(f(11)) / PERMILLE_PER_PERCENT));
        setGrid('ilim', k, sprintf('%.2f', str2double(f(12)) / MILLI));
    end

    function onMmStatus(f)
        % MM;eisBusy;i2cErrors
        busy = str2double(f(2)) == 1;
        set(hStart, 'Enable', onOff(~busy));
        set(hAbort, 'Enable', onOff(busy));
    end

    function onConfig(f)
        % CFG;BM;n;addr...  CFG;PM;n;addr...  CFG;SRC;src...
        switch f(2)
            case "BM"
                cfg.bmAddr = cellstr(f(4:end));
                set(hBmAddr, 'String', strjoin(cfg.bmAddr, ', '));
                bmLast = struct('u', {}, 't', {});
            case "PM"
                cfg.pmAddr = cellstr(f(4:end));
                set(hPmAddr, 'String', strjoin(cfg.pmAddr, ', '));
                pmLast = struct('tAct', {}, 'tPt', {}, 'tSet', {});
            case "SRC"                                 % letzte Zeile der Antwort auf CFG?
                cfg.pmSource = str2double(f(3:end));
                buildCellGrid();
                updateSelectionLists();
        end
    end

    %% =========================================================================
    %  Zellenuebersicht
    %  =========================================================================
    % Aufbau (eine Spalte je Zelle, Zelle k = BM k + PM k):
    %
    %                  | Zelle 1     | Zelle 2     |
    %   Zellname       | [Zelle_A ]  | [Zelle_B ]  |   <- editierbar
    %   BM - EIS-Messung ---------------------------
    %   Adresse        | 0x10        | 0x11        |
    %   ...
    %   PM - Temperaturregelung --------------------
    %   ...
    % Jedes Feld ist ein Kaestchen mit Rahmen, so ergeben sich die Trennlinien.
    function buildCellGrid()
        delete(get(pGrid, 'Children'));
        gridH = struct();
        numCells = max(numel(cfg.bmAddr), numel(cfg.pmAddr));
        for k = numel(cellNames) + 1:numCells
            cellNames(k) = string(sprintf('Zelle_%c', FIRST_CELL_LETTER + k - 1));
        end

        numRows   = size(GRID_ROWS, 1) + 1;              % + Kopfzeile
        rowHeight = 1 / numRows;
        colWidth  = (1 - GRID_LABEL_WIDTH) / max(numCells, 1);
        rowY      = @(r) 1 - r * rowHeight;              % r = 1: Kopfzeile

        gridBox(pGrid, 'text', '', [0 rowY(1) GRID_LABEL_WIDTH rowHeight], COLOR_HEADER, 'bold');
        for k = 1:numCells
            gridBox(pGrid, 'text', sprintf('Zelle %d', k), ...
                [GRID_LABEL_WIDTH + (k - 1) * colWidth, rowY(1), colWidth, rowHeight], COLOR_HEADER, 'bold');
        end

        for r = 1:size(GRID_ROWS, 1)
            key = GRID_ROWS{r, 1};
            y = rowY(r + 1);
            if key(1) == '#'                             % Abschnitt BM / PM ueber die ganze Breite
                gridBox(pGrid, 'text', GRID_ROWS{r, 2}, [0 y 1 rowHeight], COLOR_SECTION, 'bold');
                continue;
            end
            gridBox(pGrid, 'label', GRID_ROWS{r, 2}, [0 y GRID_LABEL_WIDTH rowHeight], COLOR_LABEL, 'normal');
            h = gobjects(1, numCells);
            for k = 1:numCells
                pos = [GRID_LABEL_WIDTH + (k - 1) * colWidth, y, colWidth, rowHeight];
                if strcmp(key, 'name')
                    h(k) = uicontrol(pGrid, 'Style', 'edit', 'String', char(cellNames(k)), ...
                        'Units', 'normalized', 'Position', pos, 'FontSize', GRID_FONT_SIZE, ...
                        'TooltipString', 'Name der Zelle (für Log und Ergebnisdatei)', ...
                        'Callback', @(src, ~) onCellNameEdited(k, src));
                else
                    h(k) = gridBox(pGrid, 'value', '-', pos, COLOR_VALUE, 'normal');
                end
            end
            gridH.(key) = h;
        end

        % Zellen ohne BM bzw. ohne PM kennzeichnen, Adressen eintragen
        for k = 1:numCells
            if k <= numel(cfg.bmAddr)
                setGrid('bmAddr', k, cfg.bmAddr{k});
            else
                setGrid({'bmAddr', 'bmState', 'u', 'i', 'tTab', 'eis', 'conz'}, k, 'kein BM', COLOR_NO_BOARD);
            end
            if k <= numel(cfg.pmAddr)
                setGrid('pmAddr', k, cfg.pmAddr{k});
                setGrid('src', k, sourceText(cfg.pmSource(k)));
            else
                setGrid({'pmAddr', 'pmState', 'tSet', 'tAct', 'tPt', 'iPm', 'duty', 'ilim', 'src'}, k, 'kein PM', COLOR_NO_BOARD);
            end
        end
    end

    % ein Feld der Uebersicht: 'text' = Ueberschrift, 'label' = Beschriftung, 'value' = Messwert
    function h = gridBox(parent, kind, str, pos, color, weight)
        align = 'center';
        if strcmp(kind, 'label')
            align = 'left';
        end
        if strcmp(kind, 'text')
            h = uicontrol(parent, 'Style', 'text', 'String', str, 'Units', 'normalized', 'Position', pos, ...
                          'BackgroundColor', color, 'FontWeight', weight, 'FontSize', GRID_FONT_SIZE, ...
                          'HorizontalAlignment', align);
        else
            % 'edit' mit Enable 'inactive': nicht editierbar, aber mit Rahmen -> Trennlinien
            h = uicontrol(parent, 'Style', 'edit', 'String', str, 'Enable', 'inactive', 'Units', 'normalized', ...
                          'Position', pos, 'BackgroundColor', color, 'FontWeight', weight, ...
                          'FontSize', GRID_FONT_SIZE, 'HorizontalAlignment', align);
        end
    end

    % setzt Text (und optional Hintergrundfarbe) eines oder mehrerer Felder von Zelle k
    function setGrid(keys, k, str, color)
        if ischar(keys)
            keys = {keys};
        end
        for n = 1:numel(keys)
            if ~isfield(gridH, keys{n}) || k > numel(gridH.(keys{n}))
                continue;
            end
            h = gridH.(keys{n})(k);
            set(h, 'String', str, 'TooltipString', str);      % Tooltip zeigt auch lange Texte ganz
            if nargin >= 4
                set(h, 'BackgroundColor', color);
            end
        end
    end

    function onCellNameEdited(k, src)
        cellNames(k) = string(strtrim(get(src, 'String')));
        updateSelectionLists();
    end

    % Auswahllisten (Messung, Zelle der Temperaturregelung, Temperaturquelle)
    function updateSelectionLists()
        nBm = numel(cfg.bmAddr);
        nPm = numel(cfg.pmAddr);
        targets = [arrayfun(@(k) cellLabel(k), 1:nBm, 'UniformOutput', false), ...
                   {'Stack', 'alle Zellen', 'alle Zellen + Stack'}];
        set(hTarget, 'String', targets, 'Value', min(get(hTarget, 'Value'), numel(targets)));
        pmList = [{'alle Zellen'}, arrayfun(@(k) cellLabel(k), 1:nPm, 'UniformOutput', false)];
        set(hPmSelect, 'String', pmList, 'Value', min(get(hPmSelect, 'Value'), numel(pmList)));
        srcList = [{'PT1000 am PM'}, arrayfun(@(k) sprintf('Tab-Sensor %s', cellLabel(k)), 1:nBm, 'UniformOutput', false)];
        set(hPmSource, 'String', srcList, 'Value', min(get(hPmSource, 'Value'), numel(srcList)));
    end

    function s = cellLabel(k)
        s = sprintf('Zelle %d', k);
        if k <= numel(cellNames) && strlength(cellNames(k)) > 0
            s = sprintf('Zelle %d (%s)', k, cellNames(k));
        end
    end

    %% =========================================================================
    %  Boardliste
    %  =========================================================================
    function applyBoardList()
        bm = addressList(get(hBmAddr, 'String'));
        pm = addressList(get(hPmAddr, 'String'));
        if isempty(bm)
            logMsg('mindestens ein BM angeben');
            return;
        end
        sendCommand(['CFGBM;' strjoin(bm, ';')]);
        if isempty(pm)
            sendCommand('CFGPM');
        else
            sendCommand(['CFGPM;' strjoin(pm, ';')]);
        end
        sendCommand('CFG?');
        logMsg('Liste übernommen - mit "Im MM speichern" dauerhaft ablegen');
    end

    function list = addressList(text)
        parts = strtrim(split(string(text), {',', ';', ' '}));
        parts = parts(strlength(parts) > 0);
        list = cellstr(parts).';
    end

    %% =========================================================================
    %  Temperaturregelung
    %  =========================================================================
    function k = selectedPm()
        k = get(hPmSelect, 'Value') - 1;      % 0 = alle Zellen (alle PMs)
    end

    function pmCommand(cmd)
        sendCommand(sprintf('%s;%d', cmd, selectedPm()));
    end

    function pmSetpoint()
        t = str2double(strrep(get(hTset, 'String'), ',', '.'));
        if isnan(t)
            logMsg('Sollwert ist keine Zahl');
            return;
        end
        sendCommand(sprintf('PMSET;%d;%d', selectedPm(), round(t * CENTI)));
    end

    function pmCurrentLimit()
        i = str2double(strrep(get(hIlim, 'String'), ',', '.'));
        if isnan(i)
            logMsg('Stromgrenze ist keine Zahl');
            return;
        end
        sendCommand(sprintf('PMILIM;%d;%d', selectedPm(), round(i * MILLI)));
    end

    function pmSourceSet()
        k = selectedPm();
        if k == 0
            logMsg('Temperaturquelle bitte für eine einzelne Zelle setzen');
            return;
        end
        sendCommand(sprintf('PMSRC;%d;%d', k, get(hPmSource, 'Value') - 1));
        sendCommand('CFG?');
    end

    %% =========================================================================
    %  EIS
    %  =========================================================================
    function chooseFolder()
        d = uigetdir(get(hFolder, 'String'));
        if ischar(d)
            set(hFolder, 'String', d);
        end
    end

    function startEis()
        n = numel(cfg.bmAddr);
        sel = get(hTarget, 'Value');
        if sel <= n
            target = sprintf('C%d', sel);
        elseif sel == n + 1
            target = 'S';
        elseif sel == n + 2
            target = 'ALL';
        else
            target = 'ALLS';
        end
        fStart = get(hFstart, 'Value') - 1;
        fStop  = get(hFstop, 'Value') - 1;
        if fStop < fStart
            logMsg('Stopp-Frequenz muss unter der Start-Frequenz liegen (Stopp-Index >= Start-Index)');
            return;
        end
        jobInfo = struct();
        jobInfo.folder    = get(hFolder, 'String');
        jobInfo.baseName  = regexprep(get(hFilename, 'String'), '[^\w\-]', '_');
        jobInfo.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));
        jobInfo.comment   = get(hComment, 'String');
        jobInfo.cellNames = cellNames;
        jobInfo.settings  = struct('fStart', fStart, 'fStop', fStop, ...
                                   'amplitude', AMPLITUDE_TEXT{get(hAmp, 'Value')}, ...
                                   'waveform', WAVEFORM_TEXT{get(hWave, 'Value')}, ...
                                   'averages', get(hAvg, 'Value'));
        meas = containers.Map();
        cla(ax);
        plotHandles = containers.Map();
        sendCommand(sprintf('EIS;%s;%d;%d;%d;%d;%d', target, fStart, fStop, ...
                            get(hAmp, 'Value') - 1, get(hWave, 'Value') - 1, get(hAvg, 'Value')));
    end

    function onEisBegin(f)
        % EISBEGIN;target;fstart;fstop;amp;wave;avg
        t = char(f(2));
        m.target = t;
        m.cells  = zeros(0, 3);          % [BM, U mV, T degC]
        m.data   = zeros(0, 4);          % [Index, f Hz, Re uOhm, Im uOhm]
        m.pm     = pmLast;
        m.start  = datetime('now');
        meas(t) = m;
        set(hStart, 'Enable', 'off');
        set(hAbort, 'Enable', 'on');
        set(hProgress, 'String', sprintf('%s: Messung gestartet', targetText(t)));
        logMsg(sprintf('EIS %s gestartet', targetText(t)));
    end

    function onEisCell(f)
        % EISCELL;target;bm;u_mV;t_cdegC
        t = char(f(2));
        m = meas(t);
        m.cells(end + 1, :) = [str2double(f(3)), str2double(f(4)), str2double(f(5)) / CENTI];
        meas(t) = m;
    end

    function onEisProgress(f)
        % PROG;target;index
        t = char(f(2));
        idx = str2double(f(3));
        if idx ~= PROGRESS_IDLE
            s = jobInfo.settings;
            set(hProgress, 'String', sprintf('%s: Frequenz %d von %d (%.2f Hz)', targetText(t), ...
                idx - s.fStart + 1, s.fStop - s.fStart + 1, FREQ_HZ(idx + 1)));
        end
    end

    function onEisResult(f)
        % RES;target;index;f_cHz;re_uOhm;im_uOhm
        t = char(f(2));
        m = meas(t);
        m.data(end + 1, :) = [str2double(f(3)), str2double(f(4)) / CENTI, str2double(f(5)), str2double(f(6))];
        meas(t) = m;
        re = m.data(:, 3) * MICRO_TO_MILLI;
        im = m.data(:, 4) * MICRO_TO_MILLI;
        if isKey(plotHandles, t) && isvalid(plotHandles(t))
            set(plotHandles(t), 'XData', re, 'YData', -im);
        else
            plotHandles(t) = plot(ax, re, -im, '-o', 'DisplayName', targetText(t));
            legend(ax, 'show', 'Location', 'best');
        end
    end

    function onEisEnd(f)
        % EISEND;target;OK   |   EISEND;target;ERR;REASON[;BM_ERRn]
        t = char(f(2));
        if f(3) == "OK"
            file = EIS_Textdatei_schreiben(meas(t), jobInfo, targetText(t));
            logMsg(sprintf('EIS %s fertig: %s', targetText(t), file));
        else
            reason = char(f(4));
            if isKey(EIS_REASON_TEXT, reason)
                reason = [reason ' - ' EIS_REASON_TEXT(reason)];
            end
            if numel(f) >= 5
                bmErr = str2double(extractAfter(f(5), "BM_ERR"));
                reason = sprintf('%s (BM-Fehler %d: %s)', reason, bmErr, errorText(BM_ERROR_TEXT, bmErr));
            end
            logMsg(sprintf('EIS %s fehlgeschlagen: %s', targetText(t), reason));
        end
    end

    function onEisDone(f)
        % EISDONE;ok;total
        set(hStart, 'Enable', 'on');
        set(hAbort, 'Enable', 'off');
        set(hProgress, 'String', sprintf('Messauftrag beendet: %s von %s erfolgreich', f(2), f(3)));
        logMsg(get(hProgress, 'String'));
    end

    %% =========================================================================
    %  Hilfsfunktionen
    %  =========================================================================
    function s = targetText(t)
        if t(1) == 'S'
            s = 'Stack';
        else
            s = cellLabel(str2double(t(2:end)));
        end
    end

    function [s, color] = bmState(online, status, err, progress)
        if ~online
            s = 'offline';                       color = COLOR_STATE_OFFLINE;
        elseif bitand(status, BM_ST_EIS_BUSY)
            s = sprintf('EIS läuft (%.2f Hz)', FREQ_HZ(min(progress, NUM_FREQ - 1) + 1));
            color = COLOR_STATE_ACTIVE;
        elseif bitand(status, BM_ST_ERROR)
            s = ['Fehler: ' errorText(BM_ERROR_TEXT, err)];  color = COLOR_STATE_ERROR;
        else
            s = 'bereit';                        color = COLOR_STATE_OK;
        end
    end

    function [s, color] = pmState(online, status, err)
        if ~online
            s = 'offline';                       color = COLOR_STATE_OFFLINE;
        elseif bitand(status, PM_ST_ERROR)
            s = ['Fehler: ' errorText(PM_ERROR_TEXT, err)];  color = COLOR_STATE_ERROR;
        elseif bitand(status, PM_ST_RUNNING)
            color = COLOR_STATE_ACTIVE;
            if bitand(status, PM_ST_COOLING)
                s = 'regelt (kühlt)';
            else
                s = 'regelt (heizt)';
            end
        elseif ~bitand(status, PM_ST_TEMP_VALID)
            s = 'Temperatur ungültig';           color = COLOR_STATE_ERROR;
        else
            s = 'aus';                           color = COLOR_STATE_OK;
        end
    end

    function s = sourceText(src)
        if src == 0
            s = 'PT1000 am PM';
        else
            s = sprintf('Tab-Sensor Zelle %d', src);
        end
    end

    function s = errorText(table, code)
        if code >= 0 && code < numel(table)
            s = table{code + 1};
        else
            s = sprintf('Code %d', code);
        end
    end

    function s = onOffText(b)
        if b, s = 'ein'; else, s = 'aus'; end
    end

    function s = onOff(b)
        if b, s = 'on'; else, s = 'off'; end
    end

    function hz = frequencyTable()
        % gleiche Rechnung wie EIS_FreqCentiHz() im BM
        idx  = 0:NUM_FREQ - 1;
        fund = mod(idx, FREQ_STEPS_PER_OCTAVE);
        div  = floor(idx / FREQ_STEPS_PER_OCTAVE);
        centi = floor((floor(floor(2 * FREQ_STEPS_PER_OCTAVE * F_MAX_CENTI_HZ ./ (FREQ_STEPS_PER_OCTAVE + fund)) ./ 2 .^ div) + 1) / 2);
        hz = centi / CENTI;
    end

    function logMsg(msg)
        if ~isvalid(fig)
            return;
        end
        old = get(hLog, 'String');
        if ischar(old)
            old = cellstr(old);
        end
        lines = [old; {sprintf('[%s] %s', char(datetime('now', 'Format', 'HH:mm:ss')), msg)}];
        set(hLog, 'String', lines, 'Value', numel(lines));
        drawnow limitrate;
    end
end
