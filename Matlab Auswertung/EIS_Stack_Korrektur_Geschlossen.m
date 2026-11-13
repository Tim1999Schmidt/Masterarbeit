function erg = EIS_Stack_Korrektur_Geschlossen(stackDatei, kontaktDateien, varargin)
% EIS_Stack_Korrektur_Geschlossen  Stack ohne Kontaktierung fuer N = 2 Zellen, geschlossene Loesung
%
%   Gleiche Aufgabe wie EIS_Stack_Korrektur (Annahme: beide Zellen haben dieselbe Impedanz
%   Z_Z), aber ohne Newton-Verfahren: fuer zwei Zellen ist
%       1/Z_S = 1/(Z_Z + Z_K1) + 1/(Z_Z + Z_K2)
%   eine quadratische Gleichung in Z_Z mit der Loesung (pq-Formel)
%       Z_Z = Z_S - (Z_K1 + Z_K2)/2 +/- sqrt( Z_S^2 + ((Z_K1 - Z_K2)/2)^2 )
%   Physikalisch ist die Wurzel mit positivem Realteil; Stack ohne Kontaktierung: Z_0 = Z_Z/2.
%   Damit laesst sich das Ergebnis von EIS_Stack_Korrektur (Newton) Frequenz fuer
%   Frequenz pruefen.
%
%   erg = EIS_Stack_Korrektur_Geschlossen
%       Dialoge: Stackmessung, je Zelle Kontaktierungsdatei und Modell, optional die
%       Ausgabedatei von EIS_Stack_Korrektur (..._ohneKontakt.txt) zum Vergleich
%   erg = EIS_Stack_Korrektur_Geschlossen(stackDatei, {kontakt1, kontakt2})
%   erg = EIS_Stack_Korrektur_Geschlossen(..., 'Modelle', {'RL_Skin', 'Messdaten'})
%       Modell je Zelle wie bei EIS_Stack_Korrektur (ein Text fuer beide oder einer je Zelle)
%   erg = EIS_Stack_Korrektur_Geschlossen(..., 'Vergleich', 'pfad\Stack_ohneKontakt.txt')
%       Ergebnis des Newton-Verfahrens zum Vergleich (Abweichung je Frequenz)
%   erg = EIS_Stack_Korrektur_Geschlossen(..., 'Ausgabe', 'pfad\Stack_geschlossen.txt')
%       Standard: <Stackdatei>_ohneKontakt_geschlossen.txt im selben Ordner
%
%   Fuer den Vergleich dieselben Kontaktierungsdateien und Modelle verwenden wie bei
%   EIS_Stack_Korrektur, sonst vergleicht man unterschiedliche Kontaktmodelle.
%
%   Ausgabe: <Name>.txt und <Name>_Komma.txt (Format der MM-Messdateien), Diagramme
%   (Nyquist, Abweichung ueber f) und die Struktur erg.

    MODELLE        = {'RL_Skin', 'RL_parallel_C', 'RLC_seriell', 'Messdaten'};
    ANZAHL_ZELLEN  = 2;              % die geschlossene Loesung gilt nur fuer zwei Zellen
    MILLI          = 1e3;            % Ohm -> mOhm
    MIKRO          = 1e6;            % Ohm -> uOhm
    PROZENT        = 100;
    MARKER         = 4;

    % ---- Argumente / Dialoge ----
    p = inputParser;
    addParameter(p, 'Modelle', MODELLE{1});
    addParameter(p, 'Vergleich', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Ausgabe', '', @(s) ischar(s) || isstring(s));
    parse(p, varargin{:});
    vergleichDatei = char(p.Results.Vergleich);
    if nargin < 2
        [stackDatei, kontaktDateien, modelle, vergleichDatei] = dialoge(MODELLE, ANZAHL_ZELLEN);
        if isempty(stackDatei)
            erg = [];
            return;
        end
    else
        kontaktDateien = cellstr(kontaktDateien);
        modelle = cellstr(p.Results.Modelle);
        if isscalar(modelle)
            modelle = repmat(modelle, 1, numel(kontaktDateien));
        end
    end
    if numel(kontaktDateien) ~= ANZAHL_ZELLEN || numel(modelle) ~= ANZAHL_ZELLEN
        error('EIS_Stack_Korrektur_Geschlossen:anzahl', ...
              'Die geschlossene Loesung gilt nur fuer %d Zellen (je eine Kontaktierungsdatei und ein Modell)', ANZAHL_ZELLEN);
    end
    if ~all(ismember(modelle, MODELLE))
        error('EIS_Stack_Korrektur_Geschlossen:modell', 'Unbekanntes Modell (erlaubt: %s)', strjoin(MODELLE, ', '));
    end
    ausgabe = char(p.Results.Ausgabe);
    if isempty(ausgabe)
        [ordner, name] = fileparts(stackDatei);
        ausgabe = fullfile(ordner, [name '_ohneKontakt_geschlossen.txt']);
    end

    % ---- Stackmessung ----
    stack = EIS_Datei_lesen(stackDatei);
    f  = stack.f(:);
    zS = stack.re(:) + 1i * stack.im(:);

    % ---- Kontaktierung je Zelle (wie in EIS_Stack_Korrektur) ----
    zK = zeros(numel(f), ANZAHL_ZELLEN);
    beschreibung = cell(1, ANZAHL_ZELLEN);
    for k = 1:ANZAHL_ZELLEN
        kd = EIS_Datei_lesen(kontaktDateien{k});
        [fK, idx] = unique(kd.f);
        zKd = kd.re(idx) + 1i * kd.im(idx);
        if strcmp(modelle{k}, 'Messdaten')
            zK(:, k) = interp1(log10(fK), real(zKd), log10(f), 'linear') + ...
                       1i * interp1(log10(fK), imag(zKd), log10(f), 'linear');   % ausserhalb: NaN
            beschreibung{k} = sprintf('Zelle %d: %s, Messdaten', k, kd.name);
        else
            km = EIS_Kontakt_Modell(fK, zKd, modelle{k});
            zK(:, k) = km.Z(f);
            beschreibung{k} = sprintf('Zelle %d: %s, Modell %s: %s', k, kd.name, modelle{k}, km.text);
        end
    end
    gueltig = all(~isnan(zK), 2);
    if any(~gueltig)
        warning('EIS_Stack_Korrektur_Geschlossen:bereich', ...
                '%d Frequenzen ohne Kontaktdaten (Messdaten ausserhalb des Bereichs) werden weggelassen', nnz(~gueltig));
    end
    f  = f(gueltig);
    zS = zS(gueltig);
    zK = zK(gueltig, :);

    % ---- geschlossene Loesung je Frequenz ----
    % Z_Z^2 + p Z_Z + q = 0 mit p = Z_K1 + Z_K2 - 2 Z_S, q = Z_K1 Z_K2 - Z_S (Z_K1 + Z_K2)
    % -> Z_Z = Z_S - Z_Km +/- sqrt(Z_S^2 + Z_Kd^2),  Z_Km = Mittelwert, Z_Kd = halbe Differenz
    zKm    = (zK(:, 1) + zK(:, 2)) / 2;
    zKd    = (zK(:, 1) - zK(:, 2)) / 2;
    wurzel = sqrt(zS .^ 2 + zKd .^ 2);
    wurzeln = [zS - zKm + wurzel, zS - zKm - wurzel];
    [~, wahl] = max(real(wurzeln), [], 2);          % physikalisch: groesserer (positiver) Realteil
    zeile = (1:numel(f)).';
    zZelle = wurzeln(sub2ind(size(wurzeln), zeile, wahl));
    zAndere = wurzeln(sub2ind(size(wurzeln), zeile, 3 - wahl));
    z0 = zZelle / ANZAHL_ZELLEN;

    unphysikalisch = real(zZelle) <= 0;
    if any(unphysikalisch)
        warning('EIS_Stack_Korrektur_Geschlossen:unphysikalisch', ...
                ['%d Frequenzen ohne Loesung mit positivem Realteil (z. B. %.3g Hz): Stackmessung und ' ...
                 'Kontaktmodell passen dort nicht zusammen (Kontaktierung ueberschaetzt?)'], ...
                nnz(unphysikalisch), f(find(unphysikalisch, 1)));
    end

    erg = struct('f', f, 'Zstack', zS, 'Zkorrigiert', z0, 'Zzelle', zZelle, 'ZzelleAndereWurzel', zAndere, ...
                 'Zkontakt', zK, 'modelle', {modelle});

    fprintf('\nStack ohne Kontaktierung (geschlossene Loesung, 2 Zellen): %s\n', stack.name);
    for k = 1:ANZAHL_ZELLEN
        fprintf('  %s\n', beschreibung{k});
    end

    % ---- Vergleich mit dem Newton-Ergebnis ----
    if ~isempty(vergleichDatei)
        nd = EIS_Datei_lesen(vergleichDatei);
        [fN, idx] = unique(nd.f);
        zNd = nd.re(idx) + 1i * nd.im(idx);
        zNewton = interp1(log10(fN), real(zNd), log10(f), 'linear') + ...
                  1i * interp1(log10(fN), imag(zNd), log10(f), 'linear');
        if any(~ismember(f, fN))
            warning('EIS_Stack_Korrektur_Geschlossen:frequenzen', ...
                    'Frequenzen der Vergleichsdatei weichen ab - Newton-Ergebnis wird ueber log(f) interpoliert');
        end
        diffAbs = abs(z0 - zNewton);
        diffRel = diffAbs ./ abs(z0);
        erg.Znewton = zNewton;
        erg.abweichungAbs = diffAbs;
        erg.abweichungRel = diffRel;
        [maxRel, iMax] = max(diffRel);
        fprintf('Vergleich mit Newton (%s):\n', nd.name);
        fprintf('  max. |Z_geschlossen - Z_Newton| = %.4g uOhm (%.3g %%) bei %.4g Hz\n', ...
                max(diffAbs) * MIKRO, maxRel * PROZENT, f(iMax));
        fprintf('  (Dateien speichern Re/Im mit 8 Nachkommastellen in Ohm -> Rundung ca. 0,01 uOhm)\n');
    end

    % ---- Dateien ----
    kopf = [{'Stackmessung ohne Kontaktierung - geschlossene Loesung fuer 2 Zellen', ...
             'Z_Z = Z_S - (Z_K1+Z_K2)/2 + sqrt(Z_S^2 + ((Z_K1-Z_K2)/2)^2),  Z_0 = Z_Z/2', ...
             sprintf('Stackmessung: %s', stack.name), ...
             'Annahme: beide Zellen mit gleicher Impedanz'}, beschreibung];
    [ordner, name] = fileparts(ausgabe);
    EIS_Datei_schreiben(fullfile(ordner, [name '.txt']), name, kopf, f, z0, false);
    EIS_Datei_schreiben(fullfile(ordner, [name '_Komma.txt']), name, kopf, f, z0, true);
    fprintf('Gespeichert: %s (+ _Komma)\n', fullfile(ordner, [name '.txt']));

    % ---- Diagramme ----
    fig = figure('Color', 'w', 'Name', 'Stack ohne Kontaktierung - geschlossene Loesung', 'NumberTitle', 'off');
    axN = subplot(1, 2, 1, 'Parent', fig);
    plot(axN, real(zS) * MILLI, -imag(zS) * MILLI, '-o', 'MarkerSize', MARKER, 'DisplayName', 'Stack gemessen');
    hold(axN, 'on');
    plot(axN, real(z0) * MILLI, -imag(z0) * MILLI, '-o', 'MarkerSize', MARKER, 'DisplayName', 'ohne Kontakt, geschlossen');
    if isfield(erg, 'Znewton')
        plot(axN, real(erg.Znewton) * MILLI, -imag(erg.Znewton) * MILLI, 'x', 'MarkerSize', MARKER + 2, ...
             'DisplayName', 'ohne Kontakt, Newton');
    end
    grid(axN, 'on'); box(axN, 'on'); axis(axN, 'equal');
    xlabel(axN, 'Re(Z) [m\Omega]'); ylabel(axN, '-Im(Z) [m\Omega]');
    title(axN, 'Nyquist');
    legend(axN, 'Location', 'best');

    axD = subplot(1, 2, 2, 'Parent', fig);
    if isfield(erg, 'Znewton')
        semilogx(axD, f, erg.abweichungAbs * MIKRO, '-o', 'MarkerSize', MARKER);
        ylabel(axD, '|Z_{geschlossen} - Z_{Newton}| [\mu\Omega]');
        title(axD, 'Abweichung geschlossene Loesung - Newton');
    else
        semilogx(axD, f, real(z0) * MILLI, '-o', f, imag(z0) * MILLI, '-s', 'MarkerSize', MARKER);
        ylabel(axD, 'Z_0 [m\Omega]');
        legend(axD, {'Re', 'Im'}, 'Location', 'best');
        title(axD, 'Stack ohne Kontaktierung (kein Vergleich gewaehlt)');
    end
    grid(axD, 'on');
    xlabel(axD, 'f [Hz]');
end

function [stackDatei, kontaktDateien, modelle, vergleichDatei] = dialoge(MODELLE, n)
    FILTER = {'*.txt;*.csv;*.xlsx;*.xls', 'EIS-Messdaten (*.txt, *.csv, *.xlsx)'};
    stackDatei = '';  kontaktDateien = {};  modelle = {};  vergleichDatei = '';

    [nm, o] = uigetfile(FILTER, 'Stackmessung auswaehlen (2 Zellen an der Rail)');
    if isequal(nm, 0), return; end
    stack = fullfile(o, nm);

    kontaktDateien = cell(1, n);
    modelle = cell(1, n);
    for k = 1:n
        [nm, o] = uigetfile(FILTER, sprintf('Zelle %d von %d: Kontaktierungsdatei (..._Kontaktierung.txt)', k, n), o);
        if isequal(nm, 0), kontaktDateien = {}; return; end
        kontaktDateien{k} = fullfile(o, nm);
        [wahl, ok] = listdlg('ListString', MODELLE, 'SelectionMode', 'single', 'InitialValue', 1, ...
                             'Name', sprintf('Zelle %d', k), 'PromptString', sprintf('Modell fuer die Kontaktierung von Zelle %d:', k), ...
                             'ListSize', [260 90]);
        if ~ok, kontaktDateien = {}; return; end
        modelle{k} = MODELLE{wahl};
    end

    [nm, o2] = uigetfile(FILTER, 'Optional: Newton-Ergebnis (..._ohneKontakt.txt) zum Vergleich - Abbrechen = ohne Vergleich', o);
    if ~isequal(nm, 0)
        vergleichDatei = fullfile(o2, nm);
    end
    stackDatei = stack;
end
