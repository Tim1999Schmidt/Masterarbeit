function fullFilePath = EIS_Textdatei_schreiben(m, jobInfo, targetLabel)
% EIS_Textdatei_schreiben  Schreibt das Ergebnis einer EIS-Messung als Textdatei
%
%   m           : Messung (Felder target, cells [BM U_mV T_degC], data [Index f_Hz Re_uOhm Im_uOhm],
%                 pm (letzte PM-Werte), start)
%   jobInfo     : Einstellungen des Auftrags (folder, baseName, timestamp, comment, cellNames, settings)
%   targetLabel : Bezeichnung des Messobjekts, z. B. 'Zelle 1 (Zelle_A)' oder 'Stack'
%
% Ordner : <Zielordner>/<Dateiname>_<Zeitstempel>/  (ein Ordner je Messauftrag)
% Datei  : <Dateiname>_<Ziel>.txt  und  <Dateiname>_<Ziel>_Komma.txt (Dezimalkomma)
% Aufbau wie bei der Zellhalter-GUI: Kopfzeilen mit '#', dann Spalten
% freq/Hz, Re(Z)/Ohm, Im(Z)/Ohm.

    UOHM_PER_OHM = 1e6;
    CELL_COLUMN_BM = 1;  CELL_COLUMN_U = 2;  CELL_COLUMN_T = 3;
    DATA_COLUMN_F = 2;   DATA_COLUMN_RE = 3; DATA_COLUMN_IM = 4;

    folder = fullfile(jobInfo.folder, sprintf('%s_%s', jobInfo.baseName, jobInfo.timestamp));
    if ~exist(folder, 'dir')
        mkdir(folder);
    end
    baseName = sprintf('%s_%s', jobInfo.baseName, m.target);
    fullFilePath = fullfile(folder, [baseName '.txt']);

    fid = fopen(fullFilePath, 'w');
    assert(fid > 0, 'Konnte Datei nicht öffnen: %s', fullFilePath);
    cleanup = onCleanup(@() fclose(fid));

    s = jobInfo.settings;
    fprintf(fid, '# %s\n', baseName);
    fprintf(fid, '# \n');
    fprintf(fid, '# Kommentar: %s\n', jobInfo.comment);
    fprintf(fid, '# Messobjekt: %s\n', targetLabel);
    fprintf(fid, '# Start: %s\n', char(m.start, 'yyyy-MM-dd HH:mm:ss'));
    fprintf(fid, '# \n');
    for k = 1:size(m.cells, 1)
        bm = m.cells(k, CELL_COLUMN_BM);
        name = '';
        if bm <= numel(jobInfo.cellNames)
            name = char(jobInfo.cellNames(bm));
        end
        fprintf(fid, '# BM %d %-20s Zell-Spg: %5d mV   T_Tab: %6.2f °C\n', bm, name, ...
                m.cells(k, CELL_COLUMN_U), m.cells(k, CELL_COLUMN_T));
    end
    for k = 1:numel(m.pm)
        if ~isempty(m.pm(k).tAct)
            fprintf(fid, '# PM %d   T_Soll: %6.2f °C   T_Ist: %6.2f °C   T_PT1000: %6.2f °C\n', ...
                    k, m.pm(k).tSet, m.pm(k).tAct, m.pm(k).tPt);
        end
    end
    fprintf(fid, '# \n');
    fprintf(fid, '# %-15s %-15s %-12s %-12s %-12s %-12s\n', 'Start_Index:', 'Stopp_Index:', 'Amplitude:', ...
            'Signalform:', 'Mittelung:', 'Messdauer:');
    fprintf(fid, '# %-15d %-15d %-12s %-12s %-12d %-12s\n', s.fStart, s.fStop, s.amplitude, s.waveform, ...
            s.averages, s.measTime);
    fprintf(fid, '\n');
    fprintf(fid, '  %10s\t%12s\t%12s\n', 'freq/Hz', 'Re(Z)/Ohm', 'Im(Z)/Ohm');
    for k = 1:size(m.data, 1)
        fprintf(fid, '%12.2f\t%12.6f\t%12.6f\n', m.data(k, DATA_COLUMN_F), ...
                m.data(k, DATA_COLUMN_RE) / UOHM_PER_OHM, m.data(k, DATA_COLUMN_IM) / UOHM_PER_OHM);
    end
    clear cleanup;                                   % schliesst die Datei

    % Kopie mit Dezimalkomma (z. B. fuer Excel)
    txt = fileread(fullFilePath);
    fid = fopen(fullfile(folder, [baseName '_Komma.txt']), 'w');
    assert(fid > 0, 'Konnte Komma-Datei nicht schreiben');
    fwrite(fid, strrep(txt, '.', ','));
    fclose(fid);
end
