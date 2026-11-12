function EIS_Datei_schreiben(datei, titel, kopf, f, z, dezimalKomma)
% EIS_Datei_schreiben  Schreibt Impedanzdaten im Format der MM-Messdateien
%
%   EIS_Datei_schreiben(datei, titel, kopf, f, z)
%   EIS_Datei_schreiben(datei, titel, kopf, f, z, true)   mit Dezimalkomma (Excel)
%
%     titel  erste Kopfzeile
%     kopf   weitere Kopfzeilen (Zellarray von Texten), jeweils mit '# ' vorangestellt
%     f      Frequenzen [Hz]
%     z      komplexe Impedanz [Ohm] (Im induktiv positiv)
%
%   Aufbau: Kopfzeilen mit '#', Leerzeile, Spalten freq/Hz, Re(Z)/Ohm, Im(Z)/Ohm.
%   Lesbar mit EIS_Datei_lesen.

    if nargin < 6
        dezimalKomma = false;
    end
    text = sprintf('# %s\n# \n', titel);
    for k = 1:numel(kopf)
        text = [text, sprintf('# %s\n', kopf{k})]; %#ok<AGROW>
    end
    text = [text, sprintf('\n  %10s\t%14s\t%14s\n', 'freq/Hz', 'Re(Z)/Ohm', 'Im(Z)/Ohm')];
    for k = 1:numel(f)
        text = [text, sprintf('%12.2f\t%14.8f\t%14.8f\n', f(k), real(z(k)), imag(z(k)))]; %#ok<AGROW>
    end
    if dezimalKomma
        text = strrep(text, '.', ',');
    end
    fid = fopen(datei, 'w');
    assert(fid > 0, 'Konnte Datei nicht schreiben: %s', datei);
    fwrite(fid, text, 'char');
    fclose(fid);
end
