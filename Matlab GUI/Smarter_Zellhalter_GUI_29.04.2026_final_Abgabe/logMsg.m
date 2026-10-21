% Funktion schreibt gewünschten Text mit Zeitstempel in neue Zeile des logMsg
function logMsg(handles, msg)
        % Zeitstempel + an bestehendes Log anhängen
        old = get(handles.log,'String');
        if ischar(old), old = cellstr(old); end
        ts = datestr(now,'HH:MM:SS');
        newLines = [old; {sprintf('[%s] %s',ts,msg)}];
        set(handles.log,'Enable','on');       % kurz aktivieren, um Text zu setzen
        set(handles.log,'String',newLines);
        set(handles.log, 'Value', numel(newLines));% <<--- scrollt automatisch nach unten
        drawnow;
        set(handles.log,'Enable','inactive'); % wieder schreibgeschützt
    end