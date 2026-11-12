function dateien = EIS_Dateien_waehlen(titel)
% EIS_Dateien_waehlen  Mehrere Messdateien auswaehlen, auch aus verschiedenen Ordnern
%
%   dateien = EIS_Dateien_waehlen
%   dateien = EIS_Dateien_waehlen('Einzelzellmessungen auswaehlen')
%
%   Oeffnet die Dateiauswahl wiederholt: in jedem Durchgang koennen mehrere Dateien
%   eines Ordners markiert werden (Strg/Shift). Danach fragt ein Dialog, ob weitere
%   Dateien (z. B. aus einem anderen Ordner) hinzukommen sollen. Der naechste Durchgang
%   startet im zuletzt verwendeten Ordner. Doppelte Dateien werden nur einmal uebernommen.
%
%   Rueckgabe: Zellarray mit vollstaendigen Pfaden in Auswahlreihenfolge,
%   {} bei Abbruch.

    if nargin < 1 || isempty(titel)
        titel = 'EIS-Messungen auswaehlen';
    end
    FILTER     = {'*.txt;*.csv;*.xlsx;*.xls', 'EIS-Messdaten (*.txt, *.csv, *.xlsx)'};
    WEITERE    = 'Weitere hinzufuegen';
    FERTIG     = 'Fertig';
    ABBRECHEN  = 'Abbrechen';
    MAX_LISTE  = 10;            % so viele Dateinamen zeigt der Dialog hoechstens an

    dateien = {};
    ordner  = '';
    while true
        [namen, o] = uigetfile(FILTER, sprintf('%s (bisher %d)', titel, numel(dateien)), ...
                               ordner, 'MultiSelect', 'on');
        if isequal(namen, 0)
            break;                                  % Auswahl abgebrochen: bisherige Dateien behalten
        end
        ordner  = o;
        dateien = [dateien, fullfile(o, cellstr(namen))]; %#ok<AGROW>
        [~, erste] = unique(dateien, 'first');
        dateien = dateien(sort(erste));

        [~, nm, ext] = cellfun(@fileparts, dateien, 'UniformOutput', false);
        liste = strcat(nm, ext);
        if numel(liste) > MAX_LISTE
            liste = [liste(1:MAX_LISTE), {sprintf('... (%d weitere)', numel(liste) - MAX_LISTE)}];
        end
        antwort = questdlg([{sprintf('%d Datei(en) ausgewaehlt:', numel(dateien))}, liste], ...
                           titel, WEITERE, FERTIG, ABBRECHEN, FERTIG);
        switch antwort
            case WEITERE
                continue;
            case FERTIG
                break;
            otherwise                               % Abbrechen oder Dialog geschlossen
                dateien = {};
                return;
        end
    end
end
