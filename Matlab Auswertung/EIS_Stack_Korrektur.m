function erg = EIS_Stack_Korrektur(stackDatei, kontaktDateien, varargin)
% EIS_Stack_Korrektur  Rechnet die Kontaktierung der Zellen aus einer Stackmessung heraus
%
%   Bei der Stackmessung liegt jede Zelle mit ihrer Kontaktierung (Kabel, Anschraub-
%   punkte, T1, Rail) in Reihe; die Zweige sind parallel an der Rail:
%       1/Z_Stack = Summe_k 1/(Z_Zelle + Z_Kontakt,k)
%   Unter der Annahme, dass alle angeschlossenen Zellen dieselbe Impedanz Z_Zelle haben,
%   wird Z_Zelle bei jeder Frequenz aus dieser Gleichung bestimmt (Newton-Verfahren) und
%   der Stack ohne Kontaktierung berechnet:
%       Z_Stack,korrigiert = Z_Zelle / N
%   Bei gleichen Kontaktierungen ist das genau Z_Stack - Z_Kontakt/N.
%
%   erg = EIS_Stack_Korrektur
%       Dialoge: Stackmessung, Anzahl der Zellen, je Zelle Kontaktierungsdatei und Modell
%   erg = EIS_Stack_Korrektur(stackDatei, {kontakt1, kontakt2, ...})
%       eine Kontaktierungsdatei je angeschlossener Zelle (Ausgabe von EIS_Kontaktierung,
%       ..._Kontaktierung.txt); dieselbe Datei darf mehrfach vorkommen
%   erg = EIS_Stack_Korrektur(..., 'Modelle', {'RL_Skin', 'Messdaten'})
%       Modell je Zelle (oder ein Text fuer alle):
%         'RL_Skin'       (Standard) R0 + jwL0 + (R1 || L1)
%         'RL_parallel_C' (R + jwL) || C
%         'RLC_seriell'   R + jwL + 1/(jwC)
%         'Messdaten'     gemessene Kontaktimpedanz direkt (interpoliert, ohne Modell)
%       Das Modell wird an die Kontaktierungsdatei angepasst (EIS_Kontakt_Modell).
%   erg = EIS_Stack_Korrektur(..., 'Ausgabe', 'pfad\Stack_korrigiert.txt')
%       Standard: <Stackdatei>_ohneKontakt.txt im selben Ordner
%
%   Ausgabe: <Name>.txt und <Name>_Komma.txt im Format der MM-Messdateien, ein
%   Nyquist-Diagramm (Stack gemessen / ohne Kontaktierung) und die Struktur erg.

    MODELLE = {'RL_Skin', 'RL_parallel_C', 'RLC_seriell', 'Messdaten'};
    MILLI   = 1e3;
    MARKER  = 4;
    NEWTON_SCHRITTE = 50;
    NEWTON_TOLERANZ = 1e-12;     % relative Aenderung von Z_Zelle

    % ---- Argumente / Dialoge ----
    p = inputParser;
    addParameter(p, 'Modelle', MODELLE{1});
    addParameter(p, 'Ausgabe', '', @(s) ischar(s) || isstring(s));
    if nargin < 2
        [stackDatei, kontaktDateien, modelle] = dialoge(MODELLE);
        if isempty(stackDatei)
            erg = [];
            return;
        end
        parse(p, varargin{:});
    else
        parse(p, varargin{:});
        kontaktDateien = cellstr(kontaktDateien);
        modelle = cellstr(p.Results.Modelle);
        if isscalar(modelle)
            modelle = repmat(modelle, 1, numel(kontaktDateien));
        end
    end
    n = numel(kontaktDateien);
    if numel(modelle) ~= n
        error('EIS_Stack_Korrektur:modelle', 'Anzahl der Modelle (%d) passt nicht zur Anzahl der Zellen (%d)', numel(modelle), n);
    end
    if ~all(ismember(modelle, MODELLE))
        error('EIS_Stack_Korrektur:modell', 'Unbekanntes Modell (erlaubt: %s)', strjoin(MODELLE, ', '));
    end
    ausgabe = char(p.Results.Ausgabe);
    if isempty(ausgabe)
        [ordner, name] = fileparts(stackDatei);
        ausgabe = fullfile(ordner, [name '_ohneKontakt.txt']);
    end

    % ---- Stackmessung ----
    stack = EIS_Datei_lesen(stackDatei);
    f  = stack.f(:);
    zS = stack.re(:) + 1i * stack.im(:);

    % ---- Kontaktierung je Zelle bei den Frequenzen der Stackmessung ----
    zK = zeros(numel(f), n);
    beschreibung = cell(1, n);
    for k = 1:n
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
            if any(f < min(fK) | f > max(fK))
                warning('EIS_Stack_Korrektur:extrapolation', ...
                        'Zelle %d: Modell wird ausserhalb des Frequenzbereichs der Kontaktmessung verwendet', k);
            end
            beschreibung{k} = sprintf('Zelle %d: %s, Modell %s: %s', k, kd.name, modelle{k}, km.text);
        end
    end
    gueltig = all(~isnan(zK), 2);
    if any(~gueltig)
        warning('EIS_Stack_Korrektur:bereich', '%d Frequenzen ohne Kontaktdaten (Messdaten ausserhalb des Bereichs) werden weggelassen', ...
                nnz(~gueltig));
    end
    f  = f(gueltig);
    zS = zS(gueltig);
    zK = zK(gueltig, :);

    % ---- Z_Zelle je Frequenz: Summe 1/(Z_Zelle + Z_Kontakt,k) = 1/Z_Stack ----
    zZelle = zeros(size(f));
    for i = 1:numel(f)
        zc = n * zS(i) - mean(zK(i, :));                % exakt bei gleichen Kontaktierungen
        for s = 1:NEWTON_SCHRITTE
            summand = 1 ./ (zc + zK(i, :));
            g  = sum(summand) - 1 / zS(i);
            dg = -sum(summand .^ 2);
            schritt = g / dg;
            zc = zc - schritt;
            if abs(schritt) <= NEWTON_TOLERANZ * abs(zc)
                break;
            end
        end
        zZelle(i) = zc;
    end
    zKorr = zZelle / n;

    erg = struct('f', f, 'Zstack', zS, 'Zkorrigiert', zKorr, 'Zzelle', zZelle, ...
                 'Zkontakt', zK, 'anzahlZellen', n, 'modelle', {modelle});

    % ---- Ausgabe ----
    fprintf('\nStack ohne Kontaktierung: %s, %d Zellen\n', stack.name, n);
    for k = 1:n
        fprintf('  %s\n', beschreibung{k});
    end
    [~, iMitte] = min(abs(log10(f) - log10(sqrt(min(f) * max(f)))));
    fprintf('  Beispiel bei %.3g Hz: Re %.4f -> %.4f mOhm, Im %.4f -> %.4f mOhm\n', f(iMitte), ...
            real(zS(iMitte)) * MILLI, real(zKorr(iMitte)) * MILLI, imag(zS(iMitte)) * MILLI, imag(zKorr(iMitte)) * MILLI);

    kopf = [{'Stackmessung ohne Kontaktierung der Zellen', ...
             sprintf('Stackmessung: %s', stack.name), ...
             sprintf('Angeschlossene Zellen: %d (Annahme: alle Zellen mit gleicher Impedanz)', n)}, ...
            beschreibung];
    [ordner, name] = fileparts(ausgabe);
    EIS_Datei_schreiben(fullfile(ordner, [name '.txt']), name, kopf, f, zKorr, false);
    EIS_Datei_schreiben(fullfile(ordner, [name '_Komma.txt']), name, kopf, f, zKorr, true);
    fprintf('Gespeichert: %s (+ _Komma)\n', fullfile(ordner, [name '.txt']));

    fig = figure('Color', 'w', 'Name', 'Stack ohne Kontaktierung', 'NumberTitle', 'off');
    ax = axes(fig);
    plot(ax, real(zS) * MILLI, -imag(zS) * MILLI, '-o', 'MarkerSize', MARKER, 'DisplayName', 'Stack gemessen');
    hold(ax, 'on');
    plot(ax, real(zKorr) * MILLI, -imag(zKorr) * MILLI, '-o', 'MarkerSize', MARKER, 'DisplayName', 'Stack ohne Kontaktierung');
    grid(ax, 'on'); box(ax, 'on'); axis(ax, 'equal');
    xlabel(ax, 'Re(Z) [m\Omega]'); ylabel(ax, '-Im(Z) [m\Omega]');
    title(ax, sprintf('Stackmessung, %d Zellen: Kontaktierung herausgerechnet', n));
    legend(ax, 'Location', 'best');
end

function [stackDatei, kontaktDateien, modelle] = dialoge(MODELLE)
    FILTER = {'*.txt;*.csv;*.xlsx;*.xls', 'EIS-Messdaten (*.txt, *.csv, *.xlsx)'};
    stackDatei = '';  kontaktDateien = {};  modelle = {};

    [nm, o] = uigetfile(FILTER, 'Stackmessung auswaehlen');
    if isequal(nm, 0), return; end
    stack = fullfile(o, nm);

    antwort = inputdlg('Wie viele Zellen waren bei der Stackmessung an der Rail angeschlossen?', ...
                       'Anzahl der Zellen', 1, {'2'});
    if isempty(antwort), return; end
    n = round(str2double(antwort{1}));
    if ~isfinite(n) || n < 1
        error('EIS_Stack_Korrektur:anzahl', 'Ungueltige Anzahl der Zellen: %s', antwort{1});
    end

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
    stackDatei = stack;
end
