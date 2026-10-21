function Koppeln_func (handles)

    logMsg(handles, 'Zellen werden gekoppelt'); %Funktionsaufruf um etwas in das logMsg zu schreiben

    Auslesewerte = [0, 0, 0, 0, 0, 0, 0, 0, 0];

    Auslesewerte(1) = get(handles.Z1_direkt, 'Value');
    Auslesewerte(2) = get(handles.Z1_R, 'Value');
    Auslesewerte(3) = get(handles.Z1_GND, 'Value');
    Auslesewerte(4) = get(handles.Z2_direkt, 'Value');
    Auslesewerte(5) = get(handles.Z2_R, 'Value');
    Auslesewerte(6) = get(handles.Z2_GND, 'Value');
    Auslesewerte(7) = get(handles.Z3_direkt, 'Value');
    Auslesewerte(8) = get(handles.Z3_R, 'Value');
    Auslesewerte(9) = get(handles.Z3_GND, 'Value');

    Verschalten_func (handles, Auslesewerte);

end