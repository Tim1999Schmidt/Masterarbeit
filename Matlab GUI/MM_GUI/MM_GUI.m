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
%       Automatik : Schrittliste mit den Schritttypen Temperatur (Sollwerte je Zelle, weiter
%                   erst, wenn alle temperierten Zellen die Haltezeit lang innerhalb der
%                   Toleranz liegen, Standard: < 0,5 K fuer 5 min), Wartezeit, EIS-Messung
%                   (Ziel je Schritt, Einstellungen aus dem EIS-Panel) und Wiederholen (Block
%                   frueherer Schritte n-mal). Am Ende und bei Abbruch werden die temperierten
%                   Zellen auf 25 degC temperiert, erst dann wird die Regelung ausgeschaltet.
%                   Schrittliste als Tabelle oder Text einstellbar; alte Temperaturprofile werden
%                   beim Laden umgewandelt.
%   - Intervallmessung (nur Manuell): EIS-Messung in festen Zeitabstaenden, n-mal oder bis Abbruch
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
    MM_FIELD_RAIL_MASK   = 7;          % MM;...;<rail>;<rail mask> (Zellen im Balancing, Bit k-1 = Zelle k)
    BALANCE_RESEND_S     = 3;          % MM meldet eine andere Maske: fruehestens nach dieser Zeit erneut senden
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

    % Testmodus "Stackkonfiguration für Einzelzellmessung übernehmen" (nur Manuell): die MOSFETs
    % werden wie bei der Stackmessung geschaltet (angehakte Zellen an der Rail, auch nur die
    % gemessene Zelle allein, z. B. zum Laden ueber die Rail), Feld <cellmode> des EIS-Befehls
    CELL_MODE_ALONE           = 0;      % Standard: Zelle vom Stack getrennt
    CELL_MODE_ON_RAIL         = 1;
    CELL_RAIL_TEXT            = 'Stackkonfiguration für Einzelzellmessung übernehmen';
    CELL_RAIL_LABEL           = 'an Rail';   % Zusatz in Log, Legende und Messobjekt
    EISBEGIN_FIELD_ON_RAIL    = 10;     % EISBEGIN;target;...;stackMask;onRail
    % Automatik (Schrittliste: Temperatur, Wartezeit, EIS-Messung, Wiederholen)
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
    AUTO_PROFILE_FILE         = 'Schrittliste.txt';
    % Schritttypen der Automatik (Code in autoProgram, Text in Tabelle / Liste)
    STEP_TEMP                 = 'TEMP';
    STEP_WAIT                 = 'WAIT';
    STEP_EIS                  = 'EIS';
    STEP_REPEAT               = 'REPEAT';
    STEP_TYPES                = {STEP_TEMP, STEP_WAIT, STEP_EIS, STEP_REPEAT};
    STEP_TYPE_TEXT            = {'Temperatur', 'Wartezeit', 'EIS-Messung', 'Wiederholen'};
    STEP_KEYWORD_PATTERN      = '^\s*(\d+\s*[.):]\s*)?(temperatur|temp|t|warten|wartezeit|pause|eis|messung|eis-messung|wiederholen|wiederholung)\s*:';
    AUTO_WAIT_DEFAULT_MIN     = 5;
    AUTO_WAIT_MAX_MIN         = 7 * 24 * 60;   % eine Woche
    AUTO_REPEAT_DEFAULT       = 2;
    AUTO_REPEAT_MAX           = 1000;
    MINUTES_PER_HOUR          = 60;
    PROGRAM_SUMMARY_MAX_STEPS = 6;      % so viele Schritte zeigt die Kurzuebersicht
    % Intervallmessung (nur Manuell)
    INTERVAL_DEFAULT_MIN      = 10;
    INTERVAL_COUNT_ENDLESS    = 0;      % Anzahl 0 = bis "Abbrechen"
    INTERVAL_TICK_S           = 1;
    AUTO_ANSWER_REPEAT        = 'Wiederholen';
    AUTO_ANSWER_ABORT         = 'Automatik abbrechen';
    AUTO_ANSWER_OFF_NOW       = 'Sofort ausschalten';
    AUTO_END_TEMP_DEGC        = 25;     % nach dem letzten Schritt / bei Abbruch: erst hierhin temperieren, dann Regelung aus
    SECONDS_PER_MINUTE        = 60;
    PROFILE_T_MIN_DEGC        = 0;      % Sollwertbereich des PM (pm_regs.h: 0..5000 cdegC)
    PROFILE_T_MAX_DEGC        = 50;
    PROFILE_FIG_SIZE_PX       = [1100 640];
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
        'railLimit', 'Überstromgrenze Rail [A]';
        'stackRail', 'Stackmessung: an Rail';
        'balance', 'Balancing (ohne Messung)';
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
    % Ueberstromgrenze an der Rail je BM (Betrag, Laden und Entladen; BMIMAX, nur im RAM des BM)
    RAIL_LIMIT_DEFAULT_A = 2.0;        % Standard des BM nach Reset
    RAIL_LIMIT_MIN_A     = 0.1;
    RAIL_LIMIT_MAX_A     = 2.5;        % unter dem Messbereich des BM (ca. +-2,75 A)
    RAIL_LIMIT_RESEND_S  = 3;          % BM meldet einen anderen Wert: fruehestens nach dieser Zeit erneut senden
    STAT_BM_FIELD_IMAX   = 13;         % BM;k;...;connectZ;imax_mA

    % STATUS-Bits (bm_regs.h / pm_regs.h)
    BM_ST_EIS_BUSY = 1;  BM_ST_ERROR = 4;  BM_ST_TEMP_VALID = 8;
    BM_NUM_EIS_WITH_STACK = 2;         % BM mit zweitem TLE9010 fuer den Stack
    PM_ST_RUNNING  = 1;  PM_ST_ERROR = 2;  PM_ST_COOLING = 4;  PM_ST_TEMP_VALID = 8;

    BM_ERROR_TEXT = {'kein Fehler', 'EIS-Parameter', 'beschaeftigt', 'EIS-Kommunikation', ...
                     'CONNECT_Z passt nicht', 'Tab-Temperatursensor', 'TLE9015 ERRQ', 'Flash', ...
                     'EIS-ADC uebersteuert', 'Ueberstrom an der Rail, Laden oder Entladen (CONNECT_Z aus)'};
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
    railLimitA = zeros(1, 0);                % Ueberstromgrenze je BM [A] (Sollwert der GUI)
    railLimitSent = NaT(1, 0);               % Zeitpunkt des letzten BMIMAX je BM
    balanceSel = true(1, 0);                 % Zelle k nimmt am Balancing teil (ohne Messung an der Rail)
    balanceSent = NaT;                       % Zeitpunkt des letzten RAIL-Befehls
    bmLast     = BM_LAST_EMPTY;              % letzte Messwerte je BM (Datei, Automatik)
    pmLast     = PM_LAST_EMPTY;
    mmBusy     = false;                      % MM fuehrt gerade einen EIS-Auftrag aus
    autoProgram = struct('type', {}, 'temps', {}, 'minutes', {}, 'target', {}, 'from', {}, 'count', {});   % Schrittliste
    autoRun    = struct('state', 'IDLE', 'folder', '');   % laufende Automatik (Zustaende siehe autoTick)
    autoTimer  = [];
    intervalRun = struct('active', false, 'measuring', false);   % laufende Intervallmessung
    intervalTimer = [];
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
    pAuto = uipanel(fig, 'Title', 'Automatik: Schrittliste (Temperatur, Wartezeit, EIS-Messung, Wiederholen)', 'Units', 'normalized', ...
        'Position', get(pTemp, 'Position'), 'Visible', 'off');
    uicontrol(pAuto, 'Style', 'pushbutton', 'String', 'Schritte bearbeiten ...', 'Units', 'normalized', ...
        'Position', [0.01 0.68 0.18 0.26], 'Callback', @(~, ~) openProfileEditor());
    hAutoSummary = uicontrol(pAuto, 'Style', 'text', 'String', 'keine Schrittliste', 'Units', 'normalized', ...
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
        'TooltipString', sprintf(['Zellen mit einer Vorgabe in einem Temperaturschritt.\n' ...
                                  'Die PMs der übrigen Zellen bleiben unverändert.']));
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
        'Callback', @(~, ~) updateAutoHint());
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
    hCellRail = uicontrol(pEis, 'Style', 'checkbox', 'String', CELL_RAIL_TEXT, 'Value', 0, ...
        'Units', 'normalized', 'Position', [0.45 0.37 0.54 0.09], 'TooltipString', ...
        sprintf(['Testmodus, nur im Modus Manuell:\n' ...
                 'Einzelzellen werden NICHT vom Stack getrennt, die MOSFETs werden wie bei der\n' ...
                 'Stackmessung geschaltet: an der Rail sind die Zellen, die in der Zellenübersicht\n' ...
                 'bei "Stackmessung: an Rail" angehakt sind (Spannungsdifferenz max. 50 mV).\n' ...
                 'Die gemessene Zelle muss angehakt sein; sie darf auch allein angehakt sein,\n' ...
                 'z. B. um sie während der Messung über die Rail zu laden\n' ...
                 '(jedes BM trennt die Zelle bei |I| >= "Überstromgrenze Rail" in der Zellenübersicht).\n' ...
                 'Sind weitere Zellen angehakt, fließt ein Teil des Anregungsstroms in diese.\n' ...
                 'Bei "alle Zellen" / "alle Zellen + Stack" müssen alle Zellen angehakt sein.\n' ...
                 'Dateiname mit Zusatz "_Rail".']));
    hStart = uicontrol(pEis, 'Style', 'pushbutton', 'String', 'Messung starten', 'Units', 'normalized', 'Position', [0.45 0.22 0.26 0.14], ...
        'FontWeight', 'bold', 'Callback', @(~, ~) startEis());
    hAbort = uicontrol(pEis, 'Style', 'pushbutton', 'String', 'Abbrechen', 'Units', 'normalized', 'Position', [0.73 0.22 0.26 0.14], ...
        'Enable', 'off', 'Callback', @(~, ~) onEisAbortPressed());
    % Intervallmessung (nur Manuell): Messung von Start zu Start alle <min>, <Anzahl>-mal (0 = bis Abbrechen)
    hIntEnable = uicontrol(pEis, 'Style', 'checkbox', 'String', 'Intervall alle', 'Value', 0, 'Units', 'normalized', ...
        'Position', [0.45 0.145 0.13 0.07], 'TooltipString', ...
        sprintf(['Nur im Modus Manuell: "Messung starten" misst wiederholt in festen Zeitabständen\n' ...
                 '(von Start zu Start; dauert eine Messung länger, folgt die nächste direkt danach).\n' ...
                 'Alle Messungen landen in einem Ordner <Dateiname>_Intervall_<Zeit>. "Abbrechen" beendet die Reihe.']));
    hIntMin = uicontrol(pEis, 'Style', 'edit', 'String', num2str(INTERVAL_DEFAULT_MIN), 'Units', 'normalized', ...
        'Position', [0.58 0.145 0.06 0.07], 'TooltipString', 'Intervall in Minuten');
    uicontrol(pEis, 'Style', 'text', 'String', 'min, Anzahl:', 'Units', 'normalized', ...
        'Position', [0.645 0.145 0.10 0.06], 'HorizontalAlignment', 'left');
    hIntCount = uicontrol(pEis, 'Style', 'edit', 'String', num2str(INTERVAL_COUNT_ENDLESS), 'Units', 'normalized', ...
        'Position', [0.75 0.145 0.06 0.07], 'TooltipString', 'Zahl der Messungen, 0 = bis "Abbrechen"');
    uicontrol(pEis, 'Style', 'text', 'String', '(0 = bis Abbrechen)', 'Units', 'normalized', ...
        'Position', [0.815 0.145 0.18 0.06], 'HorizontalAlignment', 'left');
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
    % waehrend einer Intervallmessung gesperrt: Einstellungen der Messreihe und die Betriebsart
    intervalLockHandles = [hModeManual, hModeAuto, hBmAddr, hPmAddr, hListApply, hListSave, hScan, ...
                           hTarget, hFstart, hFstop, hAmp, hWave, hAvg, hMeasTime, hFolder, hFolderBtn, ...
                           hFilename, hComment, hCellRail, hIntEnable, hIntMin, hIntCount];
    intervalTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', INTERVAL_TICK_S, 'BusyMode', 'drop', ...
                          'TimerFcn', @(~, ~) intervalTick());

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
        intervalFinish(sprintf('Intervallmessung beendet (Verbindung getrennt) nach %d Messung(en)', ...
                               intervalDoneCount()));
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
        if ~isempty(intervalTimer) && isvalid(intervalTimer)
            stop(intervalTimer);
            delete(intervalTimer);
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
        % BM;k;addr;online;status;err;u_mV;i_mA;t_cdegC;numEis;progress;connectZ;imax_mA
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
        checkRailLimit(k, f);
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
            intervalOnDone(false);
        end
    end

    function onWarning(f)
        % WARN;NOADDR;BM|PM;addr  - wird nur protokolliert; der Hinweisdialog kommt aus
        % der STAT-Zeile des MM (onMmStatus), damit er auch nach dem Verbinden erscheint
        logMsg(['<<< ' strjoin(cellstr(f), ';')]);
    end

    function onMmStatus(f)
        % MM;eisBusy;i2cErrors;bmOnDefaultAddr;pmOnDefaultAddr;rail;railMask
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
        checkBalance(f);
    end

    % Start/Abbrechen der manuellen EIS-Messung: nur im Modus Manuell bedienbar
    function updateEisButtons(busy)
        mmBusy = busy;
        manual = ~isAutoMode();
        set(hStart, 'Enable', onOff(manual && ~busy && ~intervalRun.active));
        set(hAbort, 'Enable', onOff(manual && (busy || intervalRun.active)));
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
                resizeProgram();
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
        railLimitA(end + 1:numel(cfg.bmAddr)) = RAIL_LIMIT_DEFAULT_A;
        railLimitSent(end + 1:numel(cfg.bmAddr)) = NaT;
        balanceSel(end + 1:numel(cfg.bmAddr)) = true;   % neue Zellen: im Balancing
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
                elseif strcmp(key, 'railLimit') && k <= numel(cfg.bmAddr)
                    h(k) = uicontrol(pGrid, 'Style', 'edit', 'String', sprintf('%.2f', railLimitA(k)), ...
                        'Units', 'normalized', 'Position', pos, 'FontSize', GRID_FONT_SIZE, ...
                        'BackgroundColor', COLOR_VALUE, 'TooltipString', railLimitTooltip(k, NaN), ...
                        'Callback', @(src, ~) onRailLimitEdited(k, src));
                elseif strcmp(key, 'balance') && k <= numel(cfg.bmAddr)
                    h(k) = uicontrol(pGrid, 'Style', 'checkbox', 'String', 'aktiv', 'Value', balanceSel(k), ...
                        'Units', 'normalized', 'Position', pos, 'FontSize', GRID_FONT_SIZE, ...
                        'BackgroundColor', COLOR_VALUE, 'Enable', onOff(~isAutoMode()), 'TooltipString', ...
                        sprintf(['Haken gesetzt: Zelle %d ist ohne laufende Messung mit der Rail verbunden ' ...
                                 '(Ausgleich mit den anderen angehakten Zellen, Spannungsdifferenz max. 50 mV).\n' ...
                                 'Ohne Haken: Zelle %d wird von der Rail getrennt (CONNECT_Z = 0), z. B. damit\n' ...
                                 'ein Ladegerät an der Rail nur die angehakten Zellen lädt (auch eine einzelne).\n' ...
                                 'Nur im Modus Manuell änderbar, in der Automatik sind alle Zellen im Balancing.'], k, k), ...
                        'Callback', @(src, ~) onBalanceEdited(k, src));
                elseif strcmp(key, 'stackRail') && k <= numel(cfg.bmAddr)
                    h(k) = uicontrol(pGrid, 'Style', 'checkbox', 'String', 'verbunden', 'Value', stackSel(k), ...
                        'Units', 'normalized', 'Position', pos, 'FontSize', GRID_FONT_SIZE, ...
                        'BackgroundColor', COLOR_VALUE, 'TooltipString', ...
                        sprintf(['Haken gesetzt: Zelle %d ist bei der Stackmessung mit der Rail verbunden ' ...
                                 '(CONNECT_Z = 1), sonst CONNECT_Z = 0.\nGilt auch für Einzelzellmessungen ' ...
                                 'mit "%s" (EIS-Panel)'], k, CELL_RAIL_TEXT), ...
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
                setGrid({'bmAddr', 'bmState', 'u', 'i', 'tTab', 'eis', 'conz', 'railLimit', 'stackRail', 'balance'}, k, 'kein BM', COLOR_NO_BOARD);
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

    % Balancing von Zelle k ein/aus (nur Manuell)
    function onBalanceEdited(k, src)
        if isAutoMode()
            set(src, 'Value', 1);
            return;
        end
        balanceSel(k) = logical(get(src, 'Value'));
        sendBalance();
        logMsg(sprintf('Balancing %s: %s', cellLabel(k), onOffText(balanceSel(k))));
    end

    function mask = balanceMask()
        n = numel(cfg.bmAddr);
        mask = sum(bitshift(1, find(balanceSel(1:n)) - 1));
    end

    function sendBalance()
        balanceSent = datetime('now');
        sendCommand(sprintf('RAIL;1;%d', balanceMask()));
    end

    % MM meldet seine Balancing-Maske: abweichend (z. B. nach Reset des MM) -> erneut senden
    function checkBalance(f)
        if numel(f) < MM_FIELD_RAIL_MASK || isempty(cfg.bmAddr) || numel(balanceSel) < numel(cfg.bmAddr)
            return;
        end
        if str2double(f(MM_FIELD_RAIL_MASK)) ~= balanceMask() && ...
                (isnat(balanceSent) || seconds(datetime('now') - balanceSent) >= BALANCE_RESEND_S)
            sendBalance();
        end
    end

    % Ueberstromgrenze von BM k geaendert: pruefen und an das MM senden (auch waehrend einer Messung)
    function onRailLimitEdited(k, src)
        v = str2double(strrep(strtrim(get(src, 'String')), ',', '.'));
        if isnan(v) || v < RAIL_LIMIT_MIN_A || v > RAIL_LIMIT_MAX_A
            logMsg(sprintf('Überstromgrenze %s: %.2f bis %.2f A erlaubt', cellLabel(k), RAIL_LIMIT_MIN_A, RAIL_LIMIT_MAX_A));
            set(src, 'String', sprintf('%.2f', railLimitA(k)));
            return;
        end
        railLimitA(k) = v;
        set(src, 'String', sprintf('%.2f', v));
        sendRailLimit(k);
        logMsg(sprintf('Überstromgrenze %s: %.2f A (Laden und Entladen)', cellLabel(k), v));
    end

    function sendRailLimit(k)
        railLimitSent(k) = datetime('now');
        sendCommand(sprintf('BMIMAX;%d;%d', k, round(railLimitA(k) * MILLI)));
    end

    function s = railLimitTooltip(k, reportedA)
        s = sprintf(['Überstromgrenze von Zelle %d an der Rail (Betrag, Laden und Entladen):\n' ...
                     'bei |I| >= Grenze mit CONNECT_Z = 1 trennt das BM die Zelle von der Rail (BM-Fehler 9).\n' ...
                     '%.2f bis %.2f A, Standard %.2f A. Eingabe mit Enter übernehmen.'], ...
                    k, RAIL_LIMIT_MIN_A, RAIL_LIMIT_MAX_A, RAIL_LIMIT_DEFAULT_A);
        if ~isnan(reportedA)
            s = sprintf('%s\nBM meldet: %.2f A', s, reportedA);
        end
    end

    % BM meldet seine Grenze: abweichend (z. B. nach Reset von BM oder MM) -> Sollwert erneut senden
    function checkRailLimit(k, f)
        if numel(f) < STAT_BM_FIELD_IMAX || k > numel(railLimitA) || ~isfield(gridH, 'railLimit')
            return;
        end
        reportedA = str2double(f(STAT_BM_FIELD_IMAX)) / MILLI;
        h = gridH.railLimit(k);
        matches = abs(reportedA - railLimitA(k)) < 1 / MILLI;
        color = COLOR_VALUE;
        if ~matches
            color = COLOR_STATE_ACTIVE;
        end
        set(h, 'BackgroundColor', color, 'TooltipString', railLimitTooltip(k, reportedA));
        if ~matches && (isnat(railLimitSent(k)) || ...
                        seconds(datetime('now') - railLimitSent(k)) >= RAIL_LIMIT_RESEND_S)
            sendRailLimit(k);
        end
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
        % Testmodus Stackkonfiguration: nur Manuell und nur fuer Messungen mit Einzelzellen
        job.cellMode = CELL_MODE_ALONE;
        if ~isAutoMode() && get(hCellRail, 'Value') == 1 && ~strcmp(job.target, 'S')
            if isempty(selected)
                logMsg(['Stackkonfiguration: mindestens eine Zelle muss bei "Stackmessung: an Rail" ' ...
                        'angehakt sein']);
                return;
            end
            if sel <= n && ~stackSel(sel)
                logMsg(sprintf('Stackkonfiguration: %s ist bei "Stackmessung: an Rail" nicht angehakt', cellLabel(sel)));
                return;
            end
            if sel > n && numel(selected) < n
                logMsg(['Stackkonfiguration: bei "alle Zellen" müssen alle Zellen bei "Stackmessung: an Rail" ' ...
                        'angehakt sein, nicht angehakt: ' cellList(setdiff(1:n, selected))]);
                return;
            end
            job.cellMode = CELL_MODE_ON_RAIL;
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
                                'stackCells', strjoin(arrayfun(@num2str, selected, 'UniformOutput', false), ', '), ...
                                'cellMode', job.cellMode);
        job.info = info;
        ok = true;
    end

    function sendEis(target, job)
        sendCommand(sprintf('EIS;%s;%d;%d;%d;%d;%d;%d;%d;%d', target, job.fStart, job.fStop, ...
                            job.ampIndex, job.waveIndex, job.averages, job.timeIndex, job.stackMask, job.cellMode));
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
        if get(hIntEnable, 'Value') == 1 && ~isAutoMode()
            startInterval(job);                      % Messreihe in festen Zeitabstaenden
            return;
        end
        beginJob(job.info);
        sendEis(job.target, job);
    end

    function onEisBegin(f)
        % EISBEGIN;target;fstart;fstop;amp;wave;avg;time;stackMask;onRail
        t = char(f(2));
        m.target = t;
        m.onRail = numel(f) >= EISBEGIN_FIELD_ON_RAIL && ...
                   str2double(f(EISBEGIN_FIELD_ON_RAIL)) == CELL_MODE_ON_RAIL;   % nur Einzelzellen
        m.cells  = zeros(0, 3);          % [BM, U mV, T degC]
        m.data   = zeros(0, 4);          % [Index, f Hz, Re uOhm, Im uOhm]
        m.pm     = pmLast;
        m.start  = datetime('now');
        meas(t) = m;
        updateEisButtons(true);
        autoOnEisBegin();
        set(hProgress, 'String', sprintf('%s: Messung gestartet', measLabel(t)));
        logMsg(sprintf('EIS %s gestartet', measLabel(t)));
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
            set(hProgress, 'String', sprintf('%s: Frequenz %d von %d (%.2f Hz)', measLabel(t), ...
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
            plotHandles(t) = plot(ax, re, -im, '-o', 'DisplayName', measLabel(t));
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
            file = EIS_Textdatei_schreiben(meas(t), jobInfo, measLabel(t));
            annotateFrequencies(t);
            logMsg(sprintf('EIS %s fertig: %s', measLabel(t), file));
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
            logMsg(sprintf('EIS %s fehlgeschlagen: %s', measLabel(t), reason));
            autoOnEisResult(t, false, reason);
        end
    end

    function onEisDone(f)
        % EISDONE;ok;total
        updateEisButtons(false);
        set(hProgress, 'String', sprintf('Messauftrag beendet: %s von %s erfolgreich', f(2), f(3)));
        logMsg(get(hProgress, 'String'));
        autoOnEisDone();
        intervalOnDone(f(2) == f(3));
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
            set(hCellRail, 'Value', 0);              % Automatik misst Einzelzellen immer getrennt
        end
        set(hCellRail, 'Enable', onOff(~auto));
        set([hIntEnable, hIntMin, hIntCount], 'Enable', onOff(~auto));   % Intervallmessung nur Manuell
        % Balancing: in der Automatik immer alle Zellen
        if isfield(gridH, 'balance')
            hb = gridH.balance(1:min(numel(gridH.balance), numel(cfg.bmAddr)));
            if auto && ~all(balanceSel)
                balanceSel(:) = true;
                set(hb, 'Value', 1);
                if ~isempty(device)
                    sendBalance();
                end
                logMsg('Automatik: Balancing für alle Zellen eingeschaltet');
            end
            set(hb, 'Enable', onOff(~auto));
        end
        if auto
            resizeProgram();
            logMsg('Betriebsart: Automatik');
        else
            logMsg('Betriebsart: Manuell');
        end
    end

    %% =========================================================================
    %  Automatik: Ablaufsteuerung (Schrittliste)
    %  =========================================================================
    % Die Automatik arbeitet eine Schrittliste (autoProgram) ab. Schritttypen:
    %   TEMP    Solltemperaturen setzen (je Zelle, leer = unveraendert) und warten, bis alle
    %           temperierten Zellen die Haltezeit lang innerhalb der Toleranz liegen
    %   WAIT    feste Wartezeit (die Temperaturregelung laeuft weiter)
    %   EIS     EIS-Messung (Ziel je Schritt, alle anderen Einstellungen aus dem EIS-Panel)
    %   REPEAT  die Schritte ab Schritt <from> bis zum Schritt davor insgesamt <count>-mal
    % Zustaende (autoRun.state), geprueft im Takt AUTO_TICK_S (autoTick):
    %   IDLE    keine Automatik
    %   TEMP    Temperaturschritt: warten auf stabile Temperatur
    %   DELAY   Wartezeit laeuft
    %   MEAS    EIS-Auftrag(e) des Schritts laufen (Ende ueber EISDONE bzw. ERR;EIS)
    %   ASK     ein Auftrag ist fehlgeschlagen -> Dialog im naechsten Takt
    %   ASKING  Dialog offen (Wiederholen / Automatik abbrechen)
    %   RETURN  Ende oder Abbruch: temperierte Zellen auf AUTO_END_TEMP_DEGC zuruecktemperieren;
    %           sobald alle innerhalb der Toleranz liegen, wird die Temperaturregelung
    %           ausgeschaltet (die Zelle soll nicht lange ungeregelt bei hoher Temperatur
    %           bleiben -> Alterung)
    % Temperiert werden koennen die Zellen 1..min(Anzahl BM, Anzahl PM) (Zellen mit BM und PM).

    function n = autoCellCount()
        n = min(numel(cfg.bmAddr), numel(cfg.pmAddr));
    end

    % Zellen, die in einem Temperaturschritt der Schrittliste eine Vorgabe haben
    function cells = programTempCells(P)
        cells = [];
        for i = 1:numel(P)
            if strcmp(P(i).type, STEP_TEMP)
                cells = union(cells, find(~isnan(P(i).temps)));
            end
        end
        cells = reshape(cells, 1, []);
    end

    function updateAutoHint()
        cells = programTempCells(autoProgram);
        if isempty(cells)
            set(hAutoHint, 'String', 'Temperiert: -');
        else
            set(hAutoHint, 'String', ['Temperiert: ' cellList(cells)]);
        end
    end

    function running = autoRunning()
        running = ~strcmp(autoRun.state, 'IDLE');
    end

    % Schrittliste an die Zahl der Zellen anpassen (Temperaturvorgaben neuer Zellen: leer)
    function resizeProgram()
        n = autoCellCount();
        if autoRunning()
            updateAutoSummary();
            return;
        end
        if isempty(autoProgram) && n > 0                 % Standard: alle Zellen 25 degC, dann alle messen
            autoProgram = [newStep(STEP_TEMP, n), newStep(STEP_EIS, n)];
        end
        for i = 1:numel(autoProgram)
            t = autoProgram(i).temps;
            if numel(t) < n
                t(end + 1:n) = NaN;
            end
            autoProgram(i).temps = t(1:n);
        end
        updateAutoSummary();
    end

    function updateAutoSummary()
        if isempty(autoProgram)
            set(hAutoSummary, 'String', 'keine Schrittliste - mit "Schritte bearbeiten ..." anlegen', 'TooltipString', '');
            updateAutoHint();
            return;
        end
        txt = arrayfun(@(i) sprintf('%d %s', i, stepShortText(autoProgram(i))), 1:numel(autoProgram), 'UniformOutput', false);
        if numel(txt) > PROGRAM_SUMMARY_MAX_STEPS
            txt = [txt(1:PROGRAM_SUMMARY_MAX_STEPS), {'...'}];
        end
        set(hAutoSummary, 'String', sprintf('%d Schritt(e):  %s', numel(autoProgram), strjoin(txt, '  →  ')), ...
            'TooltipString', strjoin(programToText(autoProgram), newline));
        updateAutoHint();
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
        msg = checkProgram(autoProgram, numel(cfg.bmAddr), n);
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
        [job, ok] = readEisJob();                % Einstellungen des EIS-Panels (Ziel je Schritt)
        if ~ok
            return;
        end
        targets = {autoProgram(strcmp({autoProgram.type}, STEP_EIS)).target};
        if any(ismember(targets, {'S', 'ALLS'})) && job.stackMask == 0
            logMsg('Automatik: Stackmessung in der Schrittliste - mindestens eine Zelle muss bei "Stackmessung: an Rail" angehakt sein');
            return;
        end
        folder = fullfile(job.info.folder, sprintf('%s_Automatik_%s', job.info.baseName, ...
                          char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'))));
        [created, mkMsg] = mkdir(folder);
        if ~created
            logMsg(['Automatik: Ordner nicht anlegbar: ' mkMsg]);
            return;
        end

        autoRun = struct('state', 'IDLE', 'folder', folder, 'program', autoProgram, 'n', n, 'pc', 0, ...
                         'repeatDone', zeros(1, numel(autoProgram)), 'setpoints', nan(1, n), 'cells', [], ...
                         'tol', tol, 'holdS', holdMin * SECONDS_PER_MINUTE, ...
                         'criterion', get(hAutoCrit, 'Value'), 'job', job, ...
                         'stableSince', NaT, 'stepStart', NaT, 'waitUntil', NaT, 'queue', {{}}, 'failed', {{}}, ...
                         'sentTarget', '', 'sentAt', NaT, 'eisBegun', false, 'eisCount', 0);
        writeProfileFile(fullfile(folder, AUTO_PROFILE_FILE), autoRun);
        autoLog(sprintf('gestartet: %d Schritt(e), Toleranz %.2f K, Haltezeit %g min, Kriterium %s, Ordner %s', ...
                        numel(autoProgram), tol, holdMin, AUTO_CRITERION_TEXT{autoRun.criterion}, folder));
        setAutoLock(true);
        autoRunStep(1);
        if autoRunning() && ~isRunning(autoTimer)
            start(autoTimer);
        end
    end

    function setAutoLock(locked)
        set(autoLockHandles, 'Enable', onOff(~locked));
        set(hAutoStart, 'Enable', onOff(~locked));
        set(hAutoStop, 'Enable', onOff(locked));
    end

    % fuehrt die Schrittliste ab Schritt pc aus, bis ein Schritt Zeit braucht (Temperatur,
    % Wartezeit, Messung); Wiederholungsschritte springen sofort zurueck
    function autoRunStep(pc)
        P = autoRun.program;
        while true
            if pc > numel(P)
                autoFinish();
                return;
            end
            autoRun.pc = pc;
            st = P(pc);
            switch st.type
                case STEP_REPEAT
                    done = autoRun.repeatDone(pc) + 1;          % abgeschlossene Durchlaeufe des Blocks
                    if done < st.count
                        autoRun.repeatDone(pc) = done;
                        autoRun.repeatDone(st.from:pc - 1) = 0; % innere Wiederholungen beginnen neu
                        autoLog(sprintf('Schritt %d: Durchlauf %d/%d beendet, weiter mit Schritt %d', ...
                                        pc, done, st.count, st.from));
                        pc = st.from;
                    else
                        autoRun.repeatDone(pc) = 0;             % falls ein aeusserer Block erneut kommt
                        autoLog(sprintf('Schritt %d: alle %d Durchläufe beendet', pc, st.count));
                        pc = pc + 1;
                    end
                case STEP_TEMP
                    autoEnterTempStep(st);
                    return;
                case STEP_WAIT
                    autoRun.state     = 'DELAY';
                    autoRun.stepStart = datetime('now');
                    autoRun.waitUntil = autoRun.stepStart + minutes(st.minutes);
                    autoLog(sprintf('Schritt %d/%d%s: Wartezeit %s', pc, numel(P), loopText(pc), minSec(st.minutes * SECONDS_PER_MINUTE)));
                    autoCheckDelay();
                    return;
                case STEP_EIS
                    autoStartMeasurement(st.target);
                    return;
            end
        end
    end

    function autoAdvance()
        autoRunStep(autoRun.pc + 1);
    end

    % Sollwerte des Schritts an die PMs, Regelung einschalten, auf stabile Temperatur warten
    function autoEnterTempStep(st)
        set_ = find(~isnan(st.temps));
        autoRun.setpoints(set_) = st.temps(set_);
        autoRun.cells       = union(autoRun.cells, set_);
        autoRun.cells       = reshape(autoRun.cells, 1, []);
        autoRun.state       = 'TEMP';
        autoRun.stableSince = NaT;
        autoRun.stepStart   = datetime('now');
        for k = set_
            sendCommand(sprintf('PMSET;%d;%d', k, round(st.temps(k) * CENTI)));
            sendCommand(sprintf('PMSTART;%d', k));
        end
        autoLog(sprintf('Schritt %d/%d%s: Solltemperaturen %s', autoRun.pc, autoStepCount(), loopText(autoRun.pc), ...
                        setpointText(autoRun.cells)));
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d: Sollwerte gesetzt (%s)', autoRun.pc, autoStepCount(), ...
            setpointText(autoRun.cells)), 'ForegroundColor', 'k');
    end

    function r = isRunning(t)
        r = ~isempty(t) && isvalid(t) && strcmp(get(t, 'Running'), 'on');
    end

    function n = autoStepCount()
        n = numel(autoRun.program);
    end

    % Zusatz "(Durchlauf x/n)" fuer alle Wiederholungsbloecke, in denen Schritt pc liegt
    function s = loopText(pc)
        s = '';
        P = autoRun.program;
        for r = pc + 1:numel(P)
            if strcmp(P(r).type, STEP_REPEAT) && P(r).from <= pc
                s = sprintf('%s, Durchlauf %d/%d', s, autoRun.repeatDone(r) + 1, P(r).count);
            end
        end
        if ~isempty(s)
            s = [' (' s(3:end) ')'];
        end
    end

    function s = setpointText(cells)
        if isempty(cells)
            s = 'keine Zelle temperiert';
            return;
        end
        s = strjoin(arrayfun(@(k) sprintf('Z%d %g °C', k, autoRun.setpoints(k)), cells, 'UniformOutput', false), ', ');
    end

    function autoTick()
        if ~isvalid(fig)
            return;
        end
        try
            switch autoRun.state
                case 'TEMP',   autoCheckTemperatures();
                case 'DELAY',  autoCheckDelay();
                case 'MEAS',   autoCheckEisStart();
                case 'ASK',    autoAskRepeat();
                case 'RETURN', autoCheckReturn();
            end
        catch ex
            logMsg(['Automatik: ' ex.message]);
        end
    end

    % Abweichung jeder temperierten Zelle von ihrer Solltemperatur; problem = Grund, warum die
    % Bedingung gerade nicht pruefbar ist (Board offline, Wert ungueltig, Sollwert nicht uebernommen)
    % temps: Solltemperaturen aller Zellen; dev: je temperierte Zelle (autoRun.cells)
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
        pc = autoRun.pc;
        nowT = datetime('now');
        [dev, problem] = autoDeviations(autoRun.setpoints, nowT);
        inTol = isempty(problem) && all(abs(dev) < autoRun.tol);
        if inTol
            if isnat(autoRun.stableSince)
                autoRun.stableSince = nowT;
                autoLog(sprintf('Schritt %d: alle temperierten Zellen innerhalb ±%.2f K', pc, autoRun.tol), false);
            end
            held = seconds(nowT - autoRun.stableSince);
        else
            if ~isnat(autoRun.stableSince)
                autoLog(sprintf('Schritt %d: Toleranz verlassen (Abweichungen %s K)', pc, deviationList(dev)), false);
            end
            autoRun.stableSince = NaT;
            held = 0;
        end

        status = sprintf('Schritt %d/%d%s Temperatur (%s): warte %s, stabil %s von %s, Abweichung %s K', ...
            pc, autoStepCount(), loopText(pc), setpointText(autoRun.cells), minSec(seconds(nowT - autoRun.stepStart)), ...
            minSec(held), minSec(autoRun.holdS), deviationList(dev));
        color = 'k';
        if ~isempty(problem)
            status = [status ' - ' problem];
            color = COLOR_TEXT_ERROR;
        end
        set(hAutoStatus, 'String', status, 'TooltipString', status, 'ForegroundColor', color);

        if inTol && held >= autoRun.holdS
            autoLog(sprintf('Schritt %d: Temperatur %s gehalten (Wartezeit gesamt %s)', ...
                            pc, minSec(autoRun.holdS), minSec(seconds(nowT - autoRun.stepStart))));
            autoAdvance();
        end
    end

    function autoCheckDelay()
        nowT = datetime('now');
        status = sprintf('Schritt %d/%d%s Wartezeit: noch %s von %s', autoRun.pc, autoStepCount(), loopText(autoRun.pc), ...
            minSec(seconds(autoRun.waitUntil - nowT)), minSec(seconds(autoRun.waitUntil - autoRun.stepStart)));
        if ~isempty(autoRun.cells)
            dev = autoDeviations(autoRun.setpoints, nowT);
            status = sprintf('%s, Abweichung %s K', status, deviationList(dev));
        end
        set(hAutoStatus, 'String', status, 'TooltipString', status, 'ForegroundColor', 'k');
        if nowT >= autoRun.waitUntil
            autoLog(sprintf('Schritt %d: Wartezeit abgelaufen', autoRun.pc), false);
            autoAdvance();
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

    function autoStartMeasurement(target)
        autoRun.eisCount = autoRun.eisCount + 1;
        if target(1) == 'C'
            measured = str2double(target(2:end));
        else
            measured = 1:numel(cfg.bmAddr);
        end
        measured = measured(measured <= autoRun.n);
        info = autoRun.job.info;
        info.folder    = autoRun.folder;
        info.baseName  = sprintf('%s_M%03d_S%02d%s', autoRun.job.info.baseName, autoRun.eisCount, autoRun.pc, ...
                                 temperatureSuffix(autoRun.setpoints(measured)));
        info.comment   = strtrim(sprintf('%s [Automatik Schritt %d/%d%s, Messung %d, T Soll %s]', autoRun.job.info.comment, ...
                                         autoRun.pc, autoStepCount(), loopText(autoRun.pc), autoRun.eisCount, ...
                                         setpointText(autoRun.cells)));
        info.cellNames = cellNames;
        beginJob(info);
        autoRun.queue  = {target};
        autoRun.failed = {};
        autoRun.state  = 'MEAS';
        autoLog(sprintf('Schritt %d/%d%s: EIS-Messung %s (Messung %d)', autoRun.pc, autoStepCount(), loopText(autoRun.pc), ...
                        autoTargetText(target), autoRun.eisCount));
        autoSendNext();
    end

    function autoSendNext()
        autoRun.sentTarget = autoRun.queue{1};
        autoRun.queue(1)   = [];
        autoRun.eisBegun   = false;
        autoRun.sentAt     = datetime('now');
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d%s: EIS-Messung %s', autoRun.pc, autoStepCount(), ...
            loopText(autoRun.pc), autoTargetText(autoRun.sentTarget)), 'ForegroundColor', 'k');
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
            autoLog(sprintf('Schritt %d: EIS %s gespeichert: %s', autoRun.pc, autoTargetText(target), detail), false);
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
        autoLog(sprintf('Schritt %d: EIS %s fehlgeschlagen: %s', autoRun.pc, autoTargetText(target), reason));
    end

    % ein Auftrag ist fertig: naechster aus der Warteschlange, sonst naechster Schritt
    function autoAfterTarget()
        if ~isempty(autoRun.queue)
            autoSendNext();
        elseif isempty(autoRun.failed)
            autoLog(sprintf('Schritt %d/%d abgeschlossen', autoRun.pc, autoStepCount()), false);
            autoAdvance();
        else
            autoRun.state = 'ASK';          % Dialog im naechsten Takt, nicht im Empfangs-Callback
        end
    end

    function autoAskRepeat()
        autoRun.state = 'ASKING';
        failedText = strjoin(cellfun(@autoTargetText, unique(autoRun.failed, 'stable'), 'UniformOutput', false), ', ');
        set(hAutoStatus, 'String', sprintf('Schritt %d/%d: EIS fehlgeschlagen (%s) - Entscheidung nötig', ...
            autoRun.pc, autoStepCount(), failedText), 'ForegroundColor', COLOR_TEXT_ERROR);
        answer = questdlg(sprintf(['Schritt %d/%d: Die EIS-Messung von %s ist fehlgeschlagen (Grund im Log).\n\n' ...
                                   '%s: nur die fehlgeschlagenen Messungen erneut starten, die Temperatur wird gehalten.\n' ...
                                   '%s: Automatik beenden, Zellen auf %g °C temperieren, danach Temperaturregelung aus.'], ...
                                  autoRun.pc, autoStepCount(), failedText, AUTO_ANSWER_REPEAT, AUTO_ANSWER_ABORT, ...
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
                autoLog(sprintf('Schritt %d: Wiederholung von %s', autoRun.pc, failedText));
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
        autoLog(sprintf('Schrittliste abgeschlossen (%d EIS-Messung(en))', autoRun.eisCount));
        autoReturnToEndTemp(sprintf('Automatik abgeschlossen (%d Messung(en))', autoRun.eisCount), COLOR_TEXT_OK);
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
                                autoRun.pc, autoStepCount(), reason, AUTO_END_TEMP_DEGC));
                autoCleanup(sprintf('Automatik abgebrochen (%s) - PMs regeln auf %g °C', reason, AUTO_END_TEMP_DEGC), COLOR_TEXT_ERROR);
            otherwise
                autoLog(sprintf('abgebrochen in Schritt %d/%d: %s', autoRun.pc, autoStepCount(), reason));
                autoReturnToEndTemp(sprintf('Automatik abgebrochen (%s)', reason), COLOR_TEXT_ERROR);
        end
    end

    function autoSetEndTemp()
        for k = autoRun.cells
            sendCommand(sprintf('PMSET;%d;%d', k, round(AUTO_END_TEMP_DEGC * CENTI)));
            sendCommand(sprintf('PMSTART;%d', k));
        end
    end

    % temperierte Zellen auf die Endtemperatur bringen; autoCheckReturn schaltet danach die Regelung aus
    function autoReturnToEndTemp(summary, color)
        autoRun.state      = 'RETURN';
        autoRun.endSummary = summary;
        autoRun.endColor   = color;
        autoRun.stepStart  = datetime('now');
        autoSetEndTemp();
        if ~isempty(autoRun.cells)
            autoLog(sprintf('Zellen werden auf %g °C temperiert, danach wird die Temperaturregelung ausgeschaltet', AUTO_END_TEMP_DEGC));
        end
        set(hAutoStop, 'String', 'Temperierung sofort aus');
        if ~isRunning(autoTimer)
            start(autoTimer);
        end
    end

    function autoCheckReturn()
        nowT = datetime('now');
        temps = AUTO_END_TEMP_DEGC * ones(1, autoRun.n);
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
            if isempty(autoRun.cells)
                autoCleanup(autoRun.endSummary, autoRun.endColor);
                return;
            end
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
            logMsg(['Automatik: Datei der Schrittliste nicht schreibbar: ' filePath]);
            return;
        end
        s = run.job.info.settings;
        fprintf(fid, '# Schrittliste der Automatik\n');
        fprintf(fid, '# Start: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        fprintf(fid, '# Toleranz: %.2f K, Haltezeit: %g min, Kriterium: %s\n', run.tol, ...
                run.holdS / SECONDS_PER_MINUTE, AUTO_CRITERION_TEXT{run.criterion});
        fprintf(fid, '# EIS-Einstellungen: Frequenzindex %d..%d, Amplitude %s, Signalform %s, Mittelung %d, Messdauer %s\n', ...
                s.fStart, s.fStop, s.amplitude, s.waveform, s.averages, s.measTime);
        lines = programToText(run.program);
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

    function s = deviationList(dev)
        s = strjoin(arrayfun(@(x) sprintf('%+.2f', x), dev, 'UniformOutput', false), ' / ');
    end

    % Dateinamenszusatz: _22_5C, wenn alle gemessenen Zellen dieselbe Solltemperatur haben
    function s = temperatureSuffix(temps)
        s = '';
        if ~isempty(temps) && ~any(isnan(temps)) && all(temps == temps(1))
            s = ['_' strrep(sprintf('%g', temps(1)), '.', '_') 'C'];
        end
    end

    function s = minSec(sec)
        sec = max(0, floor(sec));
        s = sprintf('%d:%02d', floor(sec / SECONDS_PER_MINUTE), mod(sec, SECONDS_PER_MINUTE));
    end

    %% =========================================================================
    %  Schrittliste: Text <-> Struktur
    %  =========================================================================
    % Textformat: ein Schritt je Zeile (eine fuehrende Nummer "3." wird ignoriert, Zeilen mit
    % '#' sind Kommentare, Dezimalpunkt):
    %   Temperatur: Zelle 1 = 25, Zelle 2 = 35     (nicht genannte Zellen: unveraendert)
    %   Temperatur: alle = 25
    %   Warten: 5 min                              (auch "30 s" oder "1.5 h")
    %   EIS: alle Zellen                           (Zelle k, Stack, alle Zellen, alle Zellen + Stack)
    %   Wiederholen: ab Schritt 6, insgesamt 13-mal (Schritte 6 bis zum Schritt davor)
    % Alte Temperaturprofile ("Zelle 1: 25, 15, 5") werden beim Einlesen umgewandelt:
    % je Profilschritt ein Temperaturschritt und eine EIS-Messung (Ziel aus dem EIS-Panel).

    function st = newStep(type, n)
        st = struct('type', type, 'temps', nan(1, n), 'minutes', NaN, 'target', '', 'from', NaN, 'count', NaN);
        switch type
            case STEP_TEMP,   st.temps = DEFAULT_TSET_DEGC * ones(1, n);
            case STEP_WAIT,   st.minutes = AUTO_WAIT_DEFAULT_MIN;
            case STEP_EIS,    st.target = 'ALL';
            case STEP_REPEAT, st.from = 1;  st.count = AUTO_REPEAT_DEFAULT;
        end
    end

    function lines = programToText(P)
        lines = arrayfun(@(i) sprintf('%d. %s', i, stepToText(P(i))), 1:numel(P), 'UniformOutput', false);
    end

    function s = stepToText(st)
        switch st.type
            case STEP_TEMP
                set_ = find(~isnan(st.temps));
                if ~isempty(set_) && numel(set_) == numel(st.temps) && all(st.temps == st.temps(1))
                    s = sprintf('Temperatur: alle = %g', st.temps(1));
                else
                    s = ['Temperatur: ' strjoin(arrayfun(@(k) sprintf('Zelle %d = %g', k, st.temps(k)), set_, ...
                                                         'UniformOutput', false), ', ')];
                end
            case STEP_WAIT
                s = sprintf('Warten: %g min', st.minutes);
            case STEP_EIS
                s = ['EIS: ' autoTargetText(st.target)];
            case STEP_REPEAT
                s = sprintf('Wiederholen: ab Schritt %d, insgesamt %d-mal', st.from, st.count);
            otherwise
                s = '?';
        end
    end

    function s = stepShortText(st)
        switch st.type
            case STEP_TEMP
                set_ = find(~isnan(st.temps));
                s = ['T ' strjoin(arrayfun(@(k) sprintf('%g', st.temps(k)), set_, 'UniformOutput', false), '/') ' °C'];
            case STEP_WAIT,   s = sprintf('%g min', st.minutes);
            case STEP_EIS,    s = ['EIS ' autoTargetText(st.target)];
            case STEP_REPEAT, s = sprintf('ab %d ×%d', st.from, st.count);
            otherwise,        s = '?';
        end
    end

    % nBm: Zahl der BMs (EIS-Ziele), n: Zahl der Zellen mit BM und PM (Temperaturvorgaben)
    function [P, msg] = parseProgramText(txt, nBm, n)
        P = struct('type', {}, 'temps', {}, 'minutes', {}, 'target', {}, 'from', {}, 'count', {});
        msg = '';
        if ischar(txt)
            txt = cellstr(txt);                          % mehrzeiliges Edit-Feld: Zeichenmatrix
        end
        txt = splitlines(strjoin(reshape(cellstr(txt), 1, []), newline));
        lines = {};
        for i = 1:numel(txt)
            line = strtrim(txt{i});
            if ~isempty(line) && line(1) ~= '#'
                lines{end + 1} = line; %#ok<AGROW>
            end
        end
        if isempty(lines)
            msg = 'Schrittliste ist leer';
            return;
        end
        if isempty(regexpi(strjoin(lines, newline), STEP_KEYWORD_PATTERN, 'once', 'lineanchors'))
            [P, msg] = convertOldProfile(lines, nBm, n);     % altes Temperaturprofil
            return;
        end
        for i = 1:numel(lines)
            line = regexprep(lines{i}, '^\d+\s*[.):]\s*', '');   % fuehrende Schrittnummer
            colon = strfind(line, ':');
            if isempty(colon)
                msg = sprintf('Zeile "%s": Schritttyp fehlt (Temperatur:, Warten:, EIS:, Wiederholen:)', lines{i});
                return;
            end
            key  = lower(strtrim(line(1:colon(1) - 1)));
            rest = strtrim(line(colon(1) + 1:end));
            switch key
                case {'temperatur', 'temp', 't'}
                    [st, err] = parseTempStep(rest, n);
                case {'warten', 'wartezeit', 'pause'}
                    [st, err] = parseWaitStep(rest, n);
                case {'eis', 'messung', 'eis-messung'}
                    [st, err] = parseEisStep(rest, nBm, n);
                case {'wiederholen', 'wiederholung'}
                    [st, err] = parseRepeatStep(rest, n);
                otherwise
                    err = sprintf('Schritttyp "%s" unbekannt', key);
            end
            if ~isempty(err)
                msg = sprintf('Zeile "%s": %s', lines{i}, err);
                return;
            end
            P(end + 1) = st; %#ok<AGROW>
        end
        msg = checkProgram(P, nBm, n);
    end

    function [st, err] = parseTempStep(rest, n)
        st = newStep(STEP_TEMP, n);
        st.temps = nan(1, n);
        err = '';
        parts = strtrim(regexp(rest, '[,;]', 'split'));
        parts = parts(~cellfun(@isempty, parts));
        pos = 0;                                         % Zaehler fuer Werte ohne Zellangabe
        for p = 1:numel(parts)
            item = parts{p};
            eq = strfind(item, '=');
            if isempty(eq)
                pos = pos + 1;
                cells = pos;
                value = item;
            else
                label = lower(strtrim(item(1:eq(1) - 1)));
                value = item(eq(1) + 1:end);
                if ~isempty(regexp(label, '^(alle|all)$', 'once'))
                    cells = 1:n;
                else
                    tok = regexp(label, '^(?:zelle|z)\s*(\d+)$', 'tokens', 'once');
                    if isempty(tok)
                        err = sprintf('"%s" nicht erkannt (z. B. "Zelle 1 = 25" oder "alle = 25")', item);
                        return;
                    end
                    cells = str2double(tok{1});
                end
            end
            value = strtrim(regexprep(value, '°?\s*C$', ''));
            if strcmp(value, '-')
                continue;                                % Zelle bleibt unveraendert
            end
            v = str2double(value);
            if isnan(v)
                err = sprintf('"%s": keine Zahl', item);
                return;
            end
            if any(cells < 1 | cells > n)
                err = sprintf('nur Zelle 1 bis %d haben BM und PM', n);
                return;
            end
            st.temps(cells) = v;
        end
    end

    function [st, err] = parseWaitStep(rest, n)
        st = newStep(STEP_WAIT, n);
        err = '';
        tok = regexpi(rest, '^([\d.]+)\s*(min|m|s|sek|h|std)?\.?$', 'tokens', 'once');
        if isempty(tok)
            err = 'Wartezeit nicht erkannt (z. B. "5 min", "30 s", "1.5 h")';
            return;
        end
        v = str2double(tok{1});
        switch lower(tok{2})
            case {'s', 'sek'},  v = v / SECONDS_PER_MINUTE;
            case {'h', 'std'},  v = v * MINUTES_PER_HOUR;
        end
        st.minutes = v;
    end

    function [st, err] = parseEisStep(rest, nBm, n)
        st = newStep(STEP_EIS, n);
        err = '';
        r = lower(regexprep(strtrim(rest), '\s+', ' '));
        tok = regexp(r, '^(?:zelle|z)\s*(\d+)$', 'tokens', 'once');
        if ~isempty(tok)
            k = str2double(tok{1});
            if k < 1 || k > nBm
                err = sprintf('es gibt nur Zelle 1 bis %d', nBm);
                return;
            end
            st.target = sprintf('C%d', k);
        elseif strcmp(r, 'stack')
            st.target = 'S';
        elseif ~isempty(regexp(r, '^(alle( zellen)? ?\+ ?stack|alls)$', 'once'))
            st.target = 'ALLS';
        elseif ~isempty(regexp(r, '^(alle( zellen)?|all)$', 'once'))
            st.target = 'ALL';
        else
            err = 'Ziel nicht erkannt (Zelle k, Stack, alle Zellen, alle Zellen + Stack)';
        end
    end

    function [st, err] = parseRepeatStep(rest, n)
        st = newStep(STEP_REPEAT, n);
        err = '';
        nums = str2double(regexp(rest, '\d+', 'match'));
        if numel(nums) ~= 2
            err = 'erwartet: "ab Schritt <Nr>, insgesamt <Anzahl>-mal"';
            return;
        end
        st.from  = nums(1);
        st.count = nums(2);
    end

    % altes Format (eine Zeile je Zelle) -> je Profilschritt Temperatur + EIS (Ziel aus dem EIS-Panel)
    function [P, msg] = convertOldProfile(lines, nBm, n)
        P = struct('type', {}, 'temps', {}, 'minutes', {}, 'target', {}, 'from', {}, 'count', {});
        [T, msg] = parseOldProfileText(lines, n);
        if ~isempty(msg)
            msg = ['weder Schrittliste noch altes Temperaturprofil: ' msg];
            return;
        end
        target = panelTarget();
        for s = 1:size(T, 1)
            st = newStep(STEP_TEMP, n);
            st.temps = T(s, :);
            P(end + 1) = st; %#ok<AGROW>
            st = newStep(STEP_EIS, n);
            st.target = target;
            P(end + 1) = st; %#ok<AGROW>
        end
        msg = checkProgram(P, nBm, n);
    end

    % EIS-Ziel, das im EIS-Panel unter "Messung" gewaehlt ist
    function t = panelTarget()
        nBm = numel(cfg.bmAddr);
        sel = get(hTarget, 'Value');
        if sel <= nBm
            t = sprintf('C%d', sel);
        elseif sel == nBm + 1
            t = 'S';
        elseif sel == nBm + 2
            t = 'ALL';
        else
            t = 'ALLS';
        end
    end

    % altes Temperaturprofil: "Zelle 1: 25, 15, 5" / "alle: 25, 15" / Zeile ohne Bezeichnung
    function [P, msg] = parseOldProfileText(lines, n)
        P = [];  msg = '';
        cols = cell(1, n);
        nextCol = 1;
        for i = 1:numel(lines)
            line = lines{i};
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
                msg = sprintf('Zeile "%s" nicht erkannt', line);
                return;
            end
            if isempty(label)
                targets = nextCol;
            elseif ~isempty(regexpi(label, '^(alle|all)\>', 'once'))
                targets = 1:n;
            else
                tok = regexpi(label, '^(?:zelle|cell|z)\s*(\d+)', 'tokens', 'once');
                if isempty(tok)
                    msg = sprintf('Zeile "%s": Bezeichnung nicht erkannt', line);
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
        missing = cellfun(@isempty, cols);
        if all(missing)
            msg = 'keine Werte';
            return;
        end
        len = max(cellfun(@numel, cols));
        for c = find(missing)
            cols{c} = nan(len, 1);                       % Zelle ohne Zeile: nicht temperiert
        end
        if any(cellfun(@numel, cols) ~= len)
            msg = 'alle Zellen brauchen gleich viele Schritte';
            return;
        end
        P = [cols{:}];
    end

    function msg = checkProgram(P, nBm, n)
        msg = '';
        if isempty(P)
            msg = 'Schrittliste ist leer';
            return;
        end
        if n == 0 && any(strcmp({P.type}, STEP_TEMP))
            msg = 'Temperaturschritt, aber keine Zelle mit BM und PM';
            return;
        end
        for i = 1:numel(P)
            st = P(i);
            switch st.type
                case STEP_TEMP
                    t = st.temps(~isnan(st.temps));
                    if numel(st.temps) ~= n
                        msg = sprintf('Schritt %d: Zahl der Zellen passt nicht (Liste neu laden)', i);
                    elseif isempty(t)
                        msg = sprintf('Schritt %d: keine Solltemperatur angegeben', i);
                    elseif any(t < PROFILE_T_MIN_DEGC | t > PROFILE_T_MAX_DEGC)
                        msg = sprintf('Schritt %d: Solltemperaturen müssen zwischen %g und %g °C liegen', ...
                                      i, PROFILE_T_MIN_DEGC, PROFILE_T_MAX_DEGC);
                    end
                case STEP_WAIT
                    if ~(st.minutes > 0) || st.minutes > AUTO_WAIT_MAX_MIN
                        msg = sprintf('Schritt %d: Wartezeit muss > 0 und <= %g min sein', i, AUTO_WAIT_MAX_MIN);
                    end
                case STEP_EIS
                    if st.target(1) == 'C' && str2double(st.target(2:end)) > nBm
                        msg = sprintf('Schritt %d: %s hat kein BM', i, autoTargetText(st.target));
                    end
                case STEP_REPEAT
                    if ~(st.from >= 1 && st.from < i && st.from == round(st.from))
                        msg = sprintf('Schritt %d: Wiederholung muss bei einem früheren Schritt (1 bis %d) beginnen', i, i - 1);
                    elseif ~(st.count >= 1 && st.count <= AUTO_REPEAT_MAX && st.count == round(st.count))
                        msg = sprintf('Schritt %d: Anzahl muss eine ganze Zahl von 1 bis %d sein', i, AUTO_REPEAT_MAX);
                    elseif all(strcmp({P(st.from:i - 1).type}, STEP_REPEAT))
                        msg = sprintf('Schritt %d: der wiederholte Bereich braucht mindestens einen anderen Schritt', i);
                    end
                otherwise
                    msg = sprintf('Schritt %d: unbekannter Schritttyp', i);
            end
            if ~isempty(msg)
                return;
            end
        end
    end

    %% =========================================================================
    %  Schrittliste: Editor (Tabelle + Text)
    %  =========================================================================
    % Tabelle: eine Zeile je Schritt. Spalte "Typ" waehlt den Schritttyp; je nach Typ werden
    % die passenden Spalten verwendet (Temperaturen je Zelle, Wartezeit, EIS-Ziel, ab Schritt /
    % Anzahl). Leeres Temperaturfeld = Solltemperatur der Zelle bleibt unveraendert.
    function openProfileEditor()
        if ~isempty(profileEdit.fig) && isvalid(profileEdit.fig)
            figure(profileEdit.fig);                    % schon offen: nach vorne holen
            return;
        end
        if isempty(cfg.bmAddr)
            logMsg('Schrittliste: zuerst verbinden - die Zahl der Zellen kommt vom MM');
            return;
        end
        resizeProgram();
        n = autoCellCount();
        pe = struct();
        pe.P      = autoProgram;
        pe.n      = n;
        pe.nBm    = numel(cfg.bmAddr);
        pe.selRow = [];
        pe.targets = [arrayfun(@(k) sprintf('C%d', k), 1:pe.nBm, 'UniformOutput', false), {'S', 'ALL', 'ALLS'}];
        pe.targetText = cellfun(@autoTargetText, pe.targets, 'UniformOutput', false);
        pe.colTemp   = 1 + (1:n);                        % Spaltenindizes der Tabelle
        pe.colWait   = n + 2;
        pe.colTarget = n + 3;
        pe.colFrom   = n + 4;
        pe.colCount  = n + 5;
        pe.fig = figure('Name', 'Schrittliste (Automatik)', 'NumberTitle', 'off', 'MenuBar', 'none', ...
            'ToolBar', 'none', 'Units', 'pixels', 'Position', [120 120 PROFILE_FIG_SIZE_PX]);
        colNames = [{'Typ'}, arrayfun(@(k) sprintf('Zelle %d [°C]', k), 1:n, 'UniformOutput', false), ...
                    {'Wartezeit [min]', 'EIS-Ziel', 'ab Schritt', 'Anzahl'}];
        colFormat = [{STEP_TYPE_TEXT}, repmat({'char'}, 1, n), {'char', pe.targetText, 'char', 'char'}];
        pe.table = uitable(pe.fig, 'Units', 'normalized', 'Position', [0.02 0.42 0.96 0.55], ...
            'ColumnName', colNames, 'ColumnFormat', colFormat, 'ColumnEditable', true(1, numel(colNames)), ...
            'CellEditCallback', @(src, ev) profileCellEdited(ev), ...
            'CellSelectionCallback', @(~, ev) profileCellSelected(ev));
        uicontrol(pe.fig, 'Style', 'text', 'String', 'Neuer Schritt:', 'Units', 'normalized', ...
            'Position', [0.02 0.355 0.08 0.04], 'HorizontalAlignment', 'left');
        pe.newType = uicontrol(pe.fig, 'Style', 'popupmenu', 'String', STEP_TYPE_TEXT, 'Units', 'normalized', ...
            'Position', [0.10 0.36 0.11 0.045]);
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Davor einfügen', 'Units', 'normalized', 'Position', [0.22 0.355 0.095 0.05], ...
            'TooltipString', 'neuen Schritt vor dem markierten Schritt einfügen (ohne Markierung: am Anfang)', ...
            'Callback', @(~, ~) profileInsertStep(PROFILE_INSERT_BEFORE));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Danach einfügen', 'Units', 'normalized', 'Position', [0.32 0.355 0.095 0.05], ...
            'TooltipString', 'neuen Schritt nach dem markierten Schritt einfügen (ohne Markierung: am Ende)', ...
            'Callback', @(~, ~) profileInsertStep(PROFILE_INSERT_AFTER));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Löschen', 'Units', 'normalized', 'Position', [0.42 0.355 0.08 0.05], ...
            'TooltipString', 'markierten (sonst letzten) Schritt löschen', 'Callback', @(~, ~) profileRemoveStep());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', '▲ nach oben', 'Units', 'normalized', 'Position', [0.505 0.355 0.085 0.05], ...
            'TooltipString', 'markierten Schritt eine Position früher ausführen', ...
            'Callback', @(~, ~) profileMoveStep(PROFILE_INSERT_BEFORE));
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', '▼ nach unten', 'Units', 'normalized', 'Position', [0.595 0.355 0.085 0.05], ...
            'TooltipString', 'markierten Schritt eine Position später ausführen', ...
            'Callback', @(~, ~) profileMoveStep(PROFILE_INSERT_AFTER));
        pe.selText = uicontrol(pe.fig, 'Style', 'text', 'String', 'kein Schritt markiert', 'Units', 'normalized', ...
            'Position', [0.69 0.355 0.29 0.04], 'HorizontalAlignment', 'left');
        pe.status = uicontrol(pe.fig, 'Style', 'text', 'String', '', 'Units', 'normalized', 'Position', [0.02 0.30 0.96 0.045], ...
            'HorizontalAlignment', 'left', 'FontWeight', 'bold');
        uicontrol(pe.fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.02 0.235 0.62 0.065], 'HorizontalAlignment', 'left', ...
            'String', sprintf(['Texteingabe: ein Schritt je Zeile, z. B. "Temperatur: Zelle 1 = 25, Zelle 2 = 35", "Warten: 5 min",\n' ...
                               '"EIS: alle Zellen", "Wiederholen: ab Schritt 6, insgesamt 13-mal" (# = Kommentar)']));
        pe.text = uicontrol(pe.fig, 'Style', 'edit', 'Max', 2, 'Min', 0, 'Units', 'normalized', 'Position', [0.02 0.03 0.62 0.20], ...
            'HorizontalAlignment', 'left', 'FontName', 'Consolas', 'BackgroundColor', 'w');
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Text → Tabelle', 'Units', 'normalized', 'Position', [0.66 0.17 0.15 0.06], ...
            'Callback', @(~, ~) profileTextApply());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Laden ...', 'Units', 'normalized', 'Position', [0.66 0.10 0.15 0.06], ...
            'TooltipString', 'Schrittliste laden (alte Temperaturprofile werden umgewandelt)', 'Callback', @(~, ~) profileLoad());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Speichern ...', 'Units', 'normalized', 'Position', [0.66 0.03 0.15 0.06], ...
            'Callback', @(~, ~) profileSave());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Übernehmen', 'Units', 'normalized', 'Position', [0.83 0.10 0.15 0.06], ...
            'FontWeight', 'bold', 'TooltipString', 'Schrittliste für die Automatik übernehmen', 'Callback', @(~, ~) profileApply());
        uicontrol(pe.fig, 'Style', 'pushbutton', 'String', 'Schließen', 'Units', 'normalized', 'Position', [0.83 0.03 0.15 0.06], ...
            'Callback', @(~, ~) delete(pe.fig));
        profileEdit = pe;
        profileRefresh(true);
    end

    % Tabelle (und auf Wunsch den Text) aus profileEdit.P neu aufbauen
    function profileRefresh(updateText)
        pe = profileEdit;
        P = pe.P;
        numSteps = numel(P);
        if ~isempty(pe.selRow) && pe.selRow > numSteps
            profileEdit.selRow = [];
        end
        sel = profileEdit.selRow;
        data = repmat({''}, numSteps, pe.colCount);
        for i = 1:numSteps
            st = P(i);
            data{i, 1} = STEP_TYPE_TEXT{strcmp(STEP_TYPES, st.type)};
            switch st.type
                case STEP_TEMP
                    for k = 1:pe.n
                        if ~isnan(st.temps(k))
                            data{i, pe.colTemp(k)} = sprintf('%g', st.temps(k));
                        end
                    end
                case STEP_WAIT
                    data{i, pe.colWait} = sprintf('%g', st.minutes);
                case STEP_EIS
                    data{i, pe.colTarget} = pe.targetText{strcmp(pe.targets, st.target)};
                case STEP_REPEAT
                    data{i, pe.colFrom}  = sprintf('%d', st.from);
                    data{i, pe.colCount} = sprintf('%d', st.count);
            end
        end
        rowNames = arrayfun(@(s) sprintf('%d', s), 1:numSteps, 'UniformOutput', false);
        if ~isempty(sel)
            rowNames{sel} = [rowNames{sel} PROFILE_SEL_MARK];
            set(pe.selText, 'String', sprintf('markiert: Schritt %d', sel));
        else
            set(pe.selText, 'String', 'kein Schritt markiert');
        end
        set(pe.table, 'Data', data, 'RowName', rowNames);
        if updateText
            set(pe.text, 'String', programToText(P));
        end
    end

    function profileStatus(msg, isError)
        color = COLOR_TEXT_OK;
        if isError
            color = COLOR_TEXT_ERROR;
        end
        set(profileEdit.status, 'String', msg, 'TooltipString', msg, 'ForegroundColor', color);
    end

    % eine Zelle der Tabelle geaendert: in die Schrittliste uebernehmen (ungueltig -> alter Wert)
    function profileCellEdited(ev)
        pe = profileEdit;
        i = ev.Indices(1);  c = ev.Indices(2);
        st = pe.P(i);
        v = ev.NewData;
        err = '';
        if c == 1                                        % Typ geaendert: Schritt mit Standardwerten
            type = STEP_TYPES{strcmp(STEP_TYPE_TEXT, v)};
            if ~strcmp(type, st.type)
                st = newStep(type, pe.n);
                if strcmp(type, STEP_REPEAT)
                    st.from = max(1, i - 1);
                end
            end
        elseif strcmp(st.type, STEP_TEMP) && any(c == pe.colTemp)
            k = find(c == pe.colTemp);
            x = strtrim(strrep(char(v), ',', '.'));
            if isempty(x) || strcmp(x, '-')
                st.temps(k) = NaN;                       % Zelle bleibt unveraendert
            elseif isnan(str2double(x)) || str2double(x) < PROFILE_T_MIN_DEGC || str2double(x) > PROFILE_T_MAX_DEGC
                err = sprintf('ungültige Temperatur - erlaubt sind %g bis %g °C (leer = unverändert)', PROFILE_T_MIN_DEGC, PROFILE_T_MAX_DEGC);
            else
                st.temps(k) = str2double(x);
            end
        elseif strcmp(st.type, STEP_WAIT) && c == pe.colWait
            x = str2double(strrep(char(v), ',', '.'));
            if ~(x > 0) || x > AUTO_WAIT_MAX_MIN
                err = sprintf('Wartezeit muss > 0 und <= %g min sein', AUTO_WAIT_MAX_MIN);
            else
                st.minutes = x;
            end
        elseif strcmp(st.type, STEP_EIS) && c == pe.colTarget
            st.target = pe.targets{strcmp(pe.targetText, v)};
        elseif strcmp(st.type, STEP_REPEAT) && (c == pe.colFrom || c == pe.colCount)
            x = str2double(char(v));
            if c == pe.colFrom
                if ~(x >= 1 && x < i && x == round(x))
                    err = sprintf('"ab Schritt" muss ein früherer Schritt sein (1 bis %d)', i - 1);
                else
                    st.from = x;
                end
            elseif ~(x >= 1 && x <= AUTO_REPEAT_MAX && x == round(x))
                err = sprintf('Anzahl muss eine ganze Zahl von 1 bis %d sein', AUTO_REPEAT_MAX);
            else
                st.count = x;
            end
        else
            err = sprintf('dieses Feld gehört nicht zum Schritttyp "%s"', STEP_TYPE_TEXT{strcmp(STEP_TYPES, st.type)});
        end
        if isempty(err)
            profileEdit.P(i) = st;
            profileStatus('geändert - mit "Übernehmen" für die Automatik setzen', false);
        else
            profileStatus(err, true);
        end
        profileRefresh(true);
    end

    function profileCellSelected(ev)
        if ~isempty(ev.Indices) && ~isequal(profileEdit.selRow, ev.Indices(1, 1))
            profileEdit.selRow = ev.Indices(1, 1);
            set(profileEdit.selText, 'String', sprintf('markiert: Schritt %d', profileEdit.selRow));
        end
    end

    % Nach Einfuegen / Loeschen / Verschieben: "ab Schritt" der Wiederholungen nachfuehren.
    % newPos(i) = neue Nummer des bisherigen Schritts i
    function P = remapRepeats(P, newPos)
        for i = 1:numel(P)
            if strcmp(P(i).type, STEP_REPEAT) && P(i).from >= 1 && P(i).from <= numel(newPos)
                P(i).from = newPos(P(i).from);
            end
        end
    end

    function profileInsertStep(direction)
        P = profileEdit.P;
        numSteps = numel(P);
        r = profileEdit.selRow;
        if isempty(r)
            pos = (direction == PROFILE_INSERT_AFTER) * numSteps + 1;   % Anfang bzw. Ende
        elseif direction == PROFILE_INSERT_AFTER
            pos = r + 1;
        else
            pos = r;
        end
        type = STEP_TYPES{get(profileEdit.newType, 'Value')};
        st = newStep(type, profileEdit.n);
        if strcmp(type, STEP_REPEAT)
            st.from = max(1, pos - 1);
        end
        oldPos = 1:numSteps;
        P = remapRepeats(P, oldPos + (oldPos >= pos));
        if isempty(P)
            P = st;
        else
            P = [P(1:pos - 1), st, P(pos:end)];
        end
        profileEdit.P = P;
        profileEdit.selRow = pos;                        % neuer Schritt ist markiert -> direkt anpassen
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d eingefügt - mit "Übernehmen" für die Automatik setzen', pos), false);
    end

    % markierten Schritt um eine Position verschieben (PROFILE_INSERT_BEFORE = nach oben)
    function profileMoveStep(direction)
        r = profileEdit.selRow;
        if isempty(r)
            profileStatus('zuerst einen Schritt in der Tabelle markieren', true);
            return;
        end
        target = r + direction;
        if target < 1 || target > numel(profileEdit.P)
            return;                                      % schon am Anfang / Ende
        end
        newPos = 1:numel(profileEdit.P);
        newPos([r, target]) = [target, r];
        P = remapRepeats(profileEdit.P, newPos);
        P([r, target]) = P([target, r]);
        profileEdit.P = P;
        profileEdit.selRow = target;                     % Markierung wandert mit
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d -> %d verschoben - "ab Schritt" der Wiederholungen bitte prüfen', r, target), false);
    end

    function profileRemoveStep()
        P = profileEdit.P;
        if isempty(P)
            return;
        end
        r = numel(P);
        if ~isempty(profileEdit.selRow) && profileEdit.selRow <= numel(P)
            r = profileEdit.selRow;
        end
        oldPos = 1:numel(P);
        P = remapRepeats(P, max(1, oldPos - (oldPos > r)));
        P(r) = [];
        profileEdit.P = P;
        profileEdit.selRow = [];
        profileRefresh(true);
        profileStatus(sprintf('Schritt %d gelöscht - mit "Übernehmen" für die Automatik setzen', r), false);
    end

    function ok = profileTextApply()
        [P, msg] = parseProgramText(get(profileEdit.text, 'String'), profileEdit.nBm, profileEdit.n);
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
        [file, folder] = uigetfile({'*.txt', 'Schrittliste / Temperaturprofil (*.txt)'}, 'Schrittliste laden', [PROFILE_FOLDER filesep]);
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
        [file, folder] = uiputfile({'*.txt', 'Schrittliste (*.txt)'}, 'Schrittliste speichern', ...
                                   fullfile(PROFILE_FOLDER, AUTO_PROFILE_FILE));
        if isequal(file, 0)
            return;
        end
        fid = fopen(fullfile(folder, file), 'w', 'n', 'UTF-8');
        if fid < 0
            profileStatus('Datei nicht schreibbar', true);
            return;
        end
        fprintf(fid, '# Schrittliste der Automatik (ein Schritt je Zeile)\n');
        lines = programToText(profileEdit.P);
        fprintf(fid, '%s\n', lines{:});
        fclose(fid);
        profileStatus(sprintf('gespeichert: %s', file), false);
    end

    function profileApply()
        if autoRunning()
            profileStatus('Automatik läuft - die Schrittliste kann erst danach geändert werden', true);
            return;
        end
        % Text geaendert, aber nicht uebernommen? Dann gilt der Text.
        current = strjoin(reshape(cellstr(get(profileEdit.text, 'String')), 1, []), newline);
        if ~strcmp(strtrim(current), strjoin(programToText(profileEdit.P), newline)) && ~profileTextApply()
            return;
        end
        if profileEdit.n ~= autoCellCount() || profileEdit.nBm ~= numel(cfg.bmAddr)
            profileStatus('Zahl der Zellen hat sich geändert - Editor schließen und neu öffnen', true);
            return;
        end
        msg = checkProgram(profileEdit.P, profileEdit.nBm, profileEdit.n);
        if ~isempty(msg)
            profileStatus(msg, true);
            return;
        end
        autoProgram = profileEdit.P;
        updateAutoSummary();
        profileStatus(sprintf('übernommen: %d Schritt(e)', numel(autoProgram)), false);
        logMsg(sprintf('Schrittliste übernommen: %d Schritt(e)', numel(autoProgram)));
    end

    %% =========================================================================
    %  Intervallmessung (nur Manuell): EIS-Messung in festen Zeitabstaenden
    %  =========================================================================
    % Das Intervall zaehlt von Start zu Start. Dauert eine Messung laenger als das Intervall,
    % beginnt die naechste direkt danach. Anzahl 0 = bis "Abbrechen". Alle Messungen einer
    % Reihe landen in einem Ordner <Zielordner>/<Dateiname>_Intervall_<Zeitstempel>.
    function startInterval(job)
        minutesI = str2double(strrep(get(hIntMin, 'String'), ',', '.'));
        count    = str2double(get(hIntCount, 'String'));
        if ~(minutesI > 0)
            logMsg('Intervallmessung: Intervall muss > 0 min sein');
            return;
        end
        if ~(count >= INTERVAL_COUNT_ENDLESS && count == round(count))
            logMsg('Intervallmessung: Anzahl muss eine ganze Zahl >= 0 sein (0 = bis Abbrechen)');
            return;
        end
        folder = fullfile(job.info.folder, sprintf('%s_Intervall_%s', job.info.baseName, ...
                          char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss'))));
        [created, mkMsg] = mkdir(folder);
        if ~created
            logMsg(['Intervallmessung: Ordner nicht anlegbar: ' mkMsg]);
            return;
        end
        intervalRun = struct('active', true, 'measuring', false, 'intervalS', minutesI * SECONDS_PER_MINUTE, ...
                             'count', count, 'done', 0, 'failed', 0, 'lastStart', NaT, 'nextAt', NaT, ...
                             'job', job, 'folder', folder);
        set(intervalLockHandles, 'Enable', 'off');
        logMsg(sprintf('Intervallmessung gestartet: %s alle %g min, %s, Ordner %s', autoTargetText(job.target), ...
                       minutesI, intervalCountText(), folder));
        intervalMeasure();
        if ~isRunning(intervalTimer)
            start(intervalTimer);
        end
    end

    function s = intervalCountText()
        if intervalRun.count == INTERVAL_COUNT_ENDLESS
            s = 'bis Abbrechen';
        else
            s = sprintf('%d Messungen', intervalRun.count);
        end
    end

    function intervalMeasure()
        i = intervalRun.done + 1;
        info = intervalRun.job.info;
        info.folder    = intervalRun.folder;
        info.baseName  = sprintf('%s_N%03d', intervalRun.job.info.baseName, i);
        info.comment   = strtrim(sprintf('%s [Intervallmessung %d, alle %g min]', intervalRun.job.info.comment, i, ...
                                         intervalRun.intervalS / SECONDS_PER_MINUTE));
        info.cellNames = cellNames;
        beginJob(info);
        intervalRun.measuring = true;
        intervalRun.lastStart = datetime('now');
        updateEisButtons(true);
        sendEis(intervalRun.job.target, intervalRun.job);
    end

    % Messung der Reihe beendet (EISDONE) oder vom MM abgelehnt (ERR;EIS)
    function intervalOnDone(ok)
        if ~intervalRun.active || ~intervalRun.measuring
            return;
        end
        intervalRun.measuring = false;
        intervalRun.done = intervalRun.done + 1;
        if ~ok
            intervalRun.failed = intervalRun.failed + 1;
        end
        if intervalRun.count ~= INTERVAL_COUNT_ENDLESS && intervalRun.done >= intervalRun.count
            intervalFinish(sprintf('Intervallmessung beendet: %d Messung(en), davon %d fehlgeschlagen', ...
                                   intervalRun.done, intervalRun.failed));
            return;
        end
        intervalRun.nextAt = max(intervalRun.lastStart + seconds(intervalRun.intervalS), datetime('now'));
        intervalTick();
    end

    function intervalTick()
        if ~isvalid(fig) || ~intervalRun.active || intervalRun.measuring
            return;
        end
        nowT = datetime('now');
        if nowT >= intervalRun.nextAt && ~mmBusy
            intervalMeasure();
            return;
        end
        total = '';
        if intervalRun.count ~= INTERVAL_COUNT_ENDLESS
            total = sprintf(' von %d', intervalRun.count);
        end
        set(hProgress, 'String', sprintf('Intervallmessung: %d%s fertig, nächste Messung in %s', ...
            intervalRun.done, total, minSec(seconds(intervalRun.nextAt - nowT))));
    end

    function intervalFinish(msg)
        if ~intervalRun.active
            return;
        end
        intervalRun.active = false;
        intervalRun.measuring = false;
        if ~isempty(intervalTimer) && isvalid(intervalTimer)
            stop(intervalTimer);
        end
        set(intervalLockHandles, 'Enable', 'on');
        set(hCellRail, 'Enable', onOff(~isAutoMode()));
        updateEisButtons(mmBusy);
        set(hProgress, 'String', msg);
        logMsg(msg);
    end

    % Knopf "Abbrechen" im EIS-Panel: laufende Messung abbrechen, eine Intervallreihe beenden
    function n = intervalDoneCount()
        n = 0;
        if isfield(intervalRun, 'done')
            n = intervalRun.done;
        end
    end

    function onEisAbortPressed()
        if intervalRun.active
            if intervalRun.measuring
                sendCommand('ABORT');
            end
            intervalFinish(sprintf('Intervallmessung abgebrochen nach %d Messung(en)', intervalRun.done));
        else
            sendCommand('ABORT');
        end
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

    % wie targetText, Einzelzelle im Testmodus Stackkonfiguration mit Zusatz
    function s = measLabel(t)
        s = targetText(t);
        if isKey(meas, t)
            entry = meas(t);                         % Map: nur eine Indexebene moeglich
            if isfield(entry, 'onRail') && entry.onRail
                s = sprintf('%s (%s)', s, CELL_RAIL_LABEL);
            end
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
