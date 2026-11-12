function d = EIS_Datei_lesen(datei)
% EIS_Datei_lesen  Liest eine EIS-Messdatei
%
%   d = EIS_Datei_lesen(datei)
%
%   Unterstuetzte Formate:
%     - Messdatei der MM-GUI (*.txt): Kopfzeilen mit '#', dann die Spalten
%       freq/Hz, Re(Z)/Ohm, Im(Z)/Ohm (auch die Variante *_Komma.txt mit Dezimalkomma)
%     - Tabellen (*.csv, *.xlsx, *.xls), z. B. vom Potentiostaten: Spalten werden
%       ueber ihre Namen erkannt (freq..., Re..., Im... bzw. minusIm... / -Im...)
%
%   Rueckgabe (Struktur):
%     d.f    Frequenz [Hz] (Spaltenvektor, Reihenfolge wie in der Datei)
%     d.re   Re(Z) [Ohm]
%     d.im   Im(Z) [Ohm], induktiv positiv (wie in der MM-GUI)
%     d.name Dateiname ohne Endung (fuer Legenden)

    [~, d.name, ext] = fileparts(datei);
    switch lower(ext)
        case {'.csv', '.xlsx', '.xls'}
            [d.f, d.re, d.im] = leseTabelle(datei);
        otherwise
            [d.f, d.re, d.im] = leseMmText(datei);
    end
    if isempty(d.f)
        error('EIS_Datei_lesen:keineDaten', 'Keine Messwerte gefunden in %s', datei);
    end
end

% ---- Messdatei der MM-GUI --------------------------------------------------------
function [f, re, im] = leseMmText(datei)
    SPALTEN = 3;                                        % freq, Re, Im
    zeilen = splitlines(fileread(datei));
    werte = zeros(0, SPALTEN);
    for k = 1:numel(zeilen)
        z = strtrim(zeilen{k});
        if isempty(z) || z(1) == '#' || ~isempty(regexp(z, '[A-DF-Za-df-z]', 'once'))
            continue;                                   % Kopf, Leerzeile, Spaltenueberschrift (e/E: Exponent)
        end
        z = strrep(z, ',', '.');                        % Variante mit Dezimalkomma
        v = sscanf(z, '%f').';
        if numel(v) == SPALTEN
            werte(end + 1, :) = v; %#ok<AGROW>
        end
    end
    f  = werte(:, 1);
    re = werte(:, 2);
    im = werte(:, 3);
end

% ---- Tabelle (Potentiostat o. ae.) -------------------------------------------------
function [f, re, im] = leseTabelle(datei)
    t = readtable(datei, 'VariableNamingRule', 'preserve');
    namen = t.Properties.VariableNames;
    iF  = findeSpalte(namen, '^freq');
    iRe = findeSpalte(namen, '^re');
    iIm = findeSpalte(namen, '(^|minus|-)im');
    if isempty(iF) || isempty(iRe) || isempty(iIm)
        error('EIS_Datei_lesen:spalten', ...
              'Spalten fuer Frequenz, Re(Z) und Im(Z) nicht gefunden in %s', datei);
    end
    f  = t{:, iF};
    re = t{:, iRe};
    im = t{:, iIm};
    imName = lower(namen{iIm});
    if contains(imName, 'minus') || startsWith(imName, '-')
        im = -im;                                       % Spalte enthaelt -Im(Z)
    end
end

function i = findeSpalte(namen, muster)
    i = find(~cellfun(@isempty, regexpi(namen, muster, 'once')), 1);
end
