function fig = EIS_Nyquist_Vergleich(varargin)
% EIS_Nyquist_Vergleich  Mehrere EIS-Messungen in einem gemeinsamen Nyquist-Diagramm
%
%   EIS_Nyquist_Vergleich
%       Dateiauswahl (mehrere Dateien mit Strg/Shift, auch aus verschiedenen Ordnern,
%       siehe EIS_Dateien_waehlen)
%   EIS_Nyquist_Vergleich(datei1, datei2, ...)   oder   EIS_Nyquist_Vergleich({datei1, datei2, ...})
%   EIS_Nyquist_Vergleich(..., 'Legende', {'Messung A', 'Messung B'})
%       eigene Legendentexte (Standard: Dateinamen)
%   EIS_Nyquist_Vergleich(..., 'Frequenzen', false)
%       Start- und Endfrequenz nicht beschriften (Standard: true)
%   fig = EIS_Nyquist_Vergleich(...)
%       gibt die Figure zurueck (z. B. fuer exportgraphics)
%
%   Dateiformate: siehe EIS_Datei_lesen (Messdateien der MM-GUI, CSV/Excel vom Potentiostaten).
%   Darstellung: -Im(Z) ueber Re(Z) in mOhm, gleiche Achsenskalierung. Beim Ueberfahren
%   eines Punkts zeigt der Datentipp auch die Frequenz.

    MILLI_PER_UNIT  = 1e3;
    MARKER_SIZE     = 4;
    LABEL_FONT_SIZE = 8;
    HZ_PER_KHZ      = 1e3;

    [dateien, legende, mitFrequenzen] = argumenteLesen(varargin);
    if isempty(dateien)
        fig = [];
        return;
    end

    fig = figure('Color', 'w', 'Name', 'Nyquist-Vergleich', 'NumberTitle', 'off');
    ax = axes(fig);
    hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

    for k = 1:numel(dateien)
        d = EIS_Datei_lesen(dateien{k});
        x = d.re * MILLI_PER_UNIT;
        y = -d.im * MILLI_PER_UNIT;
        if ~isempty(legende)
            name = legende{k};
        else
            name = d.name;
        end
        h = plot(ax, x, y, '-o', 'MarkerSize', MARKER_SIZE, 'DisplayName', name);
        h.UserData = d.f;
        frequenzDatentipp(h);
        if mitFrequenzen
            beschrifte(ax, x(1),   y(1),   d.f(1),   h.Color);
            beschrifte(ax, x(end), y(end), d.f(end), h.Color);
        end
    end

    axis(ax, 'equal');
    xlabel(ax, 'Re(Z) [m\Omega]');
    ylabel(ax, '-Im(Z) [m\Omega]');
    title(ax, 'Nyquist-Diagramm');
    legend(ax, 'show', 'Location', 'best', 'Interpreter', 'none');

    % ---- lokale Hilfsfunktionen (nutzen die Konstanten oben) ----
    function beschrifte(a, xp, yp, fHz, farbe)
        text(a, xp, yp, ['  ' frequenzText(fHz)], 'Color', farbe, 'FontSize', LABEL_FONT_SIZE, ...
             'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', 'Clipping', 'on');
    end

    function s = frequenzText(fHz)
        if fHz >= HZ_PER_KHZ
            s = sprintf('%.3g kHz', fHz / HZ_PER_KHZ);
        else
            s = sprintf('%.3g Hz', fHz);
        end
    end
end

% Datentipp: Re, -Im und Frequenz (Frequenzen stehen in UserData der Kurve); der Text als
% CreateFcn sorgt dafuer, dass er auch in einer gespeicherten .fig wieder gesetzt wird
function frequenzDatentipp(h)
    code = ['try, h = gcbo; h.DataTipTemplate.DataTipRows = [' ...
            'dataTipTextRow(''Re(Z) [m\Omega]'', ''XData''), ' ...
            'dataTipTextRow(''-Im(Z) [m\Omega]'', ''YData''), ' ...
            'dataTipTextRow(''f [Hz]'', h.UserData(:).'')]; catch, end'];
    h.CreateFcn = code;
    try                                                 % DataTipTemplate ab R2019a
        h.DataTipTemplate.DataTipRows = [ ...
            dataTipTextRow('Re(Z) [m\Omega]', 'XData'), ...
            dataTipTextRow('-Im(Z) [m\Omega]', 'YData'), ...
            dataTipTextRow('f [Hz]', h.UserData(:).')];
    catch
    end
end

function [dateien, legende, mitFrequenzen] = argumenteLesen(args)
    legende = {};
    mitFrequenzen = true;
    dateien = {};
    k = 1;
    while k <= numel(args)
        a = args{k};
        if (ischar(a) || isstring(a)) && any(strcmpi(a, {'Legende', 'Frequenzen'})) && k < numel(args)
            if strcmpi(a, 'Legende')
                legende = cellstr(args{k + 1});
            else
                mitFrequenzen = logical(args{k + 1});
            end
            k = k + 2;
            continue;
        end
        if iscell(a) || isstring(a)
            dateien = [dateien, cellstr(a)]; %#ok<AGROW>
        else
            dateien{end + 1} = a; %#ok<AGROW>
        end
        k = k + 1;
    end

    if isempty(dateien)
        dateien = EIS_Dateien_waehlen('EIS-Messungen auswaehlen');
        if isempty(dateien)
            return;                                     % abgebrochen
        end
    end
    if ~isempty(legende) && numel(legende) ~= numel(dateien)
        error('EIS_Nyquist_Vergleich:legende', 'Anzahl der Legendentexte (%d) passt nicht zur Anzahl der Dateien (%d)', ...
              numel(legende), numel(dateien));
    end
end
