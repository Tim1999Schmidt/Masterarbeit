function Textdatei_erstellen_func (handles,Empfangene_Zeilen)

    %   Legt automatisch einen Ordner + Textdatei an
    %   und schreibt die empfangenen Zeilen hinein.

    % Auslesen globaler Variablen für Textfile
    EIS_Textfelder_Werte = getappdata(0, 'EIS_Textfelder_Werte'); % Zielordner, Filename, Kommentar, Zellenname_Z1, Zellenname_Z2, Zellenname_Z3

    EIS_Popupmenu_Werte = getappdata(0, 'EIS_Popupmenu_Werte'); % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung, Messdauer

    EIS_Popupmenu_Werte_akt_str = getappdata(0, 'EIS_Popupmenu_Werte_akt_str'); % EIS_Chip, Start_Frequenz, Stopp_Frequenz, Amplitude, SinRec, Mittelung, Verschaltung

    EIS_Spannungs_Werte = getappdata(0, 'akt_Spg_fuer_Textfile'); % Spg_Z1, Spg_Z2, Spg_Z3, NC

    EIS_Kontaktwiderstand_Werte = getappdata(0, 'akt_Kontaktwerte_fuer_Textfile'); % R_S1, R_S2, R_S3
    
    ersteZeile = 2;
    letzteZeile = EIS_Popupmenu_Werte(3)-EIS_Popupmenu_Werte(2) + 2; % Berechnung wie viele Zeilen als Antwort erwartet werden;
    anzahlZeilen = EIS_Popupmenu_Werte(3)-EIS_Popupmenu_Werte(2) + 1;
    logRoot = EIS_Textfelder_Werte(1);      % "" = aktueller Ordner
    %logRoot = "Y:\Desktop_Verknüpfungen\Matlab_Test\Zielordner_Text";      % "" = aktueller Ordner

    % --- logRoot prüfen / ggf. anlegen ---
    if ~isempty(logRoot) && ~exist(logRoot, 'dir')
        mkdir(logRoot);
    end

    % --- Empfangene_Zeilen robust in string-Array umwandeln ---
    if iscell(Empfangene_Zeilen)
        Empfangene_Zeilen = string(Empfangene_Zeilen);
    elseif ischar(Empfangene_Zeilen)
        Empfangene_Zeilen = string(Empfangene_Zeilen);
    end

    % --- Ordner/Filename + Zeitstempel ---
    baseNameRaw = EIS_Textfelder_Werte(2);

    % Unerlaubte Zeichen im Dateinamen ersetzen
    safeBaseName = regexprep(baseNameRaw, '[^\w\-]', '_');

    ts = char(datetime('now','Format','yyyy-MM-dd_HHmmss'));
    baseName = safeBaseName + "_" + string(ts);

    % --- Unterordner erstellen ---
    if ~isempty(logRoot)
        folder = fullfile(logRoot, baseName);
    else
        folder = baseName;
    end
    if ~exist(folder, 'dir')
        mkdir(folder);
    end

    % --- Datei erstellen ---
    fullFilePath = fullfile(folder, baseName + ".txt");
    fid = fopen(fullFilePath, "w");
    assert(fid > 0, "Konnte Datei nicht öffnen: %s", fullFilePath);

    % --- Schreiben ---

    Beschriftung_1 = baseName;
    Beschriftung_2 = ["Name Zelle 1:","Name Zelle 2:","Name Zelle 3:","Verschaltung:"];
    Beschriftung_3 = ["EIS_Chip:","Start_Frequenz:","Stopp_Frequenz:","Amplitude:","Signalform:","Mittelung_ueber:"];
    Beschriftung_4 = ["freq/Hz", "Re(Z)/Ohm", "Im(Z)/Ohm"];

    try
        % 2 Beschriftungszeilen
        fprintf(fid, '# %s\n', Beschriftung_1);
        fprintf(fid, '# \n'); % Absatz
        fprintf(fid, '# Kommentar: %s\n', EIS_Textfelder_Werte{3});
        fprintf(fid, '# \n'); % Absatz
        fprintf(fid, '# %-30s %-30s %-30s %-30s\n', Beschriftung_2(1), Beschriftung_2(2), Beschriftung_2(3), Beschriftung_2(4));
        fprintf(fid, '# %-30s %-30s %-30s %-30s\n', EIS_Textfelder_Werte{4}, EIS_Textfelder_Werte{5}, EIS_Textfelder_Werte{6}, EIS_Popupmenu_Werte_akt_str{7});
        fprintf(fid, '# %-30s %-30s %-30s\n', sprintf('Zell-Spg:      %4d mV', EIS_Spannungs_Werte(1)), sprintf('Zell-Spg:      %4d mV', EIS_Spannungs_Werte(2)), sprintf('Zell-Spg:      %4d mV', EIS_Spannungs_Werte(3)));
        fprintf(fid, '# %-30s %-30s %-30s\n', sprintf('R_S1:          %.2f mΩ', EIS_Kontaktwiderstand_Werte(1)), sprintf('R_S2:          %.2f mΩ', EIS_Kontaktwiderstand_Werte(2)), sprintf('R_S3:          %.2f mΩ', EIS_Kontaktwiderstand_Werte(3)));
        fprintf(fid, '# \n'); % Absatz
        fprintf(fid, '# %-15s %-25s %-25s %-15s %-15s %-18s\n', Beschriftung_3(1), ...
                                                 Beschriftung_3(2), Beschriftung_3(3), ...
                                                 Beschriftung_3(4), Beschriftung_3(5), ...
                                                 Beschriftung_3(6));
        fprintf(fid, '# %-15s %-25s %-25s %-15s %-15s %-18s\n', EIS_Popupmenu_Werte_akt_str{1}, ...
                                    EIS_Popupmenu_Werte_akt_str{2}, EIS_Popupmenu_Werte_akt_str{3}, ...
                                    EIS_Popupmenu_Werte_akt_str{4}, EIS_Popupmenu_Werte_akt_str{5}, ...
                                    EIS_Popupmenu_Werte_akt_str{6});
        fprintf(fid, '\n'); % Absatz
        fprintf(fid, '  %10s\t%12s\t%12s\n', Beschriftung_4(1), Beschriftung_4(2), Beschriftung_4(3));

        % Datenzeilen von string in eine für Plotprogramm lesbares Format bringen, Wichtig!!!
        for k = ersteZeile:letzteZeile
            % Einzelne Zeile aus dem Array holen
            Einzelzeile = Empfangene_Zeilen(k);
            %logMsg(handles, Einzelzeile);
            % Die drei Zahlen aus der Zeile extrahieren
            Zahlenwerte = sscanf(Einzelzeile, '%f %f %f');   % Ergebnis: 3x1-Vektor
            f = Zahlenwerte(1);
            Re = Zahlenwerte(2)/1000; %von mohm in ohm
            Im = Zahlenwerte(3)/1000; %von mohm in ohm
            % In Datei schreiben
            fprintf(fid, '%12.2f\t%12.6f\t%12.6f\n', f, Re, Im);
        end

        fclose(fid);

        % =================================================================
        % NEU: Kopie erstellen und Dezimalpunkt -> Dezimalkomma ersetzen
        % =================================================================
        fullFilePath_Comma = fullfile(folder, baseName + "_Komma.txt");

        fid_r = fopen(fullFilePath, 'r');
        assert(fid_r > 0, "Konnte Originaldatei nicht zum Lesen öffnen: %s", fullFilePath);
        txt = fread(fid_r, '*char')';
        fclose(fid_r);

        txt = strrep(txt, '.', ',');

        fid_w = fopen(fullFilePath_Comma, 'w');
        assert(fid_w > 0, "Konnte Komma-Datei nicht zum Schreiben öffnen: %s", fullFilePath_Comma);
        fwrite(fid_w, txt);
        fclose(fid_w);
        % =================================================================

    catch ME
        fclose(fid);
        rethrow(ME);
    end

    logMsg(handles, 'Ordner und Textdatei wurden erstellt');
    logMsg(handles, ''); % leere Zeile einfügen


end