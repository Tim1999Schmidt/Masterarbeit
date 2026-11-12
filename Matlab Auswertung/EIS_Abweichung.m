function ergebnis = EIS_Abweichung(referenzDatei, messDatei)
% EIS_Abweichung  Absolute und relative Abweichung zweier EIS-Messungen ueber der Frequenz
%
%   EIS_Abweichung
%       Dateiauswahl: zuerst die Referenz, dann die zu bewertende Messung
%   EIS_Abweichung(referenzDatei, messDatei)
%   ergebnis = EIS_Abweichung(...)
%       Tabelle mit allen Werten (z. B. fuer writetable)
%
%   Abweichung = Messung - Referenz, ausgewertet bei den Frequenzen der Messung. Liegen die
%   Frequenzen der Referenz anders (z. B. Potentiostat), wird die Referenz dort linear ueber
%   log(f) interpoliert; Frequenzen ausserhalb des Referenzbereichs werden weggelassen.
%
%   Dargestellt (Frequenzachse logarithmisch):
%     oben  - absolute Abweichung in mOhm von Re(Z), Im(Z) und |Z|
%     unten - relative Abweichung in Prozent:
%               Re(Z): bezogen auf Re(Z) der Referenz
%               Im(Z): bezogen auf |Z| der Referenz (Im(Z) geht durch null, ein Bezug auf
%                      Im(Z) selbst waere dort unendlich gross)
%               |Z|  : bezogen auf |Z| der Referenz
%
%   Dateiformate: siehe EIS_Datei_lesen.

    MILLI_PER_UNIT   = 1e3;
    PERCENT_PER_UNIT = 100;
    MARKER_SIZE      = 4;

    if nargin < 2
        [referenzDatei, messDatei] = dateienWaehlen();
        if isempty(referenzDatei)
            ergebnis = [];
            return;
        end
    end
    ref  = EIS_Datei_lesen(referenzDatei);
    mess = EIS_Datei_lesen(messDatei);

    % Referenz bei den Frequenzen der Messung (interpoliert ueber log10(f))
    [fRef, idx] = unique(ref.f);
    reRef = ref.re(idx);
    imRef = ref.im(idx);
    imBereich = mess.f >= min(fRef) & mess.f <= max(fRef);
    if ~any(imBereich)
        error('EIS_Abweichung:bereich', 'Die Frequenzbereiche der beiden Messungen ueberlappen nicht');
    end
    if any(~imBereich)
        warning('EIS_Abweichung:bereich', '%d Frequenzen der Messung liegen ausserhalb der Referenz und werden weggelassen', ...
                nnz(~imBereich));
    end
    f   = mess.f(imBereich);
    re  = mess.re(imBereich);
    im  = mess.im(imBereich);
    reR = interp1(log10(fRef), reRef, log10(f), 'linear');
    imR = interp1(log10(fRef), imRef, log10(f), 'linear');
    absZ  = hypot(re, im);
    absZR = hypot(reR, imR);

    % Abweichungen
    dRe  = re - reR;
    dIm  = im - imR;
    dAbs = absZ - absZR;
    dRePct  = dRe  ./ reR   * PERCENT_PER_UNIT;
    dImPct  = dIm  ./ absZR * PERCENT_PER_UNIT;
    dAbsPct = dAbs ./ absZR * PERCENT_PER_UNIT;

    ergebnis = table(f, dRe * MILLI_PER_UNIT, dIm * MILLI_PER_UNIT, dAbs * MILLI_PER_UNIT, ...
                     dRePct, dImPct, dAbsPct, ...
                     'VariableNames', {'f_Hz', 'dRe_mOhm', 'dIm_mOhm', 'dAbsZ_mOhm', ...
                                       'dRe_Prozent', 'dIm_Prozent_von_absZ', 'dAbsZ_Prozent'});

    % ---- Diagramme ----
    fig = figure('Color', 'w', 'Name', 'EIS-Abweichung', 'NumberTitle', 'off');
    titel = sprintf('%s  gegen Referenz  %s', mess.name, ref.name);

    axAbs = subplot(2, 1, 1, 'Parent', fig);
    semilogx(axAbs, f, ergebnis.dRe_mOhm, '-o', f, ergebnis.dIm_mOhm, '-s', f, ergebnis.dAbsZ_mOhm, '-^', ...
             'MarkerSize', MARKER_SIZE);
    nullLinie(axAbs);
    grid(axAbs, 'on');
    ylabel(axAbs, 'Abweichung [m\Omega]');
    title(axAbs, {'Absolute Abweichung (Messung - Referenz)', titel}, 'Interpreter', 'none');
    legend(axAbs, {'\DeltaRe(Z)', '\DeltaIm(Z)', '\Delta|Z|'}, 'Location', 'best');

    axRel = subplot(2, 1, 2, 'Parent', fig);
    semilogx(axRel, f, dRePct, '-o', f, dImPct, '-s', f, dAbsPct, '-^', 'MarkerSize', MARKER_SIZE);
    nullLinie(axRel);
    grid(axRel, 'on');
    xlabel(axRel, 'f [Hz]');
    ylabel(axRel, 'Abweichung [%]');
    title(axRel, 'Relative Abweichung');
    legend(axRel, {'\DeltaRe / Re_{Ref}', '\DeltaIm / |Z_{Ref}|', '\Delta|Z| / |Z_{Ref}|'}, 'Location', 'best');
    linkaxes([axAbs, axRel], 'x');

    % ---- Zusammenfassung im Befehlsfenster ----
    fprintf('\n%s\n', titel);
    fprintf('%d Frequenzen von %.3g Hz bis %.3g Hz\n', numel(f), min(f), max(f));
    fprintf('%-24s %12s %12s\n', '', 'Mittel |.|', 'Maximum |.|');
    zeile('Re(Z)  [%]',          dRePct);
    zeile('Im(Z)  [% von |Z|]',  dImPct);
    zeile('|Z|    [%]',          dAbsPct);
    zeile('Re(Z)  [mOhm]',       dRe  * MILLI_PER_UNIT);
    zeile('Im(Z)  [mOhm]',       dIm  * MILLI_PER_UNIT);
    zeile('|Z|    [mOhm]',       dAbs * MILLI_PER_UNIT);
end

function zeile(name, werte)
    fprintf('%-24s %12.4g %12.4g\n', name, mean(abs(werte)), max(abs(werte)));
end

function nullLinie(ax)
    hold(ax, 'on');
    plot(ax, xlim(ax), [0 0], 'k-', 'LineWidth', 0.5, 'HandleVisibility', 'off');
    hold(ax, 'off');
end

function [referenz, messung] = dateienWaehlen()
    FILTER = {'*.txt;*.csv;*.xlsx;*.xls', 'EIS-Messdaten (*.txt, *.csv, *.xlsx)'};
    referenz = '';
    messung  = '';
    [n, o] = uigetfile(FILTER, '1/2: Referenzmessung auswaehlen');
    if isequal(n, 0)
        return;
    end
    referenz = fullfile(o, n);
    [n, o] = uigetfile(FILTER, '2/2: zu bewertende Messung auswaehlen', o);
    if isequal(n, 0)
        referenz = '';
        return;
    end
    messung = fullfile(o, n);
end
