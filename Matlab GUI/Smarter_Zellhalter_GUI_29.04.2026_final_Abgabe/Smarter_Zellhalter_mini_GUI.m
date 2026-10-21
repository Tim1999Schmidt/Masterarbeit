function handles = Smarter_Zellhalter_mini_GUI()
    

    %% alte Fenster schließen
    figs = findall(0, 'Type', 'figure');  % alle offenen Figuren finden
    for i = 1:length(figs)
        figName = get(figs(i), 'Name');
        if ischar(figName) && startsWith(figName, 'Smarter_Zellhalter_GUI_')
            close(figs(i));
        end
    end

    %% Fenster öffnen
    fig = figure('Name', 'Smarter_Zellhalter_GUI_v1.1', ...
                 'NumberTitle', 'off', ...
                 'Position', [100 100 1000 600], ...
                 'MenuBar', 'none', ...
                 'Resize', 'on', ...          % <-- Fenstergrößenänderung erlauben
                 'WindowState', 'normal');    % <-- Maximieren möglich (Standard)

    %% Beschriftung (Label)
uicontrol(fig,'Style','text','String','Smarter_Zellhalter_mini_GUI','FontSize',16,'FontWeight','bold','Position',[6.67 561 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Einstellungen EIS-Messung:','FontSize',11,'FontWeight','bold','Position',[6.67 253.33 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Zielordner:','FontSize',10,'FontWeight','bold','Position',[66.67 200.00 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Filename:','FontSize',10,'FontWeight','bold','Position',[66.67 166.67 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Kommentar:','FontSize',10,'FontWeight','bold','Position',[66.67 133.33 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Name Z1:','FontSize',10,'FontWeight','bold','Position',[66.67 100.00 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Name Z2:','FontSize',10,'FontWeight','bold','Position',[66.67 66.67 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Name Z3:','FontSize',10,'FontWeight','bold','Position',[66.67 33.33 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','EIS_Chip:','FontSize',10,'FontWeight','bold','Position',[600.00 200.00 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Start_Frequenz:','FontSize',10,'FontWeight','bold','Position',[600.00 166.67 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Stopp_Frequenz:','FontSize',10,'FontWeight','bold','Position',[600.00 133.33 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Amplitude:','FontSize',10,'FontWeight','bold','Position',[600.00 100.00 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Signalform:','FontSize',10,'FontWeight','bold','Position',[600.00 66.67 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Mittelung über:','FontSize',10,'FontWeight','bold','Position',[600.00 33.33 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Verschaltung:','FontSize',10,'FontWeight','bold','Position',[600.00 0.00 333.33 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Spg_Z1:                    mV','FontSize',10,'FontWeight','bold','Position',[406.67 505.33 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Spg_Z2:                    mV','FontSize',10,'FontWeight','bold','Position',[406.67 478.67 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String','Spg_Z3:                    mV','FontSize',10,'FontWeight','bold','Position',[406.67 452.00 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' Str_Z1:                    mA','FontSize',10,'FontWeight','bold','Position',[406.67 425.33 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' Str_Z2:                    mA','FontSize',10,'FontWeight','bold','Position',[406.67 398.67 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' Str_Z3:                    mA','FontSize',10,'FontWeight','bold','Position',[406.67 372.00 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' R_S1:                      mΩ','FontSize',10,'FontWeight','bold','Position',[406.67 345.33 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' R_S2:                      mΩ','FontSize',10,'FontWeight','bold','Position',[406.67 318.67 186.67 33.33], 'HorizontalAlignment','left');

uicontrol(fig,'Style','text','String',' R_S3:                      mΩ','FontSize',10,'FontWeight','bold','Position',[406.67 292.00 186.67 33.33], 'HorizontalAlignment','left');

    %% Symbole Zeichnen
    ax = axes('Parent', fig, 'Units','pixels', 'Position',[600 333.33 333.33 200]);
    set(ax,'XLim',[0 133.33],'YLim',[0 100],'XTick',[],'YTick',[], 'Visible','on','Box','on');
    axis(ax,'manual'); axis(ax,'ij');

    w = 26.66; hgt = 53.33; y = 26.66;
    hZ.Z1 = rectangle(ax,'Position',[13.33  y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,13.33+w/2,y+hgt/2,'Z1','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',16.66);

    hZ.Z2 = rectangle(ax,'Position',[53.33  y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,53.33+w/2,y+hgt/2,'Z2','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',16.66);

    hZ.Z3 = rectangle(ax,'Position',[93.33 y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,93.33+w/2,y+hgt/2,'Z3','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',16.66);

    % Schwarze Linie über den drei Rechtecken
    hZ.L_Plus = line(ax, [6.67 116.67], [13.33 13.33],'Color', [0 0 0],'LineWidth', 6.66);

    hZ.L_Minus = line(ax, [6.67 116.67], [93.33 93.33],'Color', [0 0 0],'LineWidth', 6.66);

    hZ.L_Z1_d = line(ax, [18.67 18.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z1_R = line(ax, [34.67 34.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z1_GND = line(ax, [26.67 26.67], [80.67 90.67],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z2_d = line(ax, [58.67 58.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z2_R = line(ax, [74.67 74.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z2_GND = line(ax, [66.67 66.67], [80.67 90.67],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z3_d = line(ax, [98.67 98.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z3_R = line(ax, [114.67 114.67], [16 26],'Color', [1 1 1],'LineWidth', 6.66);

    hZ.L_Z3_GND = line(ax, [106.67 106.67], [80.67 90.67],'Color', [1 1 1],'LineWidth', 6.66);

    handles.hZ = hZ; % wird benötigt damit hZ Objekte in anderen Funktionen geändert werden können

    %% Log-Ausgabe (mehrzeiliges Textfeld, nur lesen)
    handles.log = uicontrol(fig,'Style','listbox','Max',2,'Min',0, ...
        'Position',[13.33 333.33 386.66 200], 'HorizontalAlignment','left', ...
        'FontName','Consolas','BackgroundColor',[1 1 1], ...
        'TooltipString','Protokoll der Aktionen', ...
        'Enable','inactive','String','', 'FontSize', 8);

    %% Ausklappbare Auswahl (Popup-Menü)
    Werte_COM = {'COM 1','COM 2','COM 3','COM 4','COM 5','COM 6','COM 7','COM 8','COM 9','COM 10','COM 11','COM 12'};
    handles.COM = uicontrol(fig,'Style','popupmenu','String',Werte_COM, ...
        'Position',[320 560 66.67 33.33],'FontSize',10);

    Werte_Amplitude = {'50 mA','100 mA','200 mA','300 mA','400 mA','500 mA'};
    handles.Amplitude = uicontrol(fig,'Style','popupmenu','String',Werte_Amplitude, ...
        'Position',[733.33 100 146.67 33.33],'FontSize',10);

    Werte_SinRec = {'Sinus','Rechteck'};
    handles.SinRec = uicontrol(fig,'Style','popupmenu','String',Werte_SinRec, ...
        'Position',[733.33 66.67 146.67 33.33],'FontSize',10);

    Werte_Mittelung = {'1','2','3','4','5','6','7','8','9','10'};
    handles.Mittelung = uicontrol(fig,'Style','popupmenu','String',Werte_Mittelung, ...
        'Position',[733.33 33.33 146.67 33.33],'FontSize',10);

    Werte_frq = {'(FIS   0) 7812.50 Hz','(FIS   1) 6250.00 Hz','(FIS   2) 5208.33 Hz','(FIS   3) 4464.29 Hz',...
                 '(FIS   4) 3906.25 Hz','(FIS   5) 3125.00 Hz','(FIS   6) 2604.17 Hz','(FIS   7) 2232.14 Hz',...
                 '(FIS   8) 1953.13 Hz','(FIS   9) 1562.50 Hz','(FIS 10) 1302.08 Hz','(FIS 11) 1116.07 Hz',...
                 '(FIS 12)   976.56 Hz','(FIS 13)   781.25 Hz','(FIS 14)   651.04 Hz','(FIS 15)   558.04 Hz',...
                 '(FIS 16)   488.28 Hz','(FIS 17)   390.63 Hz','(FIS 18)   325.52 Hz','(FIS 19)   279.02 Hz',...
                 '(FIS 20)   244.14 Hz','(FIS 21)   195.31 Hz','(FIS 22)   162.76 Hz','(FIS 23)   139.51 Hz',...
                 '(FIS 24)   122.07 Hz','(FIS 25)     97.66 Hz','(FIS 26)     81.38 Hz','(FIS 27)     69.75 Hz',...
                 '(FIS 28)     61.04 Hz','(FIS 29)     48.83 Hz','(FIS 30)     40.69 Hz','(FIS 31)     34.88 Hz',...
                 '(FIS 32)     30.52 Hz','(FIS 33)     24.41 Hz','(FIS 34)     20.35 Hz','(FIS 35)     17.44 Hz',...
                 '(FIS 36)     15.26 Hz','(FIS 37)     12.21 Hz','(FIS 38)     10.17 Hz','(FIS 39)       8.72 Hz',...
                 '(FIS 40)       7.63 Hz','(FIS 41)       6.10 Hz','(FIS 42)       5.09 Hz','(FIS 43)       4.36 Hz',...
                 '(FIS 44)       3.81 Hz','(FIS 45)       3.05 Hz','(FIS 46)       2.54 Hz','(FIS 47)       2.18 Hz',...
                 '(FIS 48)       1.91 Hz','(FIS 49)       1.53 Hz','(FIS 50)       1.27 Hz','(FIS 51)       1.09 Hz'};
    handles.start_frq = uicontrol(fig,'Style','popupmenu','String',Werte_frq, ...
        'Position',[733.33 166.67 146.67 33.33],'FontSize',10);
    handles.stopp_frq = uicontrol(fig,'Style','popupmenu','String',Werte_frq, ...
        'Position',[733.33 133.33 146.67 33.33],'FontSize',10);

    Werte_EIS_Chip = {'EIS_Chip_1','EIS_Chip_2','EIS_Chip_3'};
    handles.EIS_Chip = uicontrol(fig,'Style','popupmenu','String',Werte_EIS_Chip, ...
        'Position',[733.33 200 146.67 33.33],'FontSize',10);

    Werte_Verschaltung = {'individuel','einzeln','Z1 || Z2','Z1 || Z3','Z2 || Z3','Z1 || Z2 || Z3'};
    handles.Verschaltung = uicontrol(fig,'Style','popupmenu','String',Werte_Verschaltung, ...
        'Position',[733.33 0 146.67 33.33],'FontSize',10);

    %% Checkbox (Kästchen zum Ankreuzen)

    handles.Z1_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[653.33 481.33 26.67 20],'FontSize',10);
    handles.Z1_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[693.33 481.33 30 20],'FontSize',10);
    handles.Z1_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[673.33 352 50 20],'FontSize',10);

    handles.Z2_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[753.33 481.33 26.67 20],'FontSize',10);
    handles.Z2_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[793.33 481.33 30 20],'FontSize',10);
    handles.Z2_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[773.33 352 50 20],'FontSize',10);

    handles.Z3_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[853.33 481.33 26.67 20],'FontSize',10);
    handles.Z3_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[893.33 481.33 30 20],'FontSize',10);
    handles.Z3_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[873.33 352 50 20],'FontSize',10);

    %% Textfeld (Eingabe)
    handles.Zielordner = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 213.33 400 20],'FontSize',10);
    
    handles.Filename = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 180 400 20],'FontSize',10);

    handles.Kommentar = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 146.67 400 20],'FontSize',10);    

    handles.Zellenname_Z1 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 113.33 400 20],'FontSize',10);

    handles.Zellenname_Z2 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 80 400 20],'FontSize',10);

    handles.Zellenname_Z3 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[166.67 46.67 400 20],'FontSize',10);

    %% Textfeld (Ausgabe)
    handles.Text_Spg_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 520 66.67 20],'FontSize',10);

    handles.Text_Spg_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 493.33 66.67 20],'FontSize',10);   

    handles.Text_Spg_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 466.67 66.67 20],'FontSize',10);   

    handles.Text_Str_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 440 66.67 20],'FontSize',10);

    handles.Text_Str_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 413.33 66.67 20],'FontSize',10);   

    handles.Text_Str_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 386.67 66.67 20],'FontSize',10);

    handles.Text_Kontakt_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 360 66.67 20],'FontSize',10);

    handles.Text_Kontakt_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 333.33 66.67 20],'FontSize',10);   

    handles.Text_Kontakt_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[466.67 306.67 66.67 20],'FontSize',10);   

    %% Button
    handles.Connect = uicontrol(fig,'Style','pushbutton','String','Connect', ...
        'Position',[393.33 570.67 86.67 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Connect'));

    handles.Entkoppeln = uicontrol(fig,'Style','pushbutton','String','Entkoppeln', ...
        'Position',[533.33 570.67 106.67 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Entkoppeln'));
    
    handles.Koppeln = uicontrol(fig,'Style','pushbutton','String','Koppeln', ...
        'Position',[646.67 570.67 106.67 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Zellen_Check'));

    handles.Zellen_Check = uicontrol(fig,'Style','pushbutton','String','Zellen-Check', ...
        'Position',[760 570.67 106.67 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Zellen_Check'));

    handles.Kontakt_Check = uicontrol(fig,'Style','pushbutton','String','Kontakt-Check', ...
        'Position',[873.33 570.67 106.67 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Kontakt_Check'));

    %handles.Ausgleich_Start = uicontrol(fig,'Style','pushbutton','String','Ausgleich Start', ...
    %    'Position',[873.33 540 106.67 23.33],'FontSize',10, ...
    %    'Callback',@(src,evt) logMsg('Ausgleich Start'));

    %handles.Ausgleich_Stopp = uicontrol(fig,'Style','pushbutton','String','Ausgleich Stopp', ...
    %    'Position',[873.33 566.67 106.67 23.33],'FontSize',10, ...
    %    'Callback',@(src,evt) logMsg('Ausgleich Stopp'));

    handles.Reset = uicontrol(fig,'Style','pushbutton','String','Reset', ...
        'Position',[273.33 263.33 53.33 23.33],'FontSize',10);

    handles.Einstellungen_uebernehmen = uicontrol(fig,'Style','pushbutton','String','Einstellungen übernehmen', ...
        'Position',[333.33 263.33 173.33 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Einstellungen übernehmen'));

    handles.Messung_Starten = uicontrol(fig,'Style','pushbutton','String','Messung Starten', ...
        'Position',[513.33 263.33 120 23.33],'FontSize',10,'Enable','off', ...
        'Callback',@(src,evt) logMsg('Messung Starten'));

    handles.Messung_Abbrechen = uicontrol(fig,'Style','pushbutton','String','Messung Abbrechen', ...
        'Position',[640 263.33 140 23.33],'FontSize',10, ...
        'Callback',@(src,evt) logMsg('Messung Abbrechen'));
    
end