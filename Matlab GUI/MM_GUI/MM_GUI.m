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
%   - Betriebsart (Umschalter oben rechts im Verbindungsfeld):
%       Manuell   : Temperaturregelung und EIS-Messung von Hand (wie bisher)
%       Automatik : Temperaturprofil je Zelle; sobald alle Zellen ihre Solltemperatur
%                   lange genug halten (Standard: Abweichung < 0,5 K fuer 5 min), laeuft die
%                   EIS-Messung mit den Einstellungen des EIS-Panels, danach folgt der naechste
%                   Profilschritt. Nach dem letzten Schritt und bei Abbruch werden die Zellen
%                   auf 25 degC temperiert, erst dann wird die Temperaturregelung ausgeschaltet.
%                   Profil grafisch (Tabelle/Diagramm) oder als Text einstellbar. Welche Zellen
%                   temperiert werden, folgt aus "Messung" im EIS-Panel (Einzelzelle -> nur
%                   diese Zelle; Stack / alle Zellen (+ Stack) -> alle Zellen).
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
    MM_FIELD_NOADDR_BM   = 4;          % MM;busy;i2cErr;<BM auf 0x10>;<PM auf 0x20>
    MM_FIELD_NOADDR_PM   = 5;
    DEFAULT_MEAS_TIME    = 2;          % 50 ms (Listeneintrag) = Bedingung der Datenblatt-Genauigkeit
    DEFAULT_AMPLITUDE    = 6;          % 500 mA (Listeneintrag); unter 200 mA misst der TLE9010 Re ~1.7 % zu hoch
    DEFAULT_TSET_DEGC    = 25;
    DEFAULT_ILIM_A       = 3;          % = Standard und Maximum des PM
    PROGRESS_IDLE        = 255;
    FIRST_CELL_LETTER    = 'A';        % Standard-Zellnamen Zelle_A, Zelle_B, ...
    DEFAULT_DATA_FOLDER  = 'C:\Users\trims\TUM\Masterarbeit\Data\EIS-Messdaten';   % Zielordner der Messdaten
    PROFILE_FOLDER       = fileparts(mfilename('fullpath'));   % Temperaturprofile: Ordner der GUI (MM_GUI.m)
    % Temperaturquelle eines PM: nur der eigene PT1000 oder der Tab-Sensor DERSELBEN Zelle
    % (PM k <-> BM k). Mit dem Sensor einer anderen Zelle saehe der Regler eine falsche
    % Temperatur und koennte dauerhaft heizen oder kuehlen.
    SOURCE_TEXT          = {'PT1000 am PM', 'Tab-Sensor der eigenen Zelle'};
    SOURCE_ITEM_PT1000   = 1;          % Listeneintrag
    SOURCE_ITEM_OWN_TAB  = 2;
    PM_SOURCE_PT1000     = 0;          % Code im Protokoll (PMSRC / CFG;SRC); Tab-Sensor = Nummer der Zelle

    % Automatik (Temperaturprofil + EIS je Temperaturschritt)
    MODE_MANUAL_TEXT          = 'Manuell';
    MODE_AUTO_TEXT            = 'Automatik';
    AUTO_TOL_DEFAULT_K        = 0.5;    % zulaessige Abweichung von der Solltemperatur
    AUTO_HOLD_DEFAULT_MIN     = 5;      % so lange muessen alle Zellen ohne Unterbrechung in der Toleranz liegen
    AUTO_TICK_S               = 1;      % Pruefintervall der Ablaufsteuerung (= Statusabfrage)
    AUTO_DATA_MAX_AGE_S       = 5;      % aeltere Statuswerte gelten als ungueltig (Board antwortet nicht)
    AUTO_EIS_START_TIMEOUT_S  = 15;     % EIS-Befehl ohne EISBEGIN- oder ERR-Antwort -> Messfehler
    AUTO_SETPOINT_MATCH_K     = 0.01;   % PM meldet den gesendeten Sollwert zurueck (Aufloesung 0,01 K)
    AUTO_CRITERION_TEXT       = {'T Tab (BM-Sensor)', 'T Ist (PM-Regelgröße)'};
    AUTO_CRITERION_TAB        = 1;      % Listeneintrag: Temperatur am Zellableiter (BM)
    AUTO_CRITERION_PM         = 2;      % Listeneintrag: Istwert der PM-Regelung
    AUTO_LOG_FILE             = 'Ablauf.txt';          % im Ordner des Automatiklaufs
    AUTO_PROFILE_FILE         = 'Temperaturprofil.txt';
    AUTO_ANSWER_REPEAT        = 'Wiederholen';
    AUTO_ANSWER_ABORT         = 'Automatik abbrechen';
    AUTO_ANSWER_OFF_NOW       = 'Sofort ausschalten';
    AUTO_END_TEMP_DEGC        = 25;     % nach dem letzten Schritt / bei Abbruch: erst hierhin temperieren, dann Regelung aus
    SECONDS_PER_MINUTE        = 60;
    PROFILE_T_MIN_DEGC        = 0;      % Sollwertbereich des PM (pm_regs.h: 0..5000 cdegC)
    PROFILE_T_MAX_DEGC        = 50;
    PROFILE_DRAG_STEP_K       = 0.5;    % Raster beim Ziehen eines Punkts im Profildiagramm
    PROFILE_SUMMARY_MAX_STEPS = 6;      % so viele Temperaturen zeigt die Kurzuebersicht je Zelle
    PROFILE_FIG_SIZE_PX       = [1000 640];
    PROFILE_LINE_WIDTH        = 1.5;
    PROFILE_MARKER_SIZE       = 8;
    PROFILE_SEL_MARK          = ' ◄';   % Zusatz am Zeilennamen des markierten Schritts
    PROFILE_INSERT_BEFORE     = -1;     % Richtung fuer profileInsertStep / profileMoveStep
    PROFILE_INSERT_AFTER      = 1;
    COLOR_TEXT_ERROR          = [0.75 0 0];
    COLOR_TEXT_OK             = [0 0.45 0];

    % letzte Statuswerte je Board (time = Empfangszeitpunkt, fuer die Automatik)
    BM_LAST_EMPTY = struct('u', {}, 't', {}, 'tValid', {}, 'online', {}, 'time', {});
    PM_LAST_EMPTY = struct('tAct', {}, 'tPt', {}, 'tSet', {}, 'online', {}, 'error', {}, 'time', {});

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
        'stackRail', 'Stackmessung: an Rail';
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
                     'EIS-ADC uebersteuert', 'Ueberstrom an der Rail (CONNECT_Z aus)'};
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
    PLOT_FILE_TYPES = {'*.png', 'PNG-Bild (*.png)'; ...
                       '*.pdf', 'PDF, Vektorgrafik (*.pdf)'; ...
                       '*.fig', 'MATLAB-Figure (*.fig)'};
    FREQ_LABEL_FONT_SIZE  = 8;             % Frequenzbeschriftung im Nyquist-Diagramm
    FREQ_LABEL_TAG        = 'FreqLabel';
    % Datentipp mit Frequenz: als CreateFcn-Text an jeder Messkurve, damit er auch in einer
    % gespeicherten MATLAB-Figure (.fig) beim Oeffnen wieder gesetzt wird. Die Frequenzen
    % stehen in UserData der Kurve (DataTipTemplate ab R2019a).
    FREQ_TIP_CREATE_FCN = ['try, h = gcbo; h.DataTipTemplate.DataTipRows = [' ...
                           'dataTipTextRow(''Re(Z) [m\Omega]'', ''XData''), ' ...
                           'dataTipTextRow(''-Im(Z) [m\Omega]'', ''YData''), ' ...
                           'dataTipTextRow(''f [Hz]'', h.UserData(:).'')]; catch, end'];
    HZ_PER_KHZ            = 1000;
    PLOT_EXPORT_DPI       = 300;           % Aufloesung des PNG
    PLOT_EXPORT_SIZE_CM   = [16 12];       % Breite x Hoehe der gespeicherten Grafik
    PLOT_EXPORT_AXES_POS  = [0.13 0.12 0.82 0.80];   % Achsen in der Export-Figure (normiert)
    MEAS_TIME_TEXT = {'25 ms', '50 ms', '100 ms', '200 ms', '400 ms', '800 ms', '1,6 s', '3,2 s'};  % Index 0..7 wie im BM
    FREQ_HZ        = frequencyTable();
    FREQ_TEXT      = arrayfun(@(k) sprintf('(%2d) %8.2f Hz', k - 1, FREQ_HZ(k)), 1:NUM_FREQ, ...
                              'UniformOutput', false);

    %% ---- Zustand (von allen verschachtelten Funktionen geteilt) -------------
    device     = [];              % serialport-Objekt
    tipWarned  = false;           % Hinweis 'Datentipp nicht verfuegbar' schon gezeigt
    noAddr     = [false false];   % BM / PM antwortet auf der Standardadresse 0x10 / 0x20
    statTimer  = [];
    cfg        = struct('bmAddr', {{}}, 'pmAddr', {{}}, 'pmSource', []);
    cellNames  = strings(1, 0);              % Zellnamen (in der Zellenuebersicht editierbar)
    gridH      = struct();                   % Handles der Zellenuebersicht: gridH.<Zeile>(Zelle)
    numCells   = 0;                          % Spalten der Zellenuebersicht
    stackSel   = true(1, 0);                 % Zelle k bei der Stackmessung an der Rail (Haken)
    bmLast     = BM_LAST_EMPTY;              % letzte Messwerte je BM (Datei, Automatik)
    pmLast     = PM_LAST_EMPTY;
    mmBusy     = false;                      % MM fuehrt gerade einen EIS-Auftrag aus
    autoProfile = zeros(0, 0);               % Temperaturprofil [degC]: Zeile = Schritt, Spalte = Zelle
    autoRun    = struct('state', 'IDLE', 'folder', '');   % laufende Automatik (Zustaende siehe autoTick)
    autoTimer  = [];
    profileEdit = struct('fig', []);         % Fenster des Profileditors
    meas       = containers.Map();           % laufende Messung je Ziel ('C1', 'S', ...)
    dataFolder = DEFAULT_DATA_FOLDER;
    if ~exist(dataFolder, 'dir')
        dataFolder = pwd;                    % anderer Rechner / Ordner fehlt: aktueller Ordner
    end
    jobInfo    = struct('folder', dataFolder, 'baseName', 'Messung', 'timestamp', '', 'comment', '', ...
                        'cellNames', strings(0, 1), 'settings', struct('fStart', DEFAULT_START_INDEX, ...
                        'fStop', DEFAULT_STOP_INDEX, 'amplitude', '', 'waveform', '', 'averages', 1, 'measTime', ''));  % laufender Auftrag
    plotHandles = containers.Map();

    %% ---- Fenster ---------------------------------------------------------------
    figs = findall(0, 'Type', 'figure', 'Tag', 'MM_GUI');
    delete(figs);
    fig = figure('Name', 'Batteriespeicher-Testsystem (MM)', 'Tag', 'MM_GUI', ...
                 'NumberTitle', 'off', 'MenuBar', 'none', 'Units', 'pixels', ...
                 'Position', [40 40 1320 880], 'CloseRequestFcn', @onClose);
    try
        set(fig, 'WindowState', 'maximized');              % ab R2018a
    catch
        set(fig, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);   % aeltere Versionen
        set(fig, 'Units', 'pixels');
    end

    % Verbindung
    pConn = uipanel(fig, 'Title', 'Verbindung', 'Units', 'normalized', 'Position', [0.005 0.935 0.49 0.06]);
    hCom  = uicontrol(pConn, 'Style', 'popupmenu', 'String', {'-'}, 'Units', 'normalized', 'Position', [0.01 0.15 0.18 0.7]);
    uicontrol(pConn, 'Style', 'pushbutton', 'String', 'Ports suchen', 'Units', 'normalized', ...
              'Position', [0.20 0.1 0.15 0.8], 'Callback', @(~, ~) refreshPorts());
    hConnect = uicontrol(pConn, 'Style', 'pushbutton', 'String', 'Verbinden', 'Units', 'normalized', ...
              'Position', [0.36 0.1 0.15 0.8], 'Callback', @(~, ~) toggleConnection());
    hConnState = uicontrol(pConn, 'Style', 'text', 'String', 'nicht verbunden', 'Units', 'normalized', ...
              'Position', [0.53 0.1 0.20 0.65], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
    % Betriebsart: Manuell (Bedienung von Hand) / Automatik (Temperaturprofil + EIS)
    hMode = uibuttongroup(pConn, 'BorderType', 'line', 'Units', 'normalized', 'Position', [0.74 0.05 0.255 0.9], ...
              'SelectionChangedFcn', @(~, ~) onModeChanged());
    hModeManual = uicontrol(hMode, 'Style', 'radiobutton', 'String', MODE_MANUAL_TEXT, 'Units', 'normalized', ...
              'Position', [0.04 0.05 0.44 0.9], 'TooltipString', 'Temperaturregelung und EIS-Messung von Hand');
    hModeAuto   = uicontrol(hMode, 'Style', 'radiobutton', 'String', MODE_AUTO_TEXT, 'Units', 'normalized', ...
              'Position', [0.50 0.05 0.49 0.9], 'FontWeight', 'bold', ...
              'TooltipString', 'Temperaturprofil abfahren, bei stabiler Temperatur automatisch EIS messen');
    set(hMode, 'SelectedObject', hModeManual);

    % Zellenuebersicht: je Zelle eine Spalte, darunter BM und PM der Zelle
    pBoards = uipanel(fig, 'Title', 'Zellen (BM + PM)', 'Units', 'normalized', 'Position', [0.005 0.47 0.49 0.46]);
    pGrid = uipanel(pBoards, 'BorderType', 'none', 'Units', 'normalized', 'Position', [0.005 0.10 0.99 0.895]);
    uicontrol(pBoards, 'Style', 'text', 'String', 'BM-Adr.:', 'Units', 'normalized', 'Position', [0.01 0.015 0.08 0.06], 'HorizontalAlignment', 'left');
    hBmAddr = uicontrol(pBoards, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.09 0.015 0.17 0.07], ...
        'TooltipString', 'z. B. 0x11, 0x12 (Reihenfolge = Zelle 1, Zelle 2, ...; 0x10 = BM ohne vergebene Adresse)');
    uicontrol(pBoards, 'Style', 'text', 'String', 'PM-Adr.:', 'Units', 'normalized', 'Position', [0.27 0.015 0.08 0.06], 'HorizontalAlignment', 'left');
    hPmAddr = uicontrol(pBoards, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.35 0.015 0.17 0.07], ...
        'TooltipString', 'z. B. 0x21, 0x22 (Reihenfolge = Zelle 1, Zelle 2, ...; 0x20 = PM ohne vergebene Adresse)');
    hListApply = uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Liste übernehmen', 'Units', 'normalized', ...
        'Position', [0.53 0.01 0.16 0.08], 'Callback', @(~, ~) applyBoardList());
    hListSave = uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Im MM speichern', 'Units', 'normalized', ...
        'Position', [0.70 0.01 0.15 0.08], 'Callback', @(~, ~) sendCommand('SAVE'));
    hScan = uicontrol(pBoards, 'Style', 'pushbutton', 'String', 'Bus-Scan', 'Units', 'normalized', ...
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
    hPmSource = uicontrol(pTemp, 'Style', 'popupmenu', 'String', SOURCE_TEXT, 'Value', SOURCE_ITEM_PT1000, ...
        'Units', 'normalized', 'Position', [0.41 0.15 0.26 0.28], 'TooltipString', ...
        sprintf(['Regelgröße des PM: eigener PT1000 oder Tab-Sensor derselben Zelle (BM mit gleicher Nummer).\n' ...
                 'Bei "alle Zellen" bekommt jedes PM den Sensor seiner eigenen Zelle.']));
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Quelle setzen', 'Units', 'normalized', 'Position', [0.68 0.15 0.14 0.28], ...
        'Callback', @(~, ~) pmSourceSet());
    uicontrol(pTemp, 'Style', 'pushbutton', 'String', 'Neu kalibrieren', 'Units', 'normalized', 'Position', [0.83 0.15 0.16 0.28], ...
        'Callback', @(~, ~) pmCommand('PMRECAL'));

    % Automatik: liegt an derselben Stelle wie die Temperaturregelung (nur eines ist sichtbar)
    pAuto = uipanel(fig, 'Title', 'Automatik: Temperaturprofil + EIS-Messung', 'Units', 'normalized', ...
        'Position', get(pTemp, 'Position'), 'Visible', 'off');
    uicontrol(pAuto, 'Style', 'pushbutton', 'String', 'Profil bearbeiten ...', 'Units', 'normalized', ...
        'Position', [0.01 0.68 0.18 0.26], 'Callback', @(~, ~) openProfileEditor());
    hAutoSummary = uicontrol(pAuto, 'Style', 'text', 'String', 'kein Profil', 'Units', 'normalized', ...
        'Position', [0.20 0.68 0.79 0.22], 'HorizontalAlignment', 'left');
    uicontrol(pAuto, 'Style', 'text', 'String', 'Toleranz [K]:', 'Units', 'normalized', 'Position', [0.01 0.38 0.11 0.22], 'HorizontalAlignment', 'left');
    hAutoTol = uicontrol(pAuto, 'Style', 'edit', 'String', num2str(AUTO_TOL_DEFAULT_K), 'Units', 'normalized', ...
        'Position', [0.12 0.39 0.07 0.25], 'TooltipString', 'zulässige Abweichung |T - T Soll| jeder Zelle');
    uicontrol(pAuto, 'Style', 'text', 'String', 'Haltezeit [min]:', 'Units', 'normalized', 'Position', [0.21 0.38 0.13 0.22], 'HorizontalAlignment', 'left');
    hAutoHold = uicontrol(pAuto, 'Style', 'edit', 'String', num2str(AUTO_HOLD_DEFAULT_MIN), 'Units', 'normalized', ...
        'Position', [0.34 0.39 0.07 0.25], 'TooltipString', 'so lange müssen alle Zellen ohne Unterbrechung innerhalb der Toleranz liegen');
    uicontrol(pAuto, 'Style', 'text', 'String', 'Kriterium:', 'Units', 'normalized', 'Position', [0.43 0.38 0.09 0.22], 'HorizontalAlignment', 'left');
    hAutoCrit = uicontrol(pAuto, 'Style', 'popupmenu', 'String', AUTO_CRITERION_TEXT, 'Value', AUTO_CRITERION_TAB, ...
        'Units', 'normalized', 'Position', [0.52 0.39 0.22 0.25], 'TooltipString', ...
        sprintf(['Welche Temperatur mit dem Sollwert verglichen wird:\n' ...
                 'T Tab = Sensor am Zellableiter (BM), T Ist = Regelgröße des PM']));
    hAutoHint = uicontrol(pAuto, 'Style', 'text', 'String', 'Temperiert: -', 'Units', 'normalized', ...
        'Position', [0.76 0.38 0.23 0.22], 'HorizontalAlignment', 'left', 'ForegroundColor', [0.4 0.4 0.4], ...
        'TooltipString', sprintf(['Welche Zellen temperiert werden, folgt aus "Messung" im EIS-Panel:\n' ...
                                  'eine Zelle -> nur diese Zelle (die anderen PMs bleiben unverändert),\n' ...
                                  'Stack / alle Zellen / alle Zellen + Stack -> alle Zellen']));
    hAutoStart = uicontrol(pAuto, 'Style', 'pushbutton', 'String', 'Automatik starten', 'Units', 'normalized', ...
        'Position', [0.01 0.06 0.19 0.27], 'FontWeight', 'bold', 'Callback', @(~, ~) startAuto());
    hAutoStop = uicontrol(pAuto, 'Style', 'pushbutton', 'String', 'Automatik abbrechen', 'Units', 'normalized', ...
        'Position', [0.21 0.06 0.19 0.27], 'Enable', 'off', 'Callback', @(~, ~) onAutoStopPressed());
    hAutoStatus = uicontrol(pAuto, 'Style', 'text', 'String', 'Automatik bereit', 'Units', 'normalized', ...
        'Position', [0.41 0.02 0.58 0.32], 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    % EIS
    pEis = uipanel(fig, 'Title', 'EIS-Messung (BM)', 'Units', 'normalized', 'Position', [0.005 0.005 0.49 0.29]);
    labelsLeft = {'Messung:', 'Start-Frequenz:', 'Stopp-Frequenz:', 'Amplitude:', 'Signalform:', 'Mittelung:'};
    LABEL_ROW_STEP = 0.13;
    for row = 1:numel(labelsLeft)
        uicontrol(pEis, 'Style', 'text', 'String', labelsLeft{row}, 'Units', 'normalized', ...
            'Position', [0.01 0.86 - (row - 1) * LABEL_ROW_STEP 0.15 0.1], 'HorizontalAlignment', 'left');
    end
    hTarget = uicontrol(pEis, 'Style', 'popupmenu', 'String', {'Zelle 1'}, 'Units', 'normalized', 'Position', [0.16 0.86 0.26 0.11], ...
        'Callback', @(~, ~) updateAutoHint());          % bestimmt auch, welche Zellen die Automatik temperiert
    hFstart = uicontrol(pEis, 'Style', 'popupmenu', 'String', FREQ_TEXT, 'Value', DEFAULT_START_INDEX + 1, 'Units', 'normalized', 'Position', [0.16 0.73 0.26 0.11]);
    hFstop  = uicontrol(pEis, 'Style', 'popupmenu', 'String', FREQ_TEXT, 'Value', DEFAULT_STOP_INDEX + 1, 'Units', 'normalized', 'Position', [0.16 0.60 0.26 0.11]);
    hAmp    = uicontrol(pEis, 'Style', 'popupmenu', 'String', AMPLITUDE_TEXT, 'Value', DEFAULT_AMPLITUDE, 'Units', 'normalized', 'Position', [0.16 0.47 0.26 0.11]);
    hWave   = uicontrol(pEis, 'Style', 'popupmenu', 'String', WAVEFORM_TEXT, 'Units', 'normalized', 'Position', [0.16 0.34 0.26 0.11]);
    hAvg    = uicontrol(pEis, 'Style', 'popupmenu', 'String', arrayfun(@num2str, 1:MAX_AVERAGES, 'UniformOutput', false), ...
                        'Units', 'normalized', 'Position', [0.16 0.21 0.26 0.11]);
    labelsRight = {'Zielordner:', 'Dateiname:', 'Kommentar:', 'Messdauer:'};
    for row = 1:numel(labelsRight)
        uicontrol(pEis, 'Style', 'text', 'String', labelsRight{row}, 'Units', 'normalized', ...
            'Position', [0.45 0.86 - (row - 1) * LABEL_ROW_STEP 0.11 0.1], 'HorizontalAlignment', 'left');
    end
    hFolder   = uicontrol(pEis, 'Style', 'edit', 'String', dataFolder, 'Units', 'normalized', 'Position', [0.56 0.87 0.36 0.1]);
    hFolderBtn = uicontrol(pEis, 'Style', 'pushbutton', 'String', '...', 'Units', 'normalized', 'Position', [0.93 0.87 0.06 0.1], ...
        'Callback', @(~, ~) chooseFolder());
    hFilename = uicontrol(pEis, 'Style', 'edit', 'String', 'Messung', 'Units', 'normalized', 'Position', [0.56 0.74 0.43 0.1]);
    hComment  = uicontrol(pEis, 'Style', 'edit', 'String', '', 'Units', 'normalized', 'Position', [0.56 0.61 0.43 0.1]);
    set(hFilename, 'TooltipString', 'Zellnamen: in der Zellenübersicht oben eintragen');
    hMeasTime = uicontrol(pEis, 'Style', 'popupmenu', 'String', MEAS_TIME_TEXT, 'Value', DEFAULT_MEAS_TIME, ...
        'Units', 'normalized', 'Position', [0.56 0.47 0.2 0.11], 'TooltipString', ...
        sprintf(['Messdauer je Einzelmessung und Frequenz.\nUnterhalb von ca. 60 Hz verlängert der TLE9010 ' ...
                 'die Messung automatisch auf mindestens 3 Perioden.\nDie Datenblatt-Genauigkeit gilt ab 50 ms.']));
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
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Diagramm speichern', 'Units', 'normalized', ...
        'Position', [0.885 0.962 0.105 0.032], 'TooltipString', 'Nyquist-Diagramm als PNG, PDF oder MATLAB-Figure speichern', ...
        'Callback', @(~, ~) saveNyquist());
    hLog = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', 'Position', [0.50 0.005 0.495 0.36], ...
        'FontName', 'Consolas', 'FontSize', 8, 'Max', 2, 'Min', 0, 'String', {});

    % waehrend der Automatik gesperrt: alles, was den laufenden Ablauf veraendern wuerde
    autoLockHandles = [hModeManual, hModeAuto, hBmAddr, hPmAddr, hListApply, hListSave, hScan, ...
                       hTarget, hFstart, hFstop, hAmp, hWave, hAvg, hMeasTime, hFolder, hFolderBtn, ...
                       hFilename, hComment, hAutoTol, hAutoHold, hAutoCrit];
    autoTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', AUTO_TICK_S, 'BusyMode', 'drop', ...
                      'TimerFcn', @(~, ~) autoTick());

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
            if ~confirmAutoStop('Trennen')
                return;
            end
            disconnect();
        end
    end

    % Laeuft die Automatik, nachfragen; bei Zustimmung wird sie abgebrochen (Temperaturregelung aus).
    % Rueckgabe false: Benutzer will die Automatik weiterlaufen lassen.
    function ok = confirmAutoStop(action)
        ok = true;
        if ~autoRunning()
            return;
        end
        answer = questdlg(sprintf(['Die Automatik läuft. Bei "%s" wird sie abgebrochen. Die PMs werden auf %g °C ' ...
                                   'gesetzt und regeln selbständig weiter - danach bitte von Hand ausschalten.'], ...
                                  action, AUTO_END_TEMP_DEGC), ...
                          'Automatik läuft', action, 'Weiterlaufen lassen', 'Weiterlaufen lassen');
        ok = strcmp(answer, action);
        if ok
            autoStop(sprintf('Abbruch durch "%s"', action), 'handover');
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
        if ~confirmAutoStop('Schließen')
            return;
        end
        disconnect();
        if ~isempty(autoTimer) && isvalid(autoTimer)
            stop(autoTimer);
            delete(autoTimer);
        end
        if ~isempty(profileEdit.fig) && isvalid(profileEdit.fig)
            delete(profileEdit.fig);
        end
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
                case "WARN",     onWarning(f);
                case "ERR",      onErrorReply(f, rxLine);
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
        bmLast(k).online = online;
        bmLast(k).tValid = online && bitand(status, BM_ST_TEMP_VALID) ~= 0;
        bmLast(k).time   = datetime('now');
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
        pmLast(k).online = online;
        pmLast(k).error  = bitand(status, PM_ST_ERROR) ~= 0;
        pmLast(k).time   = datetime('now');
        [stateText, stateColor] = pmState(online, status, err);
        setGrid('pmState', k, stateText, stateColor);
        setGrid('src', k, sourceText(src, k));
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

    function onErrorReply(f, rxLine)
        % ERR;<Befehl>;<Grund> - Ablehnung eines Befehls durch das MM
        logMsg(['<<< ' char(rxLine)]);
        if numel(f) >= 2 && f(2) == "EIS"
            reason = '';
            if numel(f) >= 3
                reason = char(f(3));
            end
            autoOnEisRejected(reason);
        end
    end

    function onWarning(f)
        % WARN;NOADDR;BM|PM;addr  - wird nur protokolliert; der Hinweisdialog kommt aus
        % der STAT-Zeile des MM (onMmStatus), damit er auch nach dem Verbinden erscheint
        logMsg(['<<< ' strjoin(cellstr(f), ';')]);
    end

    function onMmStatus(f)
        % MM;eisBusy;i2cErrors;bmOnDefaultAddr;pmOnDefaultAddr
        if numel(f) >= MM_FIELD_NOADDR_PM
            nowNoAddr = [str2double(f(MM_FIELD_NOADDR_BM)), str2double(f(MM_FIELD_NOADDR_PM))] == 1;
            types = {'BM', 'PM'};  defaults = {'0x10', '0x20'};  examples = {'0x11', '0x21'};
            for k = find(nowNoAddr & ~noAddr)
                msg = sprintf(['Ein %s antwortet auf der Standardadresse %s - ihm wurde noch keine Adresse ' ...
                               'vergeben. Zuerst über die Konsole des Boards eine eigene Adresse setzen ' ...
                               '(z. B. "addr %s"), erst dann kann es genutzt werden.'], ...
                               types{k}, defaults{k}, examples{k});
                logMsg(['Hinweis: ' msg]);
                warndlg(msg, 'Board ohne Adresse');
            end
            noAddr = nowNoAddr;
        end
        updateEisButtons(str2double(f(2)) == 1);
    end

    % Start/Abbrechen der manuellen EIS-Messung: nur im Modus Manuell bedienbar
    function updateEisButtons(busy)
        mmBusy = busy;
        manual = ~isAutoMode();
        set(hStart, 'Enable', onOff(manual && ~busy));
        set(hAbort, 'Enable', onOff(manual && busy));
    end

    function onConfig(f)
        % CFG;BM;n;addr...  CFG;PM;n;addr...  CFG;SRC;src...
        switch f(2)
            case "BM"
                cfg.bmAddr = cellstr(f(4:end));
                set(hBmAddr, 'String', strjoin(cfg.bmAddr, ', '));
                bmLast = BM_LAST_EMPTY;
            case "PM"
                cfg.pmAddr = cellstr(f(4:end));
                set(hPmAddr, 'String', strjoin(cfg.pmAddr, ', '));
                pmLast = PM_LAST_EMPTY;
            case "SRC"                                 % letzte Zeile der Antwort auf CFG?
                cfg.pmSource = str2double(f(3:end));
                buildCellGrid();
                updateSelectionLists();
                resizeProfile();
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
        stackSel(end + 1:numel(cfg.bmAddr)) = true;     % neue Zellen: standardmaessig verbunden
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
                elseif strcmp(key, 'stackRail') && k <= numel(cfg.bmAddr)
                    h(k) = uicontrol(pGrid, 'Style', 'checkbox', 'String', 'verbunden', 'Value', stackSel(k), ...
                        'Units', 'normalized', 'Position', pos, 'FontSize', GRID_FONT_SIZE, ...
                        'BackgroundColor', COLOR_VALUE, 'TooltipString', ...
                        sprintf(['Haken gesetzt: Zelle %d ist bei der Stackmessung mit der Rail verbunden ' ...
                                 '(CONNECT_Z = 1), sonst CONNECT_Z = 0'], k), ...
                        'Callback', @(src, ~) onStackSelEdited(k, src));
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
                setGrid({'bmAddr', 'bmState', 'u', 'i', 'tTab', 'eis', 'conz', 'stackRail'}, k, 'kein BM', COLOR_NO_BOARD);
            end
            if k <= numel(cfg.pmAddr)
                setGrid('pmAddr', k, cfg.pmAddr{k});
                setGrid('src', k, sourceText(cfg.pmSource(k), k));
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

    function onStackSelEdited(k, src)
        stackSel(k) = logical(get(src, 'Value'));
    end

    function onCellNameEdited(k, src)
        cellNames(k) = string(strtrim(get(src, 'String')));
        updateSelectionLists();
    end

    % Auswahllisten (Messung, Zelle der Temperaturregelung); die Temperaturquelle hat eine
    % feste Liste (SOURCE_TEXT), weil nur der Sensor der eigenen Zelle erlaubt ist
    function updateSelectionLists()
        nBm = numel(cfg.bmAddr);
        nPm = numel(cfg.pmAddr);
        targets = [arrayfun(@(k) cellLabel(k), 1:nBm, 'UniformOutput', false), ...
                   {'Stack', 'alle Zellen', 'alle Zellen + Stack'}];
        set(hTarget, 'String', targets, 'Value', min(get(hTarget, 'Value'), numel(targets)));
        pmList = [{'alle Zellen'}, arrayfun(@(k) cellLabel(k), 1:nPm, 'UniformOutput', false)];
        set(hPmSelect, 'String', pmList, 'Value', min(get(hPmSelect, 'Value'), numel(pmList)));
        updateAutoHint();
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
        % PM k regelt nach seinem PT1000 oder nach dem Tab-Sensor von BM k (derselben Zelle);
        % "alle Zellen": jedes PM bekommt die gewaehlte Quelle seiner eigenen Zelle
        k = selectedPm();
        cellsToSet = k;
        if k == 0
            cellsToSet = 1:numel(cfg.pmAddr);
        end
        useOwnTab = get(hPmSource, 'Value') == SOURCE_ITEM_OWN_TAB;
        for c = cellsToSet
            src = PM_SOURCE_PT1000;
            if useOwnTab
                if c > numel(cfg.bmAddr)
                    logMsg(sprintf('%s hat kein BM - Tab-Sensor nicht möglich, Quelle unverändert', cellLabel(c)));
                    continue;
                end
                src = c;                                % Tab-Sensor derselben Zelle
            end
            sendCommand(sprintf('PMSRC;%d;%d', c, src));
        end
        sendCommand('CFG?');
    end

    %% =========================================================================
    %  EIS
    %  =========================================================================
    function saveNyquist()
        % Speichert nur das Nyquist-Diagramm (ohne GUI-Elemente); das Format folgt aus dem
        % im Dialog gewaehlten Dateityp: PNG (Bild), PDF (Vektorgrafik) oder MATLAB-Figure
        if isempty(get(ax, 'Children'))
            logMsg('Kein Diagramm zum Speichern vorhanden');
            return;
        end
        defaultName = fullfile(get(hFolder, 'String'), sprintf('%s_%s_Nyquist.png', ...
            regexprep(get(hFilename, 'String'), '[^\w\-]', '_'), char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'))));
        [file, folder, typeIndex] = uiputfile(PLOT_FILE_TYPES, 'Nyquist-Diagramm speichern', defaultName);
        if isequal(file, 0)
            return;                                         % abgebrochen
        end
        [~, ~, ext] = fileparts(file);
        if isempty(ext)
            ext = extractAfter(PLOT_FILE_TYPES{typeIndex, 1}, '*');
            file = [file ext];
        end
        filePath = fullfile(folder, file);

        % Kopie des Diagramms (mit Legende) in einer unsichtbaren Figure
        tmp = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', ...
                     'Position', [0 0 PLOT_EXPORT_SIZE_CM]);
        cleanupFig = onCleanup(@() close(tmp));
        objs = ax;
        if ~isempty(ax.Legend)
            objs = [ax.Legend, ax];                         % Legende nur zusammen mit ihren Achsen kopierbar
        end
        copies = copyobj(objs, tmp);
        set(copies(end), 'Units', 'normalized', 'Position', PLOT_EXPORT_AXES_POS);
        curves = findobj(copies(end), 'Type', 'line');
        for c = 1:numel(curves)                             % copyobj uebernimmt den Datentipp nicht
            if numel(curves(c).UserData) == numel(curves(c).XData)
                applyFrequencyDataTip(curves(c));
            end
        end

        try
            switch lower(ext)
                case '.png'
                    if exist('exportgraphics', 'file')
                        exportgraphics(copies(end), filePath, 'Resolution', PLOT_EXPORT_DPI);
                    else
                        print(tmp, filePath, '-dpng', sprintf('-r%d', PLOT_EXPORT_DPI));
                    end
                case '.pdf'
                    if exist('exportgraphics', 'file')
                        exportgraphics(copies(end), filePath, 'ContentType', 'vector');
                    else
                        print(tmp, filePath, '-dpdf', '-bestfit');
                    end
                case '.fig'
                    % beim spaeteren Oeffnen sichtbar, obwohl die Kopie unsichtbar gespeichert wird
                    set(tmp, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');
                    savefig(tmp, filePath);
                otherwise
                    logMsg(sprintf('Dateityp %s wird nicht unterstuetzt (PNG, PDF oder FIG)', ext));
                    return;
            end
            logMsg(sprintf('Nyquist-Diagramm gespeichert: %s', filePath));
        catch ex
            logMsg(sprintf('Diagramm konnte nicht gespeichert werden: %s', ex.message));
        end
        clear cleanupFig;                                   % schliesst die Kopie
    end

    function chooseFolder()
        d = uigetdir(get(hFolder, 'String'));
        if ischar(d)
            set(hFolder, 'String', d);
        end
    end

    % Liest die Einstellungen des EIS-Panels. ok = false bei ungueltiger Eingabe (Meldung im Log).
    % job.info hat den Aufbau von jobInfo (ohne Zeitstempel), die uebrigen Felder sind die
    % Parameter des EIS-Befehls.
    function [job, ok] = readEisJob()
        ok  = false;
        job = struct();
        n = numel(cfg.bmAddr);
        sel = get(hTarget, 'Value');
        if sel <= n
            job.target = sprintf('C%d', sel);
        elseif sel == n + 1
            job.target = 'S';
        elseif sel == n + 2
            job.target = 'ALL';
        else
            job.target = 'ALLS';
        end
        job.fStart = get(hFstart, 'Value') - 1;
        job.fStop  = get(hFstop, 'Value') - 1;
        if job.fStop < job.fStart
            logMsg('Stopp-Frequenz muss unter der Start-Frequenz liegen (Stopp-Index >= Start-Index)');
            return;
        end
        job.ampIndex  = get(hAmp, 'Value') - 1;
        job.waveIndex = get(hWave, 'Value') - 1;
        job.averages  = get(hAvg, 'Value');
        job.timeIndex = get(hMeasTime, 'Value') - 1;
        % Zellen an der Rail bei der Stackmessung: Bitmaske, Bit k-1 = BM k
        selected = find(stackSel(1:n));
        job.stackMask = sum(bitshift(1, selected - 1));
        if any(strcmp(job.target, {'S', 'ALLS'})) && job.stackMask == 0
            logMsg('Stackmessung: mindestens eine Zelle muss mit der Rail verbunden sein (Haken in der Zellenübersicht)');
            return;
        end
        info = struct();
        info.folder    = get(hFolder, 'String');
        info.baseName  = regexprep(get(hFilename, 'String'), '[^\w\-]', '_');
        info.timestamp = '';
        info.comment   = get(hComment, 'String');
        info.cellNames = cellNames;
        info.settings  = struct('fStart', job.fStart, 'fStop', job.fStop, ...
                                'amplitude', AMPLITUDE_TEXT{job.ampIndex + 1}, ...
                                'waveform', WAVEFORM_TEXT{job.waveIndex + 1}, ...
                                'averages', job.averages, ...
                                'measTime', MEAS_TIME_TEXT{job.timeIndex + 1}, ...
                                'stackCells', strjoin(arrayfun(@num2str, selected, 'UniformOutput', false), ', '));
        job.info = info;
        ok = true;
    end

    function sendEis(target, job)
        sendCommand(sprintf('EIS;%s;%d;%d;%d;%d;%d;%d;%d', target, job.fStart, job.fStop, ...
                            job.ampIndex, job.waveIndex, job.averages, job.timeIndex, job.stackMask));
    end

    % neuer Messauftrag: Ergebnisse und Diagramm zuruecksetzen
    function beginJob(info)
        jobInfo = info;
        jobInfo.timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'));
        meas = containers.Map();
        cla(ax);
        plotHandles = containers.Map();
    end

    function startEis()
        [job, ok] = readEisJob();
        if ~ok
            return;
        end
        beginJob(job.info);
        sendEis(job.target, job);
    end

    function onEisBegin(f)
        % EISBEGIN;target;fstart;fstop;amp;wave;avg;time;stackMask
        t = char(f(2));
        m.target = t;
        m.cells  = zeros(0, 3);          % [BM, U mV, T degC]
        m.data   = zeros(0, 4);          % [Index, f Hz, Re uOhm, Im uOhm]
        m.pm     = pmLast;
        m.start  = datetime('now');
        meas(t) = m;
        updateEisButtons(true);
        autoOnEisBegin();
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
        set(plotHandles(t), 'UserData', m.data(:, 2), 'CreateFcn', FREQ_TIP_CREATE_FCN);
        applyFrequencyDataTip(plotHandles(t));
    end

    function applyFrequencyDataTip(h)
        % Datentipp beim Ueberfahren / Anklicken eines Punkts: Re, -Im und Frequenz
        % (Frequenzen aus UserData der Kurve; gleicher Code wie FREQ_TIP_CREATE_FCN)
        try                                                 % DataTipTemplate ab R2019a
            h.DataTipTemplate.DataTipRows = [ ...
                dataTipTextRow('Re(Z) [m\Omega]', 'XData'), ...
                dataTipTextRow('-Im(Z) [m\Omega]', 'YData'), ...
                dataTipTextRow('f [Hz]', h.UserData(:).')];
        catch ex
            if ~tipWarned                                   % nur einmal melden
                logMsg(sprintf('Frequenz-Datentipp nicht verfuegbar (MATLAB ab R2019a noetig): %s', ex.message));
                tipWarned = true;
            end
        end
    end

    function annotateFrequencies(t)
        % Beschriftet Start-, Endfrequenz und - falls vorhanden - den Knickpunkt
        % (Uebergang Halbkreis -> Diffusionsast = Minimum von -Im nach dem Scheitel)
        if ~isKey(plotHandles, t) || ~isvalid(plotHandles(t))
            return;
        end
        h = plotHandles(t);
        x = get(h, 'XData');  y = get(h, 'YData');
        fHz = meas(t).data(:, 2);
        n = numel(x);
        if n == 0
            return;
        end
        points = {1, 'Start: '; n, 'Ende: '};
        k = kneeIndex(y);
        if ~isempty(k)
            points(end + 1, :) = {k, 'Knick: '};
        end
        for p = 1:size(points, 1)
            i = points{p, 1};
            text(ax, x(i), y(i), sprintf('  %s%s', points{p, 2}, formatFrequency(fHz(i))), ...
                 'Color', get(h, 'Color'), 'FontSize', FREQ_LABEL_FONT_SIZE, 'Tag', FREQ_LABEL_TAG, ...
                 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', 'Clipping', 'on');
        end
    end

    function k = kneeIndex(y)
        % Index des Knickpunkts: kleinstes -Im nach dem Scheitel des Halbkreises
        % (Daten von hoher nach niedriger Frequenz); leer, wenn danach kein Anstieg folgt
        k = [];
        [~, apex] = max(y);
        [~, rel] = min(y(apex:end));
        candidate = apex + rel - 1;
        if candidate > apex && candidate < numel(y)
            k = candidate;
        end
    end

    function s = formatFrequency(fHz)
        if fHz >= HZ_PER_KHZ
            s = sprintf('%.3g kHz', fHz / HZ_PER_KHZ);
        else
            s = sprintf('%.3g Hz', fHz);
        end
    end

    function onEisEnd(f)
        % EISEND;target;OK   |   EISEND;target;ERR;REASON[;BMk][;BM_ERRn]
        t = char(f(2));
        if f(3) == "OK"
            file = EIS_Textdatei_schreiben(meas(t), jobInfo, targetText(t));
            annotateFrequencies(t);
            logMsg(sprintf('EIS %s fertig: %s', targetText(t), file));
            autoOnEisResult(t, true, file);
        else
            reason = char(f(4));
            if isKey(EIS_REASON_TEXT, reason)
                reason = [reason ' - ' EIS_REASON_TEXT(reason)];
            end
            for k = 5:numel(f)
                if startsWith(f(k), "BM_ERR")
                    bmErr = str2double(extractAfter(f(k), "BM_ERR"));
                    reason = sprintf('%s (BM-Fehler %d: %s)', reason, bmErr, errorText(BM_ERROR_TEXT, bmErr));
                elseif startsWith(f(k), "BM")
                    reason = sprintf('%s, betrifft BM %s', reason, extractAfter(f(k), "BM"));
                end
            end
            logMsg(sprintf('EIS %s fehlgeschlagen: %s', targetText(t), reason));
            autoOnEisResult(t, false, reason);
        end
    end

    function onEisDone(f)
        % EISDONE;ok;total
        updateEisButtons(false);
        set(hProgress, 'String', sprintf('Messauftrag beendet: %s von %s erfolgreich', f(2), f(3)));
        logMsg(get(hProgress, 'String'));
        autoOnEisDone();
    end

    %% =========================================================================
    %  Betriebsart Manuell / Automatik
    %  =========================================================================
    function a = isAutoMode()
        a = isequal(get(hMode, 'SelectedObject'), hModeAuto);
    end

    function onModeChanged()
        % Manuell: Temperaturregelung von Hand sichtbar; Automatik: Automatik-Panel an derselben Stelle
        auto = isAutoMode();
        set(pTemp, 'Visible', onOff(~auto));
        set(pAuto, 'Visible', onOff(auto));
        updateEisButtons(mmBusy);
        if auto
            resizeProfile();
            logMsg('Betriebsart: Automatik');
        else
            logMsg('Betriebsart: Manuell');
        end
    end

    %% =========================================================================
    %  Automatik: Ablaufsteuerung
    %  =========================================================================
    % Zustaende (autoRun.state), geprueft im Takt AUTO_TICK_S (autoTick):
    %   IDLE    keine Automatik
    %   WAIT    Sollwerte des Schritts gesetzt, warten bis alle Zellen die Haltezeit lang
    %           innerhalb der Toleranz liegen -> EIS starten
    %   MEAS    EIS-Auftrag(e) des Schritts laufen (Ende ueber EISDONE bzw. ERR;EIS)
    %   ASK     ein Auftrag ist fehlgeschlagen -> Dialog im naechsten Takt
    %   ASKING  Dialog offen (Wiederholen / Automatik abbrechen)
    %   RETURN  Ende oder Abbruch: Zellen auf AUTO_END_TEMP_DEGC zuruecktemperieren; sobald alle
    %           Zellen innerhalb der Toleranz liegen, wird die Temperaturregelung ausgeschaltet
    %           (die Zelle soll nicht lange ungeregelt bei hoher Temperatur bleiben -> Alterung)
    % Beteiligt sind die Zellen 1..min(Anzahl BM, Anzahl PM), d. h. Zellen mit BM und PM.

    function n = autoCellCount()
        n = min(numel(cfg.bmAddr), numel(cfg.pmAddr));
    end

    % Zellen, die das Profil abfahren, folgen aus "Messung" im EIS-Panel: Einzelzelle k ->
    % nur Zelle k; Stack, alle Zellen, alle Zellen + Stack -> alle Zellen mit BM und PM.
    % So koennen Temperierung und Messung nicht auseinanderlaufen.
    function cells = autoSelectedCells()
        sel = get(hTarget, 'Value');
        if sel <= numel(cfg.bmAddr)
            cells = sel;
        else
            cells = 1:autoCellCount();
        end
    end

    function updateAutoHint()
        cells = autoSelectedCells();
        if isempty(cells)
            set(hAutoHint, 'String', 'Temperiert: -');
        elseif any(cells > autoCellCount())
            set(hAutoHint, 'String', sprintf('Zelle %d hat kein PM', cells(1)));
        elseif get(hTarget, 'Value') <= numel(cfg.bmAddr)
            set(hAutoHint, 'String', sprintf('Temperiert: nur Zelle %d', cells));
        else
            set(hAutoHint, 'String', 'Temperiert: alle Zellen');
        end
    end

    function running = autoRunning()
        running = ~strcmp(autoRun.state, 'IDLE');
    end

    % Profil an die Zahl der Zellen anpassen (neue Zellen uebernehmen die Temperaturen von Zelle 1)
    function resizeProfile()
        n = autoCellCount();
        if autoRunning() || n == 0
            updateAutoSummary();
            return;
        end
        if isempty(autoProfile)
            autoProfile = DEFAULT_TSET_DEGC * ones(1, n);
        elseif size(autoProfile, 2) < n
            autoProfile = [autoProfile, repmat(autoProfile(:, 1), 1, n - size(autoProfile, 2))];
        else
            autoProfile = autoProfile(:, 1:n);
        end
        updateAutoSummary();
    end

    function updateAutoSummary()
        if isempty(autoProfile)
            set(hAutoSummary, 'String', 'kein Profil (nach dem Verbinden: je Zelle mit BM und PM eine Spalte)', ...
                'TooltipString', '');
            return;
        end
        parts = arrayfun(@(k) sprintf('Z%d: %s', k, stepList(autoProfile(:, k))), 1:size(autoProfile, 2), ...
                         'UniformOutput', false);
        set(hAutoSummary, 'String', sprintf('%d Schritt(e)   %s   [°C]', size(autoProfile, 1), strjoin(parts, '   |   ')), ...
            'TooltipString', strjoin(profileToText(autoProfile), newline));
    end

    function s = stepList(v)
        txt = arrayfun(@(x) sprintf('%g', x), v(:).', 'UniformOutput', false);
        if numel(txt) > PROFILE_SUMMARY_MAX_STEPS
            txt = [txt(1:PROFILE_SUMMARY_MAX_STEPS), {'...'}];
        end
        s = strjoin(txt, ' → ');
    end

    function startAuto()
        if isempty(device)
            logMsg('Automatik: nicht verbunden');
            return;
        end
        if autoRunning()
            return;
        end
        n = autoCellCount();
        if n == 0 || size(autoProfile, 2) ~= n
            logMsg('Automatik: kein gültiges Profil - je Zelle mit BM und PM wird eine Spalte gebraucht');
            return;
        end
        cells = autoSelectedCells();
        if isempty(cells) || any(cells > n)
            logMsg('Automatik: die unter "Messung" gewählte Zelle hat kein PM - sie kann nicht temperiert werden');
            return;
        end
        msg = checkProfile(autoProfile(:, cells));
        if ~isempty(msg)
            logMsg(['Automatik: ' msg]);
            return;
        end
        tol     = str2double(strrep(get(hAutoTol, 'String'), ',', '.'));
        holdMin = str2double(strrep(get(hAutoHold, 'String'), ',', '.'));
        if ~(tol > 0) || ~(holdMin >= 0)
            logMsg('Automatik: Toleranz muss > 0 K und Haltezeit >= 0 min sein');
            return;
        end
        if mmBusy
            logMsg('Automatik: es läuft noch eine EIS-Messung');
            return;
        end
        [job, ok] = readEisJob();
        if ~ok
            return;
        end
        folder = fullfile(job.info.folder, sprintf('%s_Automatik_%s', job.info.baseName, ...
                          char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'))));
        [created, mkMsg] = mkdir(folder);
        if ~created
            logMsg(['Automatik: Ordner nicht anlegbar: ' mkMsg]);
            return;
        end

        autoRun = struct('state', 'WAIT', 'folder', folder, 'profile', autoProfile, 'cells', cells, ...
                         'step', 0, 'tol', tol, 'holdS', holdMin * SECONDS_PER_MINUTE, ...
                         'criterion', get(hAutoCrit, 'Value'), 'job', job, ...
                         'stableSince', NaT, 'stepStart', NaT, 'queue', {{}}, 'failed', {{}}, ...
                         'sentTarget', '', 'sentAt', NaT, 'eisBegun', false);
        writeProfileFile(fullfile(folder, AUTO_PROFILE_FILE), autoRun);
        autoLog(sprintf('gestartet: %d Schritt(e), Zelle(n) %s, EIS %s, Toleranz %.2f K, Haltezeit %g min, Kriterium %s, Ordner %s', ...
                        size(autoProfile, 1), cellList(cells), autoTargetText(job.target), tol, holdMin, ...
                        AUTO_CRITERION_TEXT{autoRun.criterion}, folder));
        setAutoLock(true);
        autoEnterStep(1);
        start(autoTimer);
    end

    function setAutoLock(locked)
        set(autoLockHandles, 'Enable', onOff(~locked));
        set(hAutoStart, 'Enable', onOff(~locked));
        set(hAutoStop, 'Enable', onOff(locked));
    end

    % Sollwerte des Schritts an die PMs, Regelung einschalten, auf stabile Temperatur warten
    function autoEnterStep(stepIndex)
        autoRun.step        = stepIndex;
        autoRun.state       = 'WAIT';
        autoRun.stableSince = NaT;
        autoRun.stepStart   = datetime('now');
        temps = autoRun.profile(stepIndex, :);
        for k = autoRun.cells
            sendCommand(sprintf('PMSET;%d;%d', k, round(temps(k) * CENTI)));
            sendCommand(sprintf('PMSTART;%d', k));
        end
        autoLog(sprintf('Schritt %d/%d: Solltemperaturen %s °C', stepIndex, autoStepCount(), temperatureList(temps(autoRun.cells))));
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d: Sollwerte gesetzt (%s °C)', ...
            stepIndex, autoStepCount(), temperatureList(temps(autoRun.cells))), 'ForegroundColor', 'k');
    end

    function r = isRunning(t)
        r = ~isempty(t) && isvalid(t) && strcmp(get(t, 'Running'), 'on');
    end

    function n = autoStepCount()
        n = size(autoRun.profile, 1);
    end

    function autoTick()
        if ~isvalid(fig)
            return;
        end
        try
            switch autoRun.state
                case 'WAIT', autoCheckTemperatures();
                case 'MEAS', autoCheckEisStart();
                case 'ASK',    autoAskRepeat();
                case 'RETURN', autoCheckReturn();
            end
        catch ex
            logMsg(['Automatik: ' ex.message]);
        end
    end

    % Abweichung jeder Zelle von ihrer Solltemperatur; problem = Grund, warum die Bedingung
    % gerade nicht pruefbar ist (Board offline, Wert ungueltig, Sollwert nicht uebernommen)
    % temps: Solltemperaturen aller Zellen (Spalten des Profils); dev: je beteiligte Zelle
    function [dev, problem] = autoDeviations(temps, nowT)
        dev = nan(1, numel(autoRun.cells));
        problem = '';
        for idx = 1:numel(autoRun.cells)
            k = autoRun.cells(idx);
            [t, valid, why] = autoCellTemperature(k, nowT);
            if ~valid
                problem = sprintf('Zelle %d: %s', k, why);
                continue;
            end
            if k > numel(pmLast) || isempty(pmLast(k).tSet) || abs(pmLast(k).tSet - temps(k)) > AUTO_SETPOINT_MATCH_K
                problem = sprintf('Zelle %d: PM hat den Sollwert noch nicht übernommen', k);
            elseif pmLast(k).error
                problem = sprintf('Zelle %d: PM meldet einen Fehler', k);
            end
            dev(idx) = t - temps(k);
        end
    end

    function autoCheckTemperatures()
        stepIndex = autoRun.step;
        temps = autoRun.profile(stepIndex, :);
        nowT = datetime('now');
        [dev, problem] = autoDeviations(temps, nowT);
        inTol = isempty(problem) && all(abs(dev) < autoRun.tol);
        if inTol
            if isnat(autoRun.stableSince)
                autoRun.stableSince = nowT;
                autoLog(sprintf('Schritt %d: alle Zellen innerhalb ±%.2f K', stepIndex, autoRun.tol), false);
            end
            held = seconds(nowT - autoRun.stableSince);
        else
            if ~isnat(autoRun.stableSince)
                autoLog(sprintf('Schritt %d: Toleranz verlassen (Abweichungen %s K)', stepIndex, deviationList(dev)), false);
            end
            autoRun.stableSince = NaT;
            held = 0;
        end

        status = sprintf('Schritt %d/%d (%s °C): warte %s, stabil %s von %s, Abweichung %s K', ...
            stepIndex, autoStepCount(), temperatureList(temps(autoRun.cells)), minSec(seconds(nowT - autoRun.stepStart)), ...
            minSec(held), minSec(autoRun.holdS), deviationList(dev));
        color = 'k';
        if ~isempty(problem)
            status = [status ' - ' problem];
            color = COLOR_TEXT_ERROR;
        end
        set(hAutoStatus, 'String', status, 'TooltipString', status, 'ForegroundColor', color);

        if inTol && held >= autoRun.holdS
            autoLog(sprintf('Schritt %d: Temperatur %s gehalten (Wartezeit gesamt %s) -> EIS-Messung', ...
                            stepIndex, minSec(autoRun.holdS), minSec(seconds(nowT - autoRun.stepStart))));
            autoStartMeasurement();
        end
    end

    % Temperatur von Zelle k nach dem gewaehlten Kriterium; valid = false mit Begruendung,
    % wenn das Board nicht antwortet, der Wert ungueltig oder veraltet ist
    function [t, valid, why] = autoCellTemperature(k, nowT)
        t = NaN;  valid = false;  why = '';
        if autoRun.criterion == AUTO_CRITERION_TAB
            if k > numel(bmLast) || isempty(bmLast(k).time)
                why = 'noch kein BM-Status';  return;
            end
            r = bmLast(k);
            if ~r.online
                why = 'BM offline';  return;
            end
            if ~r.tValid
                why = 'Tab-Temperatur ungültig';  return;
            end
            t = r.t;
        else
            if k > numel(pmLast) || isempty(pmLast(k).time)
                why = 'noch kein PM-Status';  return;
            end
            r = pmLast(k);
            if ~r.online
                why = 'PM offline';  return;
            end
            t = r.tAct;
        end
        if seconds(nowT - r.time) > AUTO_DATA_MAX_AGE_S
            t = NaN;  why = 'Status veraltet';  return;
        end
        valid = true;
    end

    function autoStartMeasurement()
        temps = autoRun.profile(autoRun.step, :);
        info = autoRun.job.info;
        info.folder    = autoRun.folder;
        info.baseName  = sprintf('%s_S%02d%s', autoRun.job.info.baseName, autoRun.step, temperatureSuffix(temps(autoRun.cells)));
        info.comment   = strtrim(sprintf('%s [Automatik Schritt %d/%d, T Soll %s °C]', autoRun.job.info.comment, ...
                                         autoRun.step, autoStepCount(), temperatureList(temps(autoRun.cells))));
        info.cellNames = cellNames;
        beginJob(info);
        autoRun.queue  = {autoRun.job.target};
        autoRun.failed = {};
        autoRun.state  = 'MEAS';
        autoSendNext();
    end

    function autoSendNext()
        autoRun.sentTarget = autoRun.queue{1};
        autoRun.queue(1)   = [];
        autoRun.eisBegun   = false;
        autoRun.sentAt     = datetime('now');
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d: EIS-Messung %s', autoRun.step, autoStepCount(), ...
            autoTargetText(autoRun.sentTarget)), 'ForegroundColor', 'k');
        sendEis(autoRun.sentTarget, autoRun.job);
    end

    function autoCheckEisStart()
        if ~autoRun.eisBegun && seconds(datetime('now') - autoRun.sentAt) > AUTO_EIS_START_TIMEOUT_S
            autoMarkFailed(autoRun.sentTarget, sprintf('keine Antwort vom MM nach %d s', AUTO_EIS_START_TIMEOUT_S));
            autoAfterTarget();
        end
    end

    % ---- Rueckmeldungen der EIS-Messung (aus dem Empfang) ----
    function autoOnEisBegin()
        if strcmp(autoRun.state, 'MEAS')
            autoRun.eisBegun = true;
        end
    end

    function autoOnEisResult(target, ok, detail)
        if ~strcmp(autoRun.state, 'MEAS')
            return;
        end
        if ok
            autoLog(sprintf('Schritt %d: EIS %s gespeichert: %s', autoRun.step, autoTargetText(target), detail), false);
        else
            autoMarkFailed(target, detail);
        end
    end

    function autoOnEisRejected(reason)
        % ERR;EIS;<Grund>: der Auftrag wurde gar nicht gestartet
        if strcmp(autoRun.state, 'MEAS') && ~autoRun.eisBegun
            autoMarkFailed(autoRun.sentTarget, ['vom MM abgelehnt: ' reason]);
            autoAfterTarget();
        end
    end

    function autoOnEisDone()
        if strcmp(autoRun.state, 'MEAS') && autoRun.eisBegun
            autoAfterTarget();
        end
    end

    function autoMarkFailed(target, reason)
        autoRun.failed{end + 1} = target;
        autoLog(sprintf('Schritt %d: EIS %s fehlgeschlagen: %s', autoRun.step, autoTargetText(target), reason));
    end

    % ein Auftrag ist fertig: naechster aus der Warteschlange, sonst Schritt auswerten
    function autoAfterTarget()
        if ~isempty(autoRun.queue)
            autoSendNext();
        elseif isempty(autoRun.failed)
            autoLog(sprintf('Schritt %d/%d abgeschlossen', autoRun.step, autoStepCount()));
            if autoRun.step < autoStepCount()
                autoEnterStep(autoRun.step + 1);
            else
                autoFinish();
            end
        else
            autoRun.state = 'ASK';          % Dialog im naechsten Takt, nicht im Empfangs-Callback
        end
    end

    function autoAskRepeat()
        autoRun.state = 'ASKING';
        failedText = strjoin(cellfun(@autoTargetText, unique(autoRun.failed, 'stable'), 'UniformOutput', false), ', ');
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d: EIS fehlgeschlagen (%s) - Entscheidung nötig', ...
            autoRun.step, autoStepCount(), failedText), 'ForegroundColor', COLOR_TEXT_ERROR);
        answer = questdlg(sprintf(['Schritt %d/%d: Die EIS-Messung von %s ist fehlgeschlagen (Grund im Log).\n\n' ...
                                   '%s: nur die fehlgeschlagenen Messungen erneut starten, die Temperatur wird gehalten.\n' ...
                                   '%s: Automatik beenden, Zellen auf %g °C temperieren, danach Temperaturregelung aus.'], ...
                                  autoRun.step, autoStepCount(), failedText, AUTO_ANSWER_REPEAT, AUTO_ANSWER_ABORT, ...
                                  AUTO_END_TEMP_DEGC), ...
                          'Automatik: Messfehler', AUTO_ANSWER_REPEAT, AUTO_ANSWER_ABORT, AUTO_ANSWER_REPEAT);
        if ~strcmp(autoRun.state, 'ASKING')
            return;                          % inzwischen anders beendet (z. B. Abbrechen-Knopf)
        end
        switch answer
            case AUTO_ANSWER_REPEAT
                autoRun.queue  = unique(autoRun.failed, 'stable');
                autoRun.failed = {};
                autoRun.state  = 'MEAS';
                autoLog(sprintf('Schritt %d: Wiederholung von %s', autoRun.step, failedText));
                autoSendNext();
            case AUTO_ANSWER_ABORT
                autoStop('Abbruch nach fehlgeschlagener EIS-Messung', 'return');
            otherwise
                autoRun.state = 'ASK';      % Dialog geschlossen ohne Auswahl: erneut fragen
        end
    end

    function onAutoStopPressed()
        if strcmp(autoRun.state, 'RETURN')
            answer = questdlg(sprintf(['Die Zellen werden gerade auf %g °C zurücktemperiert. Temperaturregelung ' ...
                                       'sofort ausschalten? Die Zellen kühlen bzw. erwärmen sich dann ungeregelt.'], AUTO_END_TEMP_DEGC), ...
                              'Temperierung ausschalten', AUTO_ANSWER_OFF_NOW, 'Weiter zurücktemperieren', 'Weiter zurücktemperieren');
            if strcmp(answer, AUTO_ANSWER_OFF_NOW) && strcmp(autoRun.state, 'RETURN')
                autoStop('Temperierung von Hand ausgeschaltet', 'now');
            end
            return;
        end
        answer = questdlg(sprintf(['Automatik abbrechen? Eine laufende EIS-Messung wird abgebrochen, die Zellen werden ' ...
                                   'auf %g °C temperiert und danach wird die Temperaturregelung ausgeschaltet.'], AUTO_END_TEMP_DEGC), ...
                          'Automatik abbrechen', AUTO_ANSWER_ABORT, 'Weiterlaufen lassen', 'Weiterlaufen lassen');
        if strcmp(answer, AUTO_ANSWER_ABORT) && autoRunning() && ~strcmp(autoRun.state, 'RETURN')
            autoStop('vom Benutzer abgebrochen', 'return');
        end
    end

    function autoFinish()
        autoLog(sprintf('alle %d Schritte gemessen', autoStepCount()));
        autoReturnToEndTemp(sprintf('Automatik abgeschlossen (%d Schritte)', autoStepCount()), COLOR_TEXT_OK);
    end

    % Abbruch. mode:
    %   'return'   Zellen auf AUTO_END_TEMP_DEGC temperieren, dann Regelung aus (Normalfall)
    %   'now'      Regelung sofort aus (nur aus dem Zuruecktemperieren heraus, von Hand)
    %   'handover' GUI wird geschlossen/getrennt: PMs auf AUTO_END_TEMP_DEGC setzen und
    %              eingeschaltet lassen - sie regeln selbstaendig weiter, ausschalten von Hand
    function autoStop(reason, mode)
        if ~autoRunning()
            return;
        end
        if strcmp(autoRun.state, 'MEAS')
            sendCommand('ABORT');                    % laufende EIS-Messung beenden
        end
        switch mode
            case 'now'
                autoStopPms();
                autoLog(sprintf('%s - Temperaturregelung ausgeschaltet', reason));
                autoCleanup(sprintf('%s - Temperaturregelung aus', reason), COLOR_TEXT_ERROR);
            case 'handover'
                autoSetEndTemp();
                autoLog(sprintf('abgebrochen in Schritt %d/%d: %s - PMs regeln selbständig auf %g °C weiter (von Hand ausschalten)', ...
                                autoRun.step, autoStepCount(), reason, AUTO_END_TEMP_DEGC));
                autoCleanup(sprintf('Automatik abgebrochen (%s) - PMs regeln auf %g °C', reason, AUTO_END_TEMP_DEGC), COLOR_TEXT_ERROR);
            otherwise
                autoLog(sprintf('abgebrochen in Schritt %d/%d: %s', autoRun.step, autoStepCount(), reason));
                autoReturnToEndTemp(sprintf('Automatik abgebrochen (%s)', reason), COLOR_TEXT_ERROR);
        end
    end

    function autoSetEndTemp()
        for k = autoRun.cells
            sendCommand(sprintf('PMSET;%d;%d', k, round(AUTO_END_TEMP_DEGC * CENTI)));
            sendCommand(sprintf('PMSTART;%d', k));
        end
    end

    % Zellen auf die Endtemperatur bringen; autoCheckReturn schaltet danach die Regelung aus
    function autoReturnToEndTemp(summary, color)
        autoRun.state      = 'RETURN';
        autoRun.endSummary = summary;
        autoRun.endColor   = color;
        autoRun.stepStart  = datetime('now');
        autoSetEndTemp();
        autoLog(sprintf('Zellen werden auf %g °C temperiert, danach wird die Temperaturregelung ausgeschaltet', AUTO_END_TEMP_DEGC));
        set(hAutoStop, 'String', 'Temperierung sofort aus');
        if ~isRunning(autoTimer)
            start(autoTimer);
        end
    end

    function autoCheckReturn()
        nowT = datetime('now');
        temps = AUTO_END_TEMP_DEGC * ones(1, size(autoRun.profile, 2));
        [dev, problem] = autoDeviations(temps, nowT);
        status = sprintf('%s - Zellen auf %g °C (seit %s), Abweichung %s K', autoRun.endSummary, AUTO_END_TEMP_DEGC, ...
                         minSec(seconds(nowT - autoRun.stepStart)), deviationList(dev));
        color = 'k';
        if ~isempty(problem)
            status = [status ' - ' problem];
            color = COLOR_TEXT_ERROR;
        end
        set(hAutoStatus, 'String', status, 'TooltipString', status, 'ForegroundColor', color);
        if isempty(problem) && all(abs(dev) < autoRun.tol)
            autoStopPms();
            autoLog(sprintf('%g °C erreicht (nach %s) - Temperaturregelung ausgeschaltet', AUTO_END_TEMP_DEGC, ...
                            minSec(seconds(nowT - autoRun.stepStart))));
            autoCleanup(sprintf('%s - %g °C erreicht, Temperaturregelung aus', autoRun.endSummary, AUTO_END_TEMP_DEGC), ...
                        autoRun.endColor);
        end
    end

    function autoStopPms()
        for k = autoRun.cells
            sendCommand(sprintf('PMSTOP;%d', k));
        end
    end

    function autoCleanup(statusText, color)
        if ~isempty(autoTimer) && isvalid(autoTimer)
            stop(autoTimer);
        end
        autoRun.state = 'IDLE';
        set(hAutoStop, 'String', 'Automatik abbrechen');
        setAutoLock(false);
        updateEisButtons(mmBusy);
        set(hAutoStatus, 'String', statusText, 'TooltipString', statusText, 'ForegroundColor', color);
    end

    % Meldung ins GUI-Log (optional) und in die Ablaufdatei des Laufs
    function autoLog(msg, showInGui)
        if nargin < 2
            showInGui = true;
        end
        if showInGui
            logMsg(['Automatik: ' msg]);
        end
        if isempty(autoRun.folder)
            return;
        end
        fid = fopen(fullfile(autoRun.folder, AUTO_LOG_FILE), 'a', 'n', 'UTF-8');
        if fid > 0
            fprintf(fid, '%s  %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), msg);
            fclose(fid);
        end
    end

    function writeProfileFile(filePath, run)
        fid = fopen(filePath, 'w', 'n', 'UTF-8');
        if fid < 0
            logMsg(['Automatik: Profildatei nicht schreibbar: ' filePath]);
            return;
        end
        s = run.job.info.settings;
        fprintf(fid, '# Temperaturprofil der Automatik (eine Zeile je Zelle, Werte in °C je Schritt)\n');
        fprintf(fid, '# Start: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        fprintf(fid, '# Toleranz: %.2f K, Haltezeit: %g min, Kriterium: %s\n', run.tol, ...
                run.holdS / SECONDS_PER_MINUTE, AUTO_CRITERION_TEXT{run.criterion});
        fprintf(fid, '# Beteiligte Zellen: %s\n', cellList(run.cells));
        fprintf(fid, '# EIS: %s, Frequenzindex %d..%d, Amplitude %s, Signalform %s, Mittelung %d, Messdauer %s\n', ...
                autoTargetText(run.job.target), s.fStart, s.fStop, s.amplitude, s.waveform, s.averages, s.measTime);
        lines = profileToText(run.profile);
        fprintf(fid, '%s\n', lines{:});
        fclose(fid);
    end

    function s = autoTargetText(t)
        switch t
            case 'ALL',  s = 'alle Zellen';
            case 'ALLS', s = 'alle Zellen + Stack';
            otherwise,   s = targetText(t);
        end
    end

    function s = cellList(cells)
        s = strjoin(arrayfun(@(k) cellLabel(k), cells, 'UniformOutput', false), ', ');
    end

    function s = temperatureList(temps)
        s = strjoin(arrayfun(@(x) sprintf('%g', x), temps, 'UniformOutput', false), ' / ');
    end

    function s = deviationList(dev)
        s = strjoin(arrayfun(@(x) sprintf('%+.2f', x), dev, 'UniformOutput', false), ' / ');
    end

    % Dateinamenszusatz: _22_5C, wenn alle Zellen dieselbe Solltemperatur haben
    function s = temperatureSuffix(temps)
        s = '';
        if all(temps == temps(1))
            s = ['_' strrep(sprintf('%g', temps(1)), '.', '_') 'C'];
        end
    end

    function s = minSec(sec)
        sec = max(0, floor(sec));
        s = sprintf('%d:%02d', floor(sec / SECONDS_PER_MINUTE), mod(sec, SECONDS_PER_MINUTE));
    end

    %% =========================================================================
    %  Temperaturprofil: Text <-> Matrix
    %  =========================================================================
    % Textformat: eine Zeile je Zelle, Werte je Schritt durch Komma, Semikolon oder Leerzeichen
    % getrennt, Dezimalpunkt. Zeilen mit '#' sind Kommentare.
    %   Zelle 1: 25, 15, 5, 25
    %   Zelle 2: 25, 20, 10, 25
    %   alle: 25, 15, 5          (gilt fuer alle Zellen; spaetere Zeilen ueberschreiben einzelne)
    % Zeilen ohne Bezeichnung gelten der Reihe nach fuer Zelle 1, 2, ...

    function lines = profileToText(P)
        lines = cell(1, size(P, 2));
        for k = 1:size(P, 2)
            lines{k} = sprintf('%s: %s', cellLabel(k), ...
                strjoin(arrayfun(@(x) sprintf('%g', x), P(:, k).', 'UniformOutput', false), ', '));
        end
    end

    function [P, msg] = parseProfileText(txt, n)
        P = [];  msg = '';
        if ischar(txt)
            txt = cellstr(txt);                          % mehrzeiliges Edit-Feld: Zeichenmatrix
        end
        txt = splitlines(strjoin(reshape(cellstr(txt), 1, []), newline));
        cols = cell(1, n);
        nextCol = 1;
        for i = 1:numel(txt)
            line = strtrim(txt{i});
            if isempty(line) || line(1) == '#'
                continue;
            end
            label = '';
            values = line;
            colon = strfind(line, ':');
            if ~isempty(colon)
                label  = strtrim(line(1:colon(1) - 1));
                values = line(colon(1) + 1:end);
            end
            parts = regexp(strtrim(values), '[,;\s]+', 'split');
            parts = parts(~cellfun(@isempty, parts));
            v = str2double(parts);
            if isempty(v) || any(isnan(v))
                msg = sprintf('Zeile "%s": keine gültigen Zahlen (Dezimalpunkt verwenden, Werte mit Komma, Semikolon oder Leerzeichen trennen)', line);
                return;
            end
            if isempty(label)
                targets = nextCol;
            elseif ~isempty(regexpi(label, '^(alle|all)\>', 'once'))
                targets = 1:n;
            else
                tok = regexpi(label, '^(?:zelle|cell|z)\s*(\d+)', 'tokens', 'once');
                if isempty(tok)
                    msg = sprintf('Zeile "%s": Bezeichnung nicht erkannt (z. B. "Zelle 1:" oder "alle:")', line);
                    return;
                end
                targets = str2double(tok{1});
            end
            if any(targets < 1 | targets > n)
                msg = sprintf('Zeile "%s": es gibt nur Zelle 1 bis %d', line, n);
                return;
            end
            for c = targets
                cols{c} = v(:);
            end
            nextCol = max(targets) + 1;
        end
        missing = find(cellfun(@isempty, cols));
        if ~isempty(missing)
            msg = sprintf('Profil fehlt für Zelle %s', strjoin(arrayfun(@num2str, missing, 'UniformOutput', false), ', '));
            return;
        end
        len = cellfun(@numel, cols);
        if any(len ~= len(1))
            msg = sprintf('Alle Zellen brauchen gleich viele Schritte (jetzt: %s)', ...
                          strjoin(arrayfun(@num2str, len, 'UniformOutput', false), ' / '));
            return;
        end
        P = [cols{:}];
        msg = checkProfile(P);
    end

    function msg = checkProfile(P)
        msg = '';
        if isempty(P)
            msg = 'Profil ist leer';
        elseif any(isnan(P(:)))
            msg = 'Profil enthält ungültige Werte';
        elseif any(P(:) < PROFILE_T_MIN_DEGC | P(:) > PROFILE_T_MAX_DEGC)
            msg = sprintf('Solltemperaturen müssen zwischen %g und %g °C liegen (Bereich des PM)', ...
                          PROFILE_T_MIN_DEGC, PROFILE_T_MAX_DEGC);
        end
    end

    %% =========================================================================
    %  Temperaturprofil: Editor (Tabelle, Diagramm mit verschiebbaren Punkten, Text)
    %  =========================================================================
    function openProfileEditor()
        if ~isempty(profileEdit.fig) && isvalid(profileEdit.fig)
            figure(profileEdit.fig);                    % schon offen: nach vorne holen
            return;
        end
        n = autoCellCount();
        if n == 0
            logMsg('Profil: zuerst verbinden - je Zelle werden ein BM und ein PM gebraucht');
            return;
        end
        resizeProfile();
        pe = struct();
        pe.P      = autoProfile;
        pe.selRow = [];                                  % markierter Schritt (Tabelle / Diagramm)
        pe.drag   = [];
        pe.fig = figure('Name', 'Temperaturprofil (Automatik)', 'NumberTitle', 'off', 'MenuBar', 'none', ...
            'ToolBar', 'none', 'Units', 'pixels', 'Position', [120 120 PROFILE_FIG_SIZE_PX], ...
            'WindowButtonMotionFcn', @(~, ~) profileDragMove(), 'WindowButtonUpFcn', @(~, ~) profileDragEnd());
        pe.table = uitable(pe.fig, 'Units', 'normalized', 'Position', [0.02 0.50 0.40 0.46], ...
            'ColumnEditable', true(1, n), 'ColumnName', arrayfun(@(k) sprintf('Zelle %d [°C]', k), 1:n, 'UniformOutput', false), ...
            'CellEditCallback', @(src, ev) profileCellEdited(src, ev), ...
            'CellSelectionCallback', @(~, ev) profileCellSelected(ev));
        % Schritte bearbeiten: wirken auf den markierten Schritt (Klick in die Tabelle oder auf
        % einen Punkt im Diagramm)
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Davor einfügen', 'Units', 'normalized', 'Position', [0.02 0.43 0.095 0.055], ...
            'TooltipString', 'Zwischenschritt vor dem markierten Schritt (Mittelwert der Nachbarn)', ...
            'Callback', @(~, ~) profileInsertStep(PROFILE_INSERT_BEFORE));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Danach einfügen', 'Units', 'normalized', 'Position', [0.12 0.43 0.095 0.055], ...
            'TooltipString', 'Zwischenschritt nach dem markierten Schritt (Mittelwert der Nachbarn; ohne Markierung am Ende)', ...
            'Callback', @(~, ~) profileInsertStep(PROFILE_INSERT_AFTER));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Löschen', 'Units', 'normalized', 'Position', [0.22 0.43 0.095 0.055], ...
            'TooltipString', 'markierten (sonst letzten) Schritt löschen', 'Callback', @(~, ~) profileRemoveStep());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Alle wie Zelle 1', 'Units', 'normalized', 'Position', [0.32 0.43 0.10 0.055], ...
            'TooltipString', 'Temperaturen von Zelle 1 für alle Zellen übernehmen', 'Callback', @(~, ~) profileCopyFirst());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', '▲ nach oben', 'Units', 'normalized', 'Position', [0.02 0.365 0.095 0.055], ...
            'TooltipString', 'markierten Schritt eine Position früher ausführen', ...
            'Callback', @(~, ~) profileMoveStep(PROFILE_INSERT_BEFORE));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', '▼ nach unten', 'Units', 'normalized', 'Position', [0.12 0.365 0.095 0.055], ...
            'TooltipString', 'markierten Schritt eine Position später ausführen', ...
            'Callback', @(~, ~) profileMoveStep(PROFILE_INSERT_AFTER));
        pe.selText = uicontrol(pe.fig, 'Style', 'text', 'String', 'kein Schritt markiert', 'Units', 'normalized', ...
            'Position', [0.22 0.365 0.20 0.045], 'HorizontalAlignment', 'left');
        pe.ax = axes(pe.fig, 'Units', 'normalized', 'Position', [0.50 0.47 0.47 0.47]);
        pe.status = uicontrol(pe.fig, 'Style', 'text', 'String', '', 'Units', 'normalized', 'Position', [0.46 0.36 0.52 0.05], ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold');
        uicontrol(pe.fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.02 0.27 0.62 0.07], 'HorizontalAlignment', 'left', ...
            'String', sprintf(['Texteingabe: eine Zeile je Zelle, Werte je Schritt mit Komma getrennt, Dezimalpunkt,\n' ...
                               'z. B. "Zelle 1: 25, 15, 5, 25" oder "alle: 25, 15, 5" (Zeilen mit # = Kommentar)']));
        pe.text = uicontrol(pe.fig, 'Style', 'edit', 'Max', 2, 'Min', 0, 'Units', 'normalized', 'Position', [0.02 0.03 0.62 0.24], ...
            'HorizontalAlignment', 'left', 'FontName', 'Consolas', 'BackgroundColor', 'w');
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Text → Tabelle', 'Units', 'normalized', 'Position', [0.66 0.19 0.15 0.07], ...
            'Callback', @(~, ~) profileTextApply());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Laden ...', 'Units', 'normalized', 'Position', [0.66 0.11 0.15 0.07], ...
            'Callback', @(~, ~) profileLoad());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Speichern ...', 'Units', 'normalized', 'Position', [0.66 0.03 0.15 0.07], ...
            'Callback', @(~, ~) profileSave());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Übernehmen', 'Units', 'normalized', 'Position', [0.83 0.11 0.15 0.07], ...
            'FontWeight', 'bold', 'TooltipString', 'Profil für die Automatik übernehmen', 'Callback', @(~, ~) profileApply());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Schließen', 'Units', 'normalized', 'Position', [0.83 0.03 0.15 0.07], ...
            'Callback', @(~, ~) delete(pe.fig));
        profileEdit = pe;
        profileRefresh(true);
    end

    % Tabelle und Diagramm (und auf Wunsch den Text) aus profileEdit.P neu aufbauen
    function profileRefresh(updateText)
        P = profileEdit.P;
        numSteps = size(P, 1);
        sel = profileEdit.selRow;
        if ~isempty(sel) && sel > numSteps
            sel = [];
            profileEdit.selRow = [];
        end
        rowNames = arrayfun(@(s) sprintf('Schritt %d', s), 1:numSteps, 'UniformOutput', false);
        if ~isempty(sel)
            rowNames{sel} = [rowNames{sel} PROFILE_SEL_MARK];
            set(profileEdit.selText, 'String', sprintf('markiert: Schritt %d', sel));
        else
            set(profileEdit.selText, 'String', 'kein Schritt markiert');
        end
        set(profileEdit.table, 'Data', P, 'RowName', rowNames);
        a = profileEdit.ax;
        cla(a);
        hold(a, 'on'); grid(a, 'on'); box(a, 'on');
        colors = get(a, 'ColorOrder');
        profileEdit.lines = gobjects(1, size(P, 2));
        for k = 1:size(P, 2)
            c = colors(mod(k - 1, size(colors, 1)) + 1, :);
            profileEdit.lines(k) = plot(a, 1:numSteps, P(:, k), '-o', 'Color', c, 'MarkerFaceColor', c, ...
                'LineWidth', PROFILE_LINE_WIDTH, 'MarkerSize', PROFILE_MARKER_SIZE, 'DisplayName', cellLabel(k), ...
                'ButtonDownFcn', @(~, ~) profileDragStart(k));
        end
        xlim(a, [0.5, numSteps + 0.5]);
        ylim(a, [PROFILE_T_MIN_DEGC, PROFILE_T_MAX_DEGC]);
        set(a, 'XTick', 1:numSteps);
        if isempty(sel)                                  % markierter Schritt: nur in der Achsenbeschriftung
            xlabel(a, 'Schritt');
        else
            xlabel(a, sprintf('Schritt   (markiert: Schritt %d)', sel));
        end
        ylabel(a, 'T Soll [°C]');
        title(a, sprintf('Punkte mit der Maus verschieben (Raster %g K)', PROFILE_DRAG_STEP_K));
        legend(a, 'Location', 'best', 'Interpreter', 'none');
        if updateText
            set(profileEdit.text, 'String', profileToText(P));
        end
    end

    function profileStatus(msg, isError)
        color = COLOR_TEXT_OK;
        if isError
            color = COLOR_TEXT_ERROR;
        end
        set(profileEdit.status, 'String', msg, 'TooltipString', msg, 'ForegroundColor', color);
    end

    function profileDragStart(k)
        cp = get(profileEdit.ax, 'CurrentPoint');
        stepIndex = min(max(round(cp(1, 1)), 1), size(profileEdit.P, 1));
        profileEdit.drag = [stepIndex, k];
        profileEdit.selRow = stepIndex;                 % Klick auf einen Punkt markiert den Schritt
    end

    function profileDragMove()
        if isempty(profileEdit.fig) || ~isvalid(profileEdit.fig) || isempty(profileEdit.drag)
            return;
        end
        cp = get(profileEdit.ax, 'CurrentPoint');
        t = round(cp(1, 2) / PROFILE_DRAG_STEP_K) * PROFILE_DRAG_STEP_K;
        t = min(max(t, PROFILE_T_MIN_DEGC), PROFILE_T_MAX_DEGC);
        stepIndex = profileEdit.drag(1);  k = profileEdit.drag(2);
        if profileEdit.P(stepIndex, k) ~= t
            profileEdit.P(stepIndex, k) = t;
            set(profileEdit.lines(k), 'YData', profileEdit.P(:, k));
            set(profileEdit.table, 'Data', profileEdit.P);
        end
    end

    function profileDragEnd()
        if isempty(profileEdit.fig) || ~isvalid(profileEdit.fig) || isempty(profileEdit.drag)
            return;
        end
        profileEdit.drag = [];
        profileRefresh(true);
        profileStatus('geändert - mit "Übernehmen" für die Automatik setzen', false);
    end

    function profileCellEdited(src, ev)
        P = get(src, 'Data');
        v = ev.NewData;
        if ~isnumeric(v) || ~isscalar(v) || isnan(v) || v < PROFILE_T_MIN_DEGC || v > PROFILE_T_MAX_DEGC
            P(ev.Indices(1), ev.Indices(2)) = ev.PreviousData;
            profileStatus(sprintf('ungültiger Wert - erlaubt sind %g bis %g °C', PROFILE_T_MIN_DEGC, PROFILE_T_MAX_DEGC), true);
        else
            profileStatus('geändert - mit "Übernehmen" für die Automatik setzen', false);
        end
        profileEdit.P = P;
        profileRefresh(true);
    end

    function profileCellSelected(ev)
        if ~isempty(ev.Indices) && ~isequal(profileEdit.selRow, ev.Indices(1, 1))
            profileEdit.selRow = ev.Indices(1, 1);
            set(profileEdit.selText, 'String', sprintf('markiert: Schritt %d', profileEdit.selRow));
        end
    end

    % Zwischenschritt vor (direction = PROFILE_INSERT_BEFORE) oder nach dem markierten Schritt.
    % Temperaturen: Mittelwert der beiden Nachbarschritte (im Raster PROFILE_DRAG_STEP_K),
    % am Anfang/Ende eine Kopie des Randschritts. Ohne Markierung: am Anfang bzw. Ende.
    function profileInsertStep(direction)
        P = profileEdit.P;
        numSteps = size(P, 1);
        r = profileEdit.selRow;
        if isempty(r)
            if direction == PROFILE_INSERT_AFTER
                r = numSteps;
            else
                r = 1;
            end
        end
        if direction == PROFILE_INSERT_AFTER
            neighbours = [r, r + 1];
            pos = r + 1;                                 % Index des neuen Schritts
        else
            neighbours = [r - 1, r];
            pos = r;
        end
        neighbours = neighbours(neighbours >= 1 & neighbours <= numSteps);
        newRow = round(mean(P(neighbours, :), 1) / PROFILE_DRAG_STEP_K) * PROFILE_DRAG_STEP_K;
        profileEdit.P = [P(1:pos - 1, :); newRow; P(pos:end, :)];
        profileEdit.selRow = pos;                        % neuer Schritt ist markiert -> direkt anpassen
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d eingefügt - mit "Übernehmen" für die Automatik setzen', pos), false);
    end

    % markierten Schritt um eine Position verschieben (PROFILE_INSERT_BEFORE = nach oben)
    function profileMoveStep(direction)
        r = profileEdit.selRow;
        if isempty(r)
            profileStatus('zuerst einen Schritt markieren (Tabelle oder Punkt im Diagramm)', true);
            return;
        end
        target = r + direction;
        if target < 1 || target > size(profileEdit.P, 1)
            return;                                      % schon am Anfang / Ende
        end
        profileEdit.P([r, target], :) = profileEdit.P([target, r], :);
        profileEdit.selRow = target;                     % Markierung wandert mit
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d -> %d verschoben - mit "Übernehmen" für die Automatik setzen', r, target), false);
    end

    function profileRemoveStep()
        P = profileEdit.P;
        if size(P, 1) <= 1
            profileStatus('mindestens ein Schritt wird gebraucht', true);
            return;
        end
        r = size(P, 1);
        if ~isempty(profileEdit.selRow) && profileEdit.selRow <= size(P, 1)
            r = profileEdit.selRow;
        end
        P(r, :) = [];
        profileEdit.P = P;
        profileEdit.selRow = [];
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d gelöscht - mit "Übernehmen" für die Automatik setzen', r), false);
    end

    function profileCopyFirst()
        profileEdit.P = repmat(profileEdit.P(:, 1), 1, size(profileEdit.P, 2));
        profileRefresh(true);
    end

    function ok = profileTextApply()
        [P, msg] = parseProfileText(get(profileEdit.text, 'String'), size(profileEdit.P, 2));
        ok = isempty(msg);
        if ~ok
            profileStatus(msg, true);
            return;
        end
        profileEdit.P = P;
        profileRefresh(true);
        profileStatus('Text übernommen - mit "Übernehmen" für die Automatik setzen', false);
    end

    function profileLoad()
        [file, folder] = uigetfile({'*.txt', 'Temperaturprofil (*.txt)'}, 'Temperaturprofil laden', [PROFILE_FOLDER filesep]);
        if isequal(file, 0)
            return;
        end
        set(profileEdit.text, 'String', splitlines(fileread(fullfile(folder, file))));
        if profileTextApply()
            profileStatus(sprintf('geladen: %s - mit "Übernehmen" für die Automatik setzen', file), false);
        end
    end

    function profileSave()
        if ~profileTextApply()
            return;
        end
        [file, folder] = uiputfile({'*.txt', 'Temperaturprofil (*.txt)'}, 'Temperaturprofil speichern', ...
                                   fullfile(PROFILE_FOLDER, AUTO_PROFILE_FILE));
        if isequal(file, 0)
            return;
        end
        fid = fopen(fullfile(folder, file), 'w', 'n', 'UTF-8');
        if fid < 0
            profileStatus('Datei nicht schreibbar', true);
            return;
        end
        fprintf(fid, '# Temperaturprofil (eine Zeile je Zelle, Werte in °C je Schritt)\n');
        lines = profileToText(profileEdit.P);
        fprintf(fid, '%s\n', lines{:});
        fclose(fid);
        profileStatus(sprintf('gespeichert: %s', file), false);
    end

    function profileApply()
        if autoRunning()
            profileStatus('Automatik läuft - das Profil kann erst danach geändert werden', true);
            return;
        end
        % Text geaendert, aber nicht uebernommen? Dann gilt der Text.
        current = strjoin(reshape(cellstr(get(profileEdit.text, 'String')), 1, []), newline);
        if ~strcmp(strtrim(current), strjoin(profileToText(profileEdit.P), newline)) && ~profileTextApply()
            return;
        end
        if size(profileEdit.P, 2) ~= autoCellCount()
            profileStatus('Zahl der Zellen hat sich geändert - Editor schließen und neu öffnen', true);
            return;
        end
        msg = checkProfile(profileEdit.P);
        if ~isempty(msg)
            profileStatus(msg, true);
            return;
        end
        autoProfile = profileEdit.P;
        updateAutoSummary();
        profileStatus(sprintf('übernommen: %d Schritt(e)', size(autoProfile, 1)), false);
        logMsg(sprintf('Temperaturprofil übernommen: %d Schritt(e)', size(autoProfile, 1)));
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

    function s = sourceText(src, k)
        if src == PM_SOURCE_PT1000
            s = 'PT1000 am PM';
        elseif src == k
            s = 'Tab-Sensor (eigene Zelle)';
        else
            s = sprintf('FEHLER: Tab-Sensor Zelle %d', src);   % unzulaessig - aeltere MM-Firmware?
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
