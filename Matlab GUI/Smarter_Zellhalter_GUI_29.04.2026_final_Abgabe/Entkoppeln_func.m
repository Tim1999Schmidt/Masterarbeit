function Entkoppeln_func (handles)

    logMsg(handles, 'Zellen werden entkoppelt'); %Funktionsaufruf um etwas in das logMsg zu schreiben

    % setzt die Checkboxen für Verschaltung zurück
    set(handles.Z1_direkt, 'Value', 0);
    set(handles.Z1_R, 'Value', 0);
    set(handles.Z1_GND, 'Value', 0);
    set(handles.Z2_direkt, 'Value', 0);
    set(handles.Z2_R, 'Value', 0);
    set(handles.Z2_GND, 'Value', 0);
    set(handles.Z3_direkt, 'Value', 0);
    set(handles.Z3_R, 'Value', 0);
    set(handles.Z3_GND, 'Value', 0);

    Auslesewerte = [0, 0, 0, 0, 0, 0, 0, 0, 0];

    Verschalten_func (handles, Auslesewerte);

end