function handles = Smarter_Zellhalter_GUI()
    

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
                 'Position', [100 100 1500 900], ...
                 'MenuBar', 'none', ...
                 'Resize', 'on', ...          % <-- Fenstergrößenänderung erlauben
                 'WindowState', 'normal');    % <-- Maximieren möglich (Standard)

    %% Beschriftung (Label)
    uicontrol(fig,'Style','text','String','Smarter_Zellhalter_GUI','FontSize',30,'FontWeight','bold','Position',[10 850 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Einstellungen EIS-Messung:','FontSize',20,'FontWeight','bold','Position',[10 380 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Zielordner:','FontSize',15,'FontWeight','bold','Position',[100 300 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Filename:','FontSize',15,'FontWeight','bold','Position',[100 250 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Kommentar:','FontSize',15,'FontWeight','bold','Position',[100 200 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Name Z1:','FontSize',15,'FontWeight','bold','Position',[100 150 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Name Z2:','FontSize',15,'FontWeight','bold','Position',[100 100 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Name Z3:','FontSize',15,'FontWeight','bold','Position',[100 50 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','EIS_Chip:','FontSize',15,'FontWeight','bold','Position',[900 300 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Start_Frequenz:','FontSize',15,'FontWeight','bold','Position',[900 250 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Stopp_Frequenz:','FontSize',15,'FontWeight','bold','Position',[900 200 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Amplitude:','FontSize',15,'FontWeight','bold','Position',[900 150 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Signalform:','FontSize',15,'FontWeight','bold','Position',[900 100 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Mittelung über:','FontSize',15,'FontWeight','bold','Position',[900 50 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Verschaltung:','FontSize',15,'FontWeight','bold','Position',[900 0 500 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Spg_Z1:                    mV','FontSize',15,'FontWeight','bold','Position',[610 758 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Spg_Z2:                    mV','FontSize',15,'FontWeight','bold','Position',[610 718 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String','Spg_Z3:                    mV','FontSize',15,'FontWeight','bold','Position',[610 678 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' Str_Z1:                    mA','FontSize',15,'FontWeight','bold','Position',[610 638 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' Str_Z2:                    mA','FontSize',15,'FontWeight','bold','Position',[610 598 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' Str_Z3:                    mA','FontSize',15,'FontWeight','bold','Position',[610 558 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' R_S1:                      mΩ','FontSize',15,'FontWeight','bold','Position',[610 518 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' R_S2:                      mΩ','FontSize',15,'FontWeight','bold','Position',[610 478 280 50], 'HorizontalAlignment','left');

    uicontrol(fig,'Style','text','String',' R_S3:                      mΩ','FontSize',15,'FontWeight','bold','Position',[610 438 280 50], 'HorizontalAlignment','left');

    %% Symbole Zeichnen
    ax = axes('Parent', fig, 'Units','pixels', 'Position',[900 500 500 300]);
    set(ax,'XLim',[0 200],'YLim',[0 150],'XTick',[],'YTick',[], 'Visible','on','Box','on');
    axis(ax,'manual'); axis(ax,'ij');

    w = 40; hgt = 80; y = 40;
    hZ.Z1 = rectangle(ax,'Position',[20  y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,20+w/2,y+hgt/2,'Z1','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',25);

    hZ.Z2 = rectangle(ax,'Position',[80  y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,80+w/2,y+hgt/2,'Z2','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',25);

    hZ.Z3 = rectangle(ax,'Position',[140 y w hgt],'FaceColor',[0 1 0],'EdgeColor',[0 0.3 0]);
    text(ax,140+w/2,y+hgt/2,'Z3','HorizontalAlignment','center','VerticalAlignment','middle','FontWeight','bold','FontSize',25);

    % Schwarze Linie über den drei Rechtecken
    hZ.L_Plus = line(ax, [10 175], [20 20],'Color', [0 0 0],'LineWidth', 10);

    hZ.L_Minus = line(ax, [10 175], [140 140],'Color', [0 0 0],'LineWidth', 10);

    hZ.L_Z1_d = line(ax, [28 28], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z1_R = line(ax, [52 52], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z1_GND = line(ax, [40 40], [121 136],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z2_d = line(ax, [88 88], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z2_R = line(ax, [112 112], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z2_GND = line(ax, [100 100], [121 136],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z3_d = line(ax, [148 148], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z3_R = line(ax, [172 172], [24 39],'Color', [1 1 1],'LineWidth', 10);

    hZ.L_Z3_GND = line(ax, [160 160], [121 136],'Color', [1 1 1],'LineWidth', 10);

    handles.hZ = hZ; % wird benötigt damit hZ Objekte in anderen Funktionen geändert werden können

    %% Log-Ausgabe (mehrzeiliges Textfeld, nur lesen)
    handles.log = uicontrol(fig,'Style','listbox','Max',2,'Min',0, ...
        'Position',[20 500 580 300], 'HorizontalAlignment','left', ...
        'FontName','Consolas','BackgroundColor',[1 1 1], ...
        'TooltipString','Protokoll der Aktionen', ...
        'Enable','inactive','String','', 'FontSize', 12);

    %% Ausklappbare Auswahl (Popup-Menü)
    Werte_COM = {'COM 1','COM 2','COM 3','COM 4','COM 5','COM 6','COM 7','COM 8','COM 9','COM 10','COM 11','COM 12'};
    handles.COM = uicontrol(fig,'Style','popupmenu','String',Werte_COM, ...
        'Position',[480 840 100 50],'FontSize',15);

    Werte_Amplitude = {'50 mA','100 mA','200 mA','300 mA','400 mA','500 mA'};
    handles.Amplitude = uicontrol(fig,'Style','popupmenu','String',Werte_Amplitude, ...
        'Position',[1100 150 220 50],'FontSize',15);

    Werte_SinRec = {'Sinus','Rechteck'};
    handles.SinRec = uicontrol(fig,'Style','popupmenu','String',Werte_SinRec, ...
        'Position',[1100 100 220 50],'FontSize',15);

    Werte_Mittelung = {'1','2','3','4','5','6','7','8','9','10'};
    handles.Mittelung = uicontrol(fig,'Style','popupmenu','String',Werte_Mittelung, ...
        'Position',[1100 50 220 50],'FontSize',15);

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
        'Position',[1100 250 220 50],'FontSize',15);
    handles.stopp_frq = uicontrol(fig,'Style','popupmenu','String',Werte_frq, ...
        'Position',[1100 200 220 50],'FontSize',15);

    Werte_EIS_Chip = {'EIS_Chip_1','EIS_Chip_2','EIS_Chip_3'};
    handles.EIS_Chip = uicontrol(fig,'Style','popupmenu','String',Werte_EIS_Chip, ...
        'Position',[1100 300 220 50],'FontSize',15);

    Werte_Verschaltung = {'individuel','einzeln','Z1 || Z2','Z1 || Z3','Z2 || Z3','Z1 || Z2 || Z3'};
    handles.Verschaltung = uicontrol(fig,'Style','popupmenu','String',Werte_Verschaltung, ...
        'Position',[1100 0 220 50],'FontSize',15);

    %% Checkbox (Kästchen zum Ankreuzen)

    handles.Z1_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[980 722 40 30],'FontSize',15);
    handles.Z1_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[1040 722 40 30],'FontSize',15);
    handles.Z1_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[1010 528 70 30],'FontSize',15);

    handles.Z2_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[1130 722 40 30],'FontSize',15);
    handles.Z2_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[1190 722 40 30],'FontSize',15);
    handles.Z2_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[1160 528 70 30],'FontSize',15);

    handles.Z3_direkt = uicontrol(fig,'Style','checkbox','String','d', ...
        'Position',[1280 722 40 30],'FontSize',15);
    handles.Z3_R = uicontrol(fig,'Style','checkbox','String','R', ...
        'Position',[1340 722 40 30],'FontSize',15);
    handles.Z3_GND = uicontrol(fig,'Style','checkbox','String','GND', ...
        'Position',[1310 528 70 30],'FontSize',15);

    %% Textfeld (Eingabe)
    handles.Zielordner = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 320 600 30],'FontSize',15);
    
    handles.Filename = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 270 600 30],'FontSize',15);

    handles.Kommentar = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 220 600 30],'FontSize',15);    

    handles.Zellenname_Z1 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 170 600 30],'FontSize',15);

    handles.Zellenname_Z2 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 120 600 30],'FontSize',15);

    handles.Zellenname_Z3 = uicontrol(fig,'Style','edit','String','', ...
        'Position',[250 70 600 30],'FontSize',15);

    %% Textfeld (Ausgabe)
    handles.Text_Spg_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 780 100 30],'FontSize',15);

    handles.Text_Spg_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 740 100 30],'FontSize',15);   

    handles.Text_Spg_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 700 100 30],'FontSize',15);   

    handles.Text_Str_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 660 100 30],'FontSize',15);

    handles.Text_Str_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 620 100 30],'FontSize',15);   

    handles.Text_Str_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 580 100 30],'FontSize',15);

    handles.Text_Kontakt_Z1 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 540 100 30],'FontSize',15);

    handles.Text_Kontakt_Z2 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 500 100 30],'FontSize',15);   

    handles.Text_Kontakt_Z3 = uicontrol(fig,'Style','edit','String','0', ...
        'Position',[700 460 100 30],'FontSize',15);   

    %% Button
    handles.Connect = uicontrol(fig,'Style','pushbutton','String','Connect', ...
        'Position',[590 856 130 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Connect'));

    handles.Entkoppeln = uicontrol(fig,'Style','pushbutton','String','Entkoppeln', ...
        'Position',[800 856 160 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Entkoppeln'));
    
    handles.Koppeln = uicontrol(fig,'Style','pushbutton','String','Koppeln', ...
        'Position',[970 856 160 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Zellen_Check'));

    handles.Zellen_Check = uicontrol(fig,'Style','pushbutton','String','Zellen-Check', ...
        'Position',[1140 856 160 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Zellen_Check'));

    handles.Kontakt_Check = uicontrol(fig,'Style','pushbutton','String','Kontakt-Check', ...
        'Position',[1310 856 160 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Kontakt_Check'));

    %handles.Ausgleich_Start = uicontrol(fig,'Style','pushbutton','String','Ausgleich Start', ...
    %    'Position',[1310 810 160 35],'FontSize',15, ...
    %    'Callback',@(src,evt) logMsg('Ausgleich Start'));

    %handles.Ausgleich_Stopp = uicontrol(fig,'Style','pushbutton','String','Ausgleich Stopp', ...
    %    'Position',[1310 850 160 35],'FontSize',15, ...
    %    'Callback',@(src,evt) logMsg('Ausgleich Stopp'));

    handles.Reset = uicontrol(fig,'Style','pushbutton','String','Reset', ...
        'Position',[410 395 80 35],'FontSize',15);

    handles.Einstellungen_uebernehmen = uicontrol(fig,'Style','pushbutton','String','Einstellungen übernehmen', ...
        'Position',[500 395 260 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Einstellungen übernehmen'));

    handles.Messung_Starten = uicontrol(fig,'Style','pushbutton','String','Messung Starten', ...
        'Position',[770 395 180 35],'FontSize',15,'Enable','off', ...
        'Callback',@(src,evt) logMsg('Messung Starten'));

    handles.Messung_Abbrechen = uicontrol(fig,'Style','pushbutton','String','Messung Abbrechen', ...
        'Position',[960 395 210 35],'FontSize',15, ...
        'Callback',@(src,evt) logMsg('Messung Abbrechen'));
    
end