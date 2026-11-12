function erg = EIS_Parallel(zellDateien, varargin)
% EIS_Parallel  Gesamtimpedanz parallel geschalteter Zellen aus Einzelzellmessungen
%
%   Z_Parallel = 1 / Summe_k 1/Z_Zelle,k
%
%   erg = EIS_Parallel
%       Dateiauswahl: Einzelzellmessungen (mehrere mit Strg/Shift, auch aus
%       verschiedenen Ordnern, siehe EIS_Dateien_waehlen)
%   erg = EIS_Parallel({zelle1, zelle2, ...})
%   erg = EIS_Parallel(..., 'Ausgabe', 'pfad\Parallel.txt')
%       Standard: <erste Datei>_Parallel.txt im selben Ordner
%
%   Optional zusaetzlich die Vorhersage der Stackmessung MIT Kontaktierung:
%   erg = EIS_Parallel(..., 'Kontakte', {kontakt1, kontakt2, ...}, 'Modelle', 'RL_Skin')
%       je Zelle die Kontaktierungsdatei (Ausgabe von EIS_Kontaktierung) in derselben
%       Reihenfolge wie die Zellen; Modelle wie bei EIS_Stack_Korrektur ('RL_Skin',
%       'RL_parallel_C', 'RLC_seriell', 'Messdaten'), ein Text fuer alle oder einer je Zelle.
%       Ergebnis:  Z_Vorhersage = 1 / Summe_k 1/(Z_Zelle,k + Z_Kontakt,k)
%       Diese Vorhersage laesst sich ohne jede Annahme direkt mit der gemessenen
%       Stackmessung vergleichen (EIS_Abweichung).
%
%   Ausgabe (Format der MM-Messdateien, lesbar mit EIS_Datei_lesen):
%     <Name>.txt / <Name>_Komma.txt                     Parallelschaltung der Zellen
%     <Name>_mitKontakt.txt / _mitKontakt_Komma.txt     Vorhersage der Stackmessung (nur mit 'Kontakte')
%   Ausgewertet wird bei den Frequenzen der ersten Datei; die anderen Messungen werden
%   bei Bedarf ueber log(f) interpoliert (Frequenzen ausserhalb ihres Bereichs entfallen).

    MILLI  = 1e3;
    MARKER = 4;

    p = inputParser;
    addParameter(p, 'Ausgabe', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Kontakte', {});
    addParameter(p, 'Modelle', 'RL_Skin');
    parse(p, varargin{:});

    if nargin < 1 || isempty(zellDateien)
        zellDateien = EIS_Dateien_waehlen('Einzelzellmessungen auswaehlen');
        if isempty(zellDateien)
            erg = [];
            return;
        end
    end
    zellDateien = cellstr(zellDateien);
    n = numel(zellDateien);

    kontaktDateien = cellstr(p.Results.Kontakte);
    mitKontakt = ~isempty(kontaktDateien) && ~isempty(kontaktDateien{1});
    modelle = cellstr(p.Results.Modelle);
    if mitKontakt
        if numel(kontaktDateien) ~= n
            error('EIS_Parallel:kontakte', 'Anzahl der Kontaktdateien (%d) passt nicht zur Anzahl der Zellen (%d)', ...
                  numel(kontaktDateien), n);
        end
        if isscalar(modelle)
            modelle = repmat(modelle, 1, n);
        end
    end

    ausgabe = char(p.Results.Ausgabe);
    if isempty(ausgabe)
        [o, nm] = fileparts(zellDateien{1});
        ausgabe = fullfile(o, [nm '_Parallel.txt']);
    end

    % ---- Zellen bei den Frequenzen der ersten Messung ----
    zellen = cellfun(@EIS_Datei_lesen, zellDateien);
    f = zellen(1).f(:);
    zZ = nan(numel(f), n);
    for k = 1:n
        zZ(:, k) = aufFrequenzen(zellen(k).f, zellen(k).re + 1i * zellen(k).im, f);
    end

    % ---- optional: Kontaktierungen ----
    zK = zeros(numel(f), n);
    kopfKontakt = {};
    if mitKontakt
        for k = 1:n
            kd = EIS_Datei_lesen(kontaktDateien{k});
            zKd = kd.re + 1i * kd.im;
            if strcmp(modelle{k}, 'Messdaten')
                zK(:, k) = aufFrequenzen(kd.f, zKd, f);
                kopfKontakt{end + 1} = sprintf('Kontakt Zelle %d: %s, Messdaten', k, kd.name); %#ok<AGROW>
            else
                [fK, idx] = unique(kd.f);
                km = EIS_Kontakt_Modell(fK, zKd(idx), modelle{k});
                zK(:, k) = km.Z(f);
                kopfKontakt{end + 1} = sprintf('Kontakt Zelle %d: %s, Modell %s: %s', k, kd.name, modelle{k}, km.text); %#ok<AGROW>
            end
        end
    end

    gueltig = all(~isnan(zZ), 2) & all(~isnan(zK), 2);
    if any(~gueltig)
        warning('EIS_Parallel:bereich', '%d Frequenzen liegen nicht in allen Messungen und werden weggelassen', nnz(~gueltig));
    end
    f  = f(gueltig);
    zZ = zZ(gueltig, :);
    zK = zK(gueltig, :);

    zPar = 1 ./ sum(1 ./ zZ, 2);
    erg = struct('f', f, 'Zparallel', zPar, 'Zzellen', zZ);
    if mitKontakt
        zVor = 1 ./ sum(1 ./ (zZ + zK), 2);
        erg.Zvorhersage = zVor;
        erg.Zkontakt = zK;
    end

    % ---- Dateien ----
    kopf = {sprintf('Parallelschaltung von %d Einzelzellmessungen: Z = 1 / Summe 1/Z_k', n)};
    for k = 1:n
        kopf{end + 1} = sprintf('Zelle %d: %s', k, zellen(k).name); %#ok<AGROW>
    end
    [o, nm] = fileparts(ausgabe);
    EIS_Datei_schreiben(fullfile(o, [nm '.txt']), nm, kopf, f, zPar, false);
    EIS_Datei_schreiben(fullfile(o, [nm '_Komma.txt']), nm, kopf, f, zPar, true);
    fprintf('\nParallelschaltung von %d Zellen gespeichert: %s (+ _Komma)\n', n, fullfile(o, [nm '.txt']));
    if mitKontakt
        kopfV = [{sprintf('Vorhersage der Stackmessung: Z = 1 / Summe 1/(Z_Zelle,k + Z_Kontakt,k), %d Zellen', n)}, ...
                 kopf(2:end), kopfKontakt];
        EIS_Datei_schreiben(fullfile(o, [nm '_mitKontakt.txt']), [nm '_mitKontakt'], kopfV, f, zVor, false);
        EIS_Datei_schreiben(fullfile(o, [nm '_mitKontakt_Komma.txt']), [nm '_mitKontakt'], kopfV, f, zVor, true);
        fprintf('Vorhersage mit Kontaktierung gespeichert: %s (+ _Komma)\n', fullfile(o, [nm '_mitKontakt.txt']));
    end

    % ---- Diagramm ----
    fig = figure('Color', 'w', 'Name', 'Parallelschaltung', 'NumberTitle', 'off');
    ax = axes(fig);
    hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    for k = 1:n
        plot(ax, real(zZ(:, k)) * MILLI, -imag(zZ(:, k)) * MILLI, '-o', 'MarkerSize', MARKER, ...
             'DisplayName', zellen(k).name);
    end
    plot(ax, real(zPar) * MILLI, -imag(zPar) * MILLI, '-o', 'MarkerSize', MARKER, 'LineWidth', 1.5, ...
         'DisplayName', 'Parallelschaltung');
    if mitKontakt
        plot(ax, real(zVor) * MILLI, -imag(zVor) * MILLI, '-s', 'MarkerSize', MARKER, 'LineWidth', 1.5, ...
             'DisplayName', 'Vorhersage Stack mit Kontaktierung');
    end
    axis(ax, 'equal');
    xlabel(ax, 'Re(Z) [m\Omega]'); ylabel(ax, '-Im(Z) [m\Omega]');
    title(ax, sprintf('Parallelschaltung von %d Zellen', n));
    legend(ax, 'Location', 'best', 'Interpreter', 'none');
end

% Impedanz bei den Frequenzen fZiel (ueber log10(f) interpoliert, ausserhalb NaN)
function z = aufFrequenzen(fQuelle, zQuelle, fZiel)
    [fq, idx] = unique(fQuelle(:));
    zq = zQuelle(idx);
    z = interp1(log10(fq), real(zq), log10(fZiel), 'linear') + ...
        1i * interp1(log10(fq), imag(zq), log10(fZiel), 'linear');
end
