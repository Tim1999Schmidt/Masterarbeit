function erg = EIS_Kontaktierung(einzelDatei, stackDatei, varargin)
% EIS_Kontaktierung  Impedanz der Kontaktierung Zelle -> Stack und Ersatzschaltbild
%
%   Grundlage: dieselbe Zelle einmal als Einzelzellmessung (Sense direkt an der Zelle)
%   und einmal als Stackmessung, bei der nur diese Zelle an der Rail haengt. Die
%   Differenz ist die Impedanz der Kontaktierung (Kabel, Anschraubpunkte, MOSFET T1,
%   Rail):
%       Z_Kontakt(f) = Z_Stack(f) - Z_Einzel(f)
%
%   erg = EIS_Kontaktierung
%       Dateiauswahl: zuerst die Einzelzellmessung, dann die Stackmessung
%   erg = EIS_Kontaktierung(einzelDatei, stackDatei)
%   erg = EIS_Kontaktierung(..., 'Modell', name)
%       Ersatzschaltbild (siehe EIS_Kontakt_Modell):
%         'RL_Skin'        (Standard) R0 + jwL0 + (R1 || L1), ohne Kapazitaet;
%                          R1 || L1 bildet den Anstieg von Re(Z) durch Stromverdraengung nach
%         'RL_parallel_C'  (R + jwL) || C
%         'RLC_seriell'    R + jwL + 1/(jwC)
%   erg = EIS_Kontaktierung(..., 'Ausgabe', 'pfad\Kontakt.txt')
%       Name der Ausgabedatei (Standard: <Stackdatei>_Kontaktierung.txt im selben Ordner)
%
%   Ausgabe:
%     - <Name>.txt         gemessene Z_Kontakt ueber f im Format der MM-Messdateien
%                          (Kopf mit Modell und Parametern)
%     - <Name>_Komma.txt   dasselbe mit Dezimalkomma (Excel)
%     - <Name>_Modell.txt  Impedanz des angepassten Ersatzschaltbilds bei denselben f
%     - Diagramme: Nyquist und Re/Im ueber f (Messdifferenz und Modell)
%     - erg: Struktur mit dem Modell (Parameter, Funktion), f, Z (Messung), Zmodell
%
%   Liegen die Frequenzen der beiden Messungen unterschiedlich, wird die
%   Einzelzellmessung ueber log(f) auf die Frequenzen der Stackmessung interpoliert.
%   Dateiformate: siehe EIS_Datei_lesen.

    MILLI  = 1e3;
    MIKRO  = 1e6;
    MARKER = 4;
    MODELLE = {'RL_Skin', 'RL_parallel_C', 'RLC_seriell'};

    % ---- Argumente ----
    p = inputParser;
    addParameter(p, 'Modell', MODELLE{1}, @(s) any(strcmp(s, MODELLE)));
    addParameter(p, 'Ausgabe', '', @(s) ischar(s) || isstring(s));
    if nargin < 2
        [einzelDatei, stackDatei] = dateienWaehlen();
        if isempty(einzelDatei)
            erg = [];
            return;
        end
    end
    parse(p, varargin{:});
    modell  = p.Results.Modell;
    ausgabe = char(p.Results.Ausgabe);
    if isempty(ausgabe)
        [ordner, name] = fileparts(stackDatei);
        ausgabe = fullfile(ordner, [name '_Kontaktierung.txt']);
    end

    % ---- Messdaten, Differenz ----
    einzel = EIS_Datei_lesen(einzelDatei);
    stack  = EIS_Datei_lesen(stackDatei);
    [fE, idx] = unique(einzel.f);
    zE = einzel.re(idx) + 1i * einzel.im(idx);
    imBereich = stack.f >= min(fE) & stack.f <= max(fE);
    if ~any(imBereich)
        error('EIS_Kontaktierung:bereich', 'Die Frequenzbereiche der beiden Messungen ueberlappen nicht');
    end
    if any(~imBereich)
        warning('EIS_Kontaktierung:bereich', '%d Frequenzen der Stackmessung liegen ausserhalb der Einzelzellmessung und werden weggelassen', ...
                nnz(~imBereich));
    end
    f  = stack.f(imBereich);
    zS = stack.re(imBereich) + 1i * stack.im(imBereich);
    zEinzel = interp1(log10(fE), real(zE), log10(f), 'linear') + ...
              1i * interp1(log10(fE), imag(zE), log10(f), 'linear');
    z = zS - zEinzel;                                   % Impedanz der Kontaktierung
    if mean(real(z)) <= 0
        warning('EIS_Kontaktierung:R', ['Re(Z_Kontakt) ist im Mittel nicht positiv - ' ...
                'ist die Reihenfolge Einzel/Stack richtig?']);
    end

    % ---- Ersatzschaltbild ----
    km = EIS_Kontakt_Modell(f, z, modell);

    erg = struct('modell', km, 'f', f, 'Z', z, 'Zmodell', km.zFit, ...
                 'einzel', einzel.name, 'stack', stack.name);

    fprintf('\nKontaktierung: %s  minus  %s\n', stack.name, einzel.name);
    fprintf('Modell %s, %d Frequenzen von %.3g Hz bis %.3g Hz\n', modell, numel(f), min(f), max(f));
    fprintf('  %s\n', km.text);
    if ~isempty(km.hinweis)
        fprintf('  Hinweis: %s\n', km.hinweis);
    end
    fprintf('  Restfehler (RMS) = %.2f uOhm\n', km.fehlerRms * MIKRO);

    % ---- Dateien ----
    kopf = {'Kontaktierung = Stackmessung - Einzelzellmessung', ...
            sprintf('Stackmessung: %s', stack.name), ...
            sprintf('Einzelzellmessung: %s', einzel.name), ...
            sprintf('Ersatzschaltbild: %s', modell)};
    for k = 1:numel(km.namen)
        kopf{end + 1} = sprintf('%s = %.6g %s', km.namen{k}, km.werte(k), einheit(km.namen{k})); %#ok<AGROW>
    end
    if ~isempty(km.hinweis)
        kopf{end + 1} = ['Hinweis: ' km.hinweis];
    end
    kopf{end + 1} = sprintf('Restfehler (RMS) = %.3g Ohm', km.fehlerRms);

    [ordner, name] = fileparts(ausgabe);
    EIS_Datei_schreiben(fullfile(ordner, [name '.txt']), name, kopf, f, z, false);
    EIS_Datei_schreiben(fullfile(ordner, [name '_Komma.txt']), name, kopf, f, z, true);
    EIS_Datei_schreiben(fullfile(ordner, [name '_Modell.txt']), [name '_Modell'], kopf, f, km.zFit, false);
    fprintf('Gespeichert: %s (+ _Komma, _Modell)\n', fullfile(ordner, [name '.txt']));

    % ---- Diagramme ----
    fig = figure('Color', 'w', 'Name', 'Kontaktierung', 'NumberTitle', 'off');
    titel = sprintf('Kontaktierung, Modell %s', strrep(modell, '_', '\_'));

    axN = subplot(1, 2, 1, 'Parent', fig);
    plot(axN, real(z) * MILLI, -imag(z) * MILLI, 'o', 'MarkerSize', MARKER, 'DisplayName', 'Messdifferenz');
    hold(axN, 'on');
    plot(axN, real(km.zFit) * MILLI, -imag(km.zFit) * MILLI, '-', 'LineWidth', 1.2, 'DisplayName', 'Ersatzschaltbild');
    grid(axN, 'on'); axis(axN, 'equal');
    xlabel(axN, 'Re(Z) [m\Omega]'); ylabel(axN, '-Im(Z) [m\Omega]');
    title(axN, {'Nyquist', titel});
    legend(axN, 'Location', 'best');

    axB = subplot(1, 2, 2, 'Parent', fig);
    semilogx(axB, f, real(z) * MILLI, 'o', f, imag(z) * MILLI, 's', 'MarkerSize', MARKER);
    hold(axB, 'on');
    semilogx(axB, f, real(km.zFit) * MILLI, '-', f, imag(km.zFit) * MILLI, '-', 'LineWidth', 1.2);
    grid(axB, 'on');
    xlabel(axB, 'f [Hz]'); ylabel(axB, 'Z [m\Omega]');
    title(axB, 'Re und Im ueber der Frequenz');
    legend(axB, {'Re (Messung)', 'Im (Messung)', 'Re (Modell)', 'Im (Modell)'}, 'Location', 'best');
end

function e = einheit(name)
    switch name(1)
        case 'R', e = 'Ohm';
        case 'L', e = 'H';
        otherwise, e = 'F';
    end
end

function [einzel, stack] = dateienWaehlen()
    FILTER = {'*.txt;*.csv;*.xlsx;*.xls', 'EIS-Messdaten (*.txt, *.csv, *.xlsx)'};
    einzel = '';
    stack  = '';
    [n, o] = uigetfile(FILTER, '1/2: Einzelzellmessung auswaehlen');
    if isequal(n, 0)
        return;
    end
    einzel = fullfile(o, n);
    [n, o] = uigetfile(FILTER, '2/2: Stackmessung derselben Zelle auswaehlen', o);
    if isequal(n, 0)
        einzel = '';
        return;
    end
    stack = fullfile(o, n);
end
