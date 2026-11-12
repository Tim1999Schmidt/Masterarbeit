function km = EIS_Kontakt_Modell(f, z, modell)
% EIS_Kontakt_Modell  Passt ein Ersatzschaltbild an die Impedanz einer Kontaktierung an
%
%   km = EIS_Kontakt_Modell(f, z, modell)
%     f      Frequenzen [Hz]
%     z      komplexe Impedanz der Kontaktierung [Ohm] (Im induktiv positiv)
%     modell 'RL_Skin' (Standard), 'RL_parallel_C' oder 'RLC_seriell'
%
%   Modelle:
%     RL_Skin       R0 + jwL0 + (R1 || L1)
%                   R0, L0: Gleichstromwiderstand und Induktivitaet der Leitungen/Kontakte.
%                   R1 || L1 bildet die Stromverdraengung (Skin-/Proximity-Effekt) nach:
%                   bei tiefen Frequenzen wirkt der Zweig wie L1 (Gesamtinduktivitaet
%                   L0 + L1), oberhalb der Eckfrequenz R1/(2*pi*L1) zunehmend wie R1,
%                   Re(Z) steigt mit der Frequenz an. Keine Kapazitaet.
%     RL_parallel_C (R + jwL) || C
%     RLC_seriell   R + jwL + 1/(jwC)
%
%   Rueckgabe (Struktur):
%     km.modell     Name des Modells
%     km.namen      Parameternamen, z. B. {'R0','L0','R1','L1'}
%     km.werte      Parameterwerte in SI-Einheiten (Ohm, H, F)
%     km.Z          Funktion @(f) -> Impedanz des Modells bei beliebigen Frequenzen
%     km.zFit       Modellimpedanz bei f
%     km.fehlerRms  Restfehler (RMS) [Ohm]
%     km.text       Parameter als lesbarer Text (mOhm, nH, uF)
%     km.hinweis    Hinweis zur Bestimmbarkeit ('' wenn unauffaellig)
%
%   Die Anpassung laeuft mit fminsearch (keine Toolbox noetig) ueber den Logarithmus
%   der Parameter, sodass alle Werte positiv bleiben.

    if nargin < 3 || isempty(modell)
        modell = 'RL_Skin';
    end
    SIGNIFIKANZ      = 0.01;     % Einfluss eines Teilzweigs unter 1 % von |Z|: nicht bestimmbar
    ECKE_FAKTOR      = 10;       % Eckfrequenz > 10 x f_max: Aufteilung R1/L1 unsicher
    MAX_SCHRITTE     = 4e4;

    f = f(:);  z = z(:);
    w = 2 * pi * f;
    tief = f <= median(f);                              % untere Haelfte der Frequenzen fuer die Startwerte

    % ---- Startwerte aus dem tieffrequenten Verhalten R + jwL ----
    R0 = mean(real(z(tief)));
    Lt = sum(w(tief) .* imag(z(tief))) / sum(w(tief) .^ 2);
    if R0 <= 0
        warning('EIS_Kontakt_Modell:R', 'Re(Z) ist bei tiefen Frequenzen nicht positiv (%.3g Ohm)', R0);
        R0 = max(abs(R0), eps);
    end
    Lt = max(Lt, eps);

    switch modell
        case 'RL_Skin'
            [~, iMax] = max(f);
            anstieg = max(real(z(iMax)) - R0, R0 * 1e-3);  % Anstieg von Re bis f_max
            R1 = 2 * anstieg;
            L1 = R1 / max(w);                               % Eckfrequenz am oberen Rand
            L0 = max(Lt - L1, Lt / ECKE_FAKTOR);
            start = [R0, L0, R1, L1];
            namen = {'R0', 'L0', 'R1', 'L1'};
            zm = @(q, ww) q(1) + 1i * ww * q(2) + (q(3) * 1i * ww * q(4)) ./ (q(3) + 1i * ww * q(4));
        case 'RL_parallel_C'
            start = [R0, Lt, 1 / (max(w) ^ 2 * Lt) / 100];  % Resonanz weit oberhalb
            namen = {'R', 'L', 'C'};
            zm = @(q, ww) (q(1) + 1i * ww * q(2)) ./ (1 + 1i * ww * q(3) .* (q(1) + 1i * ww * q(2)));
        case 'RLC_seriell'
            imMin = imag(z(find(w == min(w), 1)));
            if imMin < 0
                C0 = -1 / (min(w) * imMin);
            else
                C0 = 100 / (min(w) * R0);                   % praktisch ohne Einfluss
            end
            start = [R0, Lt, C0];
            namen = {'R', 'L', 'C'};
            zm = @(q, ww) q(1) + 1i * ww * q(2) + 1 ./ (1i * ww * q(3));
        otherwise
            error('EIS_Kontakt_Modell:modell', 'Unbekanntes Modell "%s" (RL_Skin, RL_parallel_C, RLC_seriell)', modell);
    end

    skala = mean(abs(z)) ^ 2;                               % Zielfunktion ~ 1
    ziel  = @(lq) sum(abs(zm(exp(lq), w) - z) .^ 2) / skala;
    opt   = optimset('MaxFunEvals', MAX_SCHRITTE, 'MaxIter', MAX_SCHRITTE, ...
                     'TolX', 1e-10, 'TolFun', 1e-15, 'Display', 'off');
    q = exp(fminsearch(ziel, log(start), opt));

    km.modell    = modell;
    km.namen     = namen;
    km.werte     = q;
    km.Z         = @(ff) zm(q, 2 * pi * ff(:));
    km.zFit      = zm(q, w);
    km.fehlerRms = sqrt(mean(abs(km.zFit - z) .^ 2));

    % ---- Text und Bestimmbarkeit ----
    switch modell
        case 'RL_Skin'
            fEcke = q(3) / (2 * pi * q(4));
            km.text = sprintf('R0 = %.4f mOhm, L0 = %.2f nH, R1 = %.4f mOhm, L1 = %.2f nH (L0+L1 = %.2f nH, Eckfrequenz %.3g Hz)', ...
                              q(1) * 1e3, q(2) * 1e9, q(3) * 1e3, q(4) * 1e9, (q(2) + q(4)) * 1e9, fEcke);
            zweig  = (q(3) * 1i * w * q(4)) ./ (q(3) + 1i * w * q(4));
            einfluss = max(abs(zweig - 1i * w * q(4)) ./ abs(km.zFit));
            if einfluss < SIGNIFIKANZ
                km.hinweis = sprintf(['Stromverdraengung im Messbereich nicht erkennbar (Einfluss %.2g %%): ' ...
                                      'R1 und L1 nicht einzeln bestimmbar, nur L0+L1'], einfluss * 100);
            elseif fEcke > ECKE_FAKTOR * max(f)
                km.hinweis = sprintf('Eckfrequenz %.3g Hz weit oberhalb des Messbereichs: Aufteilung R1/L1 unsicher', fEcke);
            else
                km.hinweis = '';
            end
        otherwise
            km.text = sprintf('R = %.4f mOhm, L = %.2f nH, C = %.4g uF', q(1) * 1e3, q(2) * 1e9, q(3) * 1e6);
            einfluss = max(abs(km.zFit - (q(1) + 1i * w * q(2))) ./ abs(km.zFit));
            if einfluss < SIGNIFIKANZ
                km.hinweis = sprintf('C nicht bestimmbar (Einfluss im Messbereich %.2g %%)', einfluss * 100);
            else
                km.hinweis = '';
            end
    end
end
