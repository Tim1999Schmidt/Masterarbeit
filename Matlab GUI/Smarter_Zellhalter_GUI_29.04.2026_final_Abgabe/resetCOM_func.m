%% Warscheinlich brauche ich diese Funktion nicht

function resetCOM_func
    % Legacy-Objekte (serial) schließen/löschen
    o = instrfind;
    if ~isempty(o), fclose(o); delete(o); end

    % Alle serialport-Objekte im Base-Workspace löschen (setzt COM wirklich frei)
    ws = evalin('base','whos');
    for k = 1:numel(ws)
        if strcmp(ws(k).class,'serialport')
            evalin('base', ['clear ', ws(k).name]);
        end
    end

    pause(1); % kurze Wartezeit für Windows/USB-Stack
end
% resetCOM_func