function hfig=ecgPreview
% ecgPreview: Creates a GUI to preview ecg, filter ecg, detect beats, and
% filter ibi. It also alows the user to export ecg and ibi in several
% formats.
%
% Version: 1.1.5 - 3/31/09
%       Updates: 
%       1. error using skip to next when nOutliers was zero.
%       2. Added an option to replace NaN values in ecg with zeros.
%          Reduced large segments missing after using fast smooth.
% Version: 1.1.7 - 6/25/09
%    	Updates: 
%       1. Fixed various simple GUI bugs
%       2. Added a checkbox option to define custom ECG segment length.
%           This allows users to define what section of the file to read.
%       3. Fixed a bug that occured when exporting IBI using "current window".
% Version: 1.1.8 - 10/04/09
%    	Updates: 
%       1. Added a feature to save annotions to Access database
% Version: 1.1.9 - 3/22/2010
%    	Updates: 
%       1. Added feature to change colors of files in list, if they have
%       been marked as complete in the database.
%       2. Added feature to view annotions within GUI
%
% NOTES: 1. To take advantage of multicore processing you must run
%           matlabpool command and specify number of processors to use.
%        2. dblclick on ecg plot to add annotion, right click or ctrl click to mark
%           file as completed
%        3. Before using the database feature the first time you must create
%           a datasourse in your Windows environment. See
%           http://matlab.izmiran.ru/help/toolbox/database/instal12.html#18933.
%           This is only done once.
%        4. dblclick on list of annotations to get details of that annotation
%        5. Use the up and down keyboard arrow keys to move to
%           the next(up) and previous (down) outlier. Use left and right to
%           move one ECG window back and forward. Note...you must first
%           click on a blank area in the ECG plot for these functions to work.


%%  Initialize Variables
    
    %global variables
    %   sldStep: increment that slider moves when clicked (samples)
    %   dx: number of ecg samples in plot window (samples)
    %   fileList: (todo)
    %   fname: name of selected file (todo)
    %   ecg1: unfilterd original ecg. I keep it in memory so i don't have
    %       to reload it if user decideds to not use ecg filters after already
    %       applying a filter.
    %   ecgf: filterd ecg
    %   path1: path to .mat files
    %   x: array containing x/time values of ecg (seconds)
    %   rate: ecg sample rate (samples/second)
    %   nx: number of total ecg samples (samples)
    %   indexR: index locations of beats (samples)
    %   ibi: 2 dim array of inter-beat intervals (seconds,samples)
    %   h: structure containing handles to all gui controls
    %   art: array containg a logical array of ibi outliers
    %   flagReady: boolean flag that lets other fxns know if at least one
    %       ecg file has been previewed. 
    %   Ann: matrix of annotions retrieved when clicking on filename
    %
    %
    %
    global sldStep dx fileList fname ecg1 ecgf path1 x rate nx
    global indexR ibi h art flagReady flagMultiCore Ann
    
    rate=1000; %sample rate of ecg
    
    flagReady=false; %flag that disables user controls until ecg is loaded    

    dataSource= 'ann_db';%specifies the datasourse to use for annotations. 
                         %Make sure this mathes the datasource that is defined in Windows

%% Defaults for gui

    def_dir='E:\ECG\rat\segements';
    def_win=.05;     %window size of plot 10%
    %ECG filter
    def_ecgfilt=1;  %1=none, 2=wavelet, 3=fastsmooth
    def_wavelet=2;  %1=db, 2=sym, 3=coif
    def_wavelet2=3; 
    def_wavLevel='8';
    def_wavRemove='1,2,8';
    def_smoothLP='3';
    def_smoothHP='750';
    def_smoothLevel=2; %1=rectangular, 2=triangular, 3=pseudo-gaussian
    def_replaceNAN=true; %true=replace nan w/ zero, false=do nothing
    %Beat detection
    def_template='E:\Source Code\Matlab\HRV\templates\RTFcon10_wk8.mat';
    def_tempUT='0.55';   %upper thresh for template matching
    def_tempLT='0.5';  %lower thresh for template matching
    %IBI filters (0=off,1=on)
    def_P=0;        %percent
    def_Pval='20';    
    def_SD=0;       %sd
    def_SDval='3';
    def_M=0;        %median
    def_Mval1='4';
    def_Mval2='5';
    def_AT=1;       %above thresh
    def_ATval='0.26';
    def_BT=1;       %below thresh
    def_BTval='0.118';
    def_C=1;        %custom
    def_Cval1='3';
    def_Cval2='320';
    
%% Create Main Figure
    %set some sizes for creating the gui
    pathH=0.05; pathB=0.95; %dir/path panel
    toolsH=0.20; toolsB=0; %tools panel
    filesH=1-toolsH; filesB=toolsH; %file list panel
    ecgH=0.6; ecgB=filesB; %ecg plot panel
    ibiH=1-ecgH-toolsH-pathH; ibiB=ecgH+toolsH; %ibi plot panel

    %Main Figure
    h.MainFigure = figure('Name','ECG Preview Tool', ...
                    'HandleVisibility','on', ...
                    'Position',[20 50 1100 700 ],...
                    'Toolbar','figure','Menubar','figure',...
                    'CloseRequestFcn',@closeGUI,'KeyPressFcn',@keyPress);
    hfig=h.MainFigure;
%% Create Current Dir Conrtrols

    h.panelDir = uipanel('Parent',h.MainFigure,...
                    'Units', 'normalized', 'backgroundcolor',[0.702 0.7216 0.8235], ...
                    'Position',[0.2 pathB 0.8 pathH]);   
    h.txtDir=uicontrol(h.panelDir,'Style','edit',...
                    'String',def_dir,...
                    'Units', 'normalized', ...
                    'Position',[.005 .15 .88 .7],...
                    'BackgroundColor','white',...
                    'HorizontalAlignment','left',...
                    'Callback', @txtDir_Callback);
    h.btnBrowse=uicontrol(h.panelDir,'Style','pushbutton',...
                    'String','Select Dir...', ...
                    'Units', 'normalized', ...
                    'Position',[.895 .15 .1 .7], ...
                    'Callback', @btnOpen_Callback);
   
%%  Create File List Controls

    h.panelPreviewFiles = uipanel('Parent',h.MainFigure,...
                'Units', 'normalized', ...
                'Position',[0 filesB .2 filesH]);    
    %Label: custom start time
    h.lblCustomStart=uicontrol(h.panelPreviewFiles,'Style','text',...
                'String','Start Time (hh:mm:ss):',...                
                'Units', 'normalized', ...
                'Position',[.13 .135 .55 .03],...
                'HorizontalAlignment','right');            
    %textBox: custom start time
    h.txtCustomStart=uicontrol(h.panelPreviewFiles,'Style','edit',...
                'String','00:00:00',...
                'Units', 'normalized', ...
                'Position',[.705 .135 .27 .03],...
                'BackgroundColor','white');
    %Label: custom segment length
    h.lblCustomLen=uicontrol(h.panelPreviewFiles,'Style','text',...
                'String','Length (hh:mm:ss):',...                
                'Units', 'normalized', ...
                'Position',[.13 .1 .55 .03],...
                'HorizontalAlignment','right');            
    %textBox: custom segment length
    h.txtCustomLen=uicontrol(h.panelPreviewFiles,'Style','edit',...
                'String','00:00:00',...
                'Units', 'normalized', ...
                'Position',[.705 .1 .27 .03],...
                'BackgroundColor','white');                    
            
    %file list        
    h.listFiles = uicontrol(h.panelPreviewFiles,'Style','listbox',...
                'Units', 'normalized', ...
                'String','',...
                'Position',[.02 .445 .96 .55],...
                'BackgroundColor','white',...
                'Callback', @lstFilesClk_Callback);
    h.btnPreview=uicontrol(h.panelPreviewFiles,'Style','pushbutton',...
                    'String','Preview',...
                    'Units', 'normalized', ...
                    'Position',[.12 .01 .76 .08],...
                    'Callback', @btnPreview_Callback);
    h.btnPrevFile=uicontrol(h.panelPreviewFiles,'Style','pushbutton',...
                    'String','<',...
                    'Units', 'normalized', ...
                    'Position',[.02 .01 .1 .08],...
                    'TooltipString','previous file',...
                    'Callback', @btnPrevFile_Callback);     
    h.btnNextFile=uicontrol(h.panelPreviewFiles,'Style','pushbutton',...
                    'String','>',...
                    'Units', 'normalized', ...
                    'Position',[.88 .01 .1 .08],...
                    'TooltipString','next file',...
                    'Callback', @btnNextFile_Callback);
    %annotation list
    h.listAnn = uicontrol(h.panelPreviewFiles,'Style','listbox',...
                    'Units', 'normalized', ...
                    'String','',...
                    'Position',[.02 .18 .96 .255],...
                    'BackgroundColor','white', ...
                    'Callback', @lstAnnClk_Callback);
    
%% Create ECG Plot Controls

    %plot panel
    h.panelPreviewECG = uipanel('Parent',h.MainFigure,...
                'Units', 'normalized', ...
                'Position',[.2 ecgB .8 ecgH]);
    %axes handle
    h.axesECG = axes('Parent', h.panelPreviewECG, ...
                 'HandleVisibility','callback', ...
                 'Units', 'normalized', 'fontsize',8, ...
                 'Position',[.06 0.27 0.85 0.65],...
                 'ButtonDownFcn',@clickEvent);
    box(h.axesECG,'on') %create black box all around plot window
    xlabel(h.axesECG,'Time (s)','fontsize',8);
    ylabel(h.axesECG,'Amplitude','fontsize',8);
    %---------------------------------------------
    %container for controls
    h.containerX = uipanel('Parent',h.panelPreviewECG,...
                'Position',[.06 .02 .85 .15]);            
    %slider
    h.slider = uicontrol(h.containerX,'Style','slider',...
                'Max',100,'Min',1,'Value',1,...
                'SliderStep',[def_win/100 0.2],...
                'Units', 'normalized', ...
                'Position',[.105 .6 .788 .3],...
                'BackgroundColor','white',...
                'Callback', @hSlider_Callback);
    %Label: min
    h.txtWinMin=uicontrol(h.containerX,'Style','edit',...
                'String',min(x),'fontsize',8,...%min(x),...
                'Value',1,...
                'Units', 'normalized', ...
                'Position',[.003 .6 .1 .3],...
                'HorizontalAlignment','center');
    %Label: max
    h.txtWinMax=uicontrol(h.containerX,'Style','edit',...
                'String',max(x),...%min(x)+dx,...
                'Value',dx,...
                'Units', 'normalized', ...
                'Position',[.895 .6 .1 .3],...
                'HorizontalAlignment','center');
            
    %textBox: current position
    h.txtWinCurrent=uicontrol(h.containerX,'Style','edit',...
                'String',1,...%x(1),...
                'Units', 'normalized', ...
                'Position',[.793 .2 .1 .3],...
                'BackgroundColor','white',...
                'Callback',@txtWinCurrent_Callback);
    %Lable: current position
    h.lblWinCurrent=uicontrol(h.containerX,'Style','edit',...
                'String','Current Position >> ',...
                'Units', 'normalized', ...
                'Position',[.591 .2 .2 .3],...
                'Enable','inactive',...
                'HorizontalAlignment','right');
    %Label: window size
    h.lblWinSize=uicontrol(h.containerX,'Style','edit',...
                'String',' << Window Size (%)',...
                'Units', 'normalized', ...
                'Position',[.207 .2 .2 .3],...
                'Enable','inactive',...
                'HorizontalAlignment','left');
    %Button: reduce window size
    h.btnWinSizeDown=uicontrol(h.containerX,'Style','pushbutton',...
                'String','<',...
                'Units', 'normalized', ...
                'Position',[.105 .2 .02 .3],...
                'Callback',@btnWinSizeDown_Callback);
    %Textbox: window size
    h.txtWinSize=uicontrol(h.containerX,'Style','edit',...
                'String','',...
                'Units', 'normalized', ...
                'Value', def_win,...
                'String',def_win,...
                'Visible','on',...
                'Position',[.125 .2 .06 .3],...
                'BackgroundColor','white',...
                'Callback', @txtWinSize_Callback);
    %Button: increase window size
    h.btnWinSizeUp=uicontrol(h.containerX,'Style','pushbutton',...
                'String','>',...
                'Units', 'normalized', ...
                'Position',[.185 .2 .02 .3],...
                'Callback', @btnWinSizeUp_Callback);
    %--------------------------------------------------
    %Textbox: Lower y limit
    h.txtYlimit1=uicontrol(h.panelPreviewECG,'Style','edit',...
                'String',num2str(min(ecgf)),...
                'Units', 'normalized','fontsize',8, ...
                'Value', min(ecgf),...
                'Visible','on',...
                'Position',[.915 .27 .065 .034],...
                'Enable','inactive',...
                'BackgroundColor',[.95 .95 .95],...
                'Callback', @txtYlimit1_Callback);
    %Textbox: Upper y limit
    h.txtYlimit2=uicontrol(h.panelPreviewECG,'Style','edit',...
                'String',num2str(max(ecgf)),...
                'Units', 'normalized','fontsize',8, ...
                'Value', max(ecgf),...
                'Enable','inactive',...
                'Visible','on',...
                'Position',[.915 .886 .065 .034],...
                'BackgroundColor',[.95 .95 .95],...
                'Callback',@txtYlimit2_Callback);
    %chk: auto scale y limit
    h.chkYlimitAuto=uicontrol(h.panelPreviewECG,'Style','checkbox',...
                'String','Auto','fontsize',8,...
                'value',1,...
                'Units', 'normalized', ...
                'Position',[.915 .578 .065 .044],...
                'Callback', @chkYlimitAuto_Callback);            

%% Create IBI Plot

    %plot panel
    h.panelPreviewIBI = uipanel('Parent',h.MainFigure,...
                'Units', 'normalized', ...
                'Position',[.2 ibiB .8 ibiH]);              
    %axes handle        
    h.axesIBI = axes('Parent', h.panelPreviewIBI, ...
                 'HandleVisibility','callback', ...
                 'Units', 'normalized','fontsize',6, ...
                 'Position',[.06 .15 .85 .8]);   
    box(h.axesIBI,'on') %create black box all around plot window
    ylabel(h.axesIBI,'IBI (ms)','fontsize',8)    
            
%% Create Panel to hold Tools
    h.panelTools = uipanel('Parent',h.MainFigure,...
                'Units', 'normalized', ...
                'Position',[0 toolsB 1 toolsH]); 
                
%% Create ECG Filter Controls
    h.panelFilter = uipanel('Parent',h.panelTools,'title','Filter ECG',...
        'Units', 'normalized', 'Position',[0 0 .2 1]);
    h.lblFilter=uicontrol(h.panelFilter,'Style','text', 'String','Method :',...
        'Units', 'normalized', 'Position',[.05 .8 .25 .1],...
        'HorizontalAlignment','right');
    h.listFilter = uicontrol(h.panelFilter,'Style','popupmenu',...
        'String',{'None','Wavelet','Fast Smooth'},'Value',def_ecgfilt, ...
        'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.35 .8 .5 .1],...
        'Callback', @listFilter_Callback);
    h.chkReplaceNAN = uicontrol(h.panelFilter,'Style','checkbox',...
        'String','Replace NaN with zero.','Value',def_replaceNAN,...
        'Units', 'normalized', 'Position',[.1 .05 .7 .12], 'visible','on', ...
        'Callback',@filtEcgChange_Callback);
    
    %Wavelet Options
    h.lblWaveletType=uicontrol(h.panelFilter,'Style','text', 'String','Wavelet :',...
        'Units', 'normalized', 'Position',[.04 .6 .3 .1],'Visible','off',...
        'HorizontalAlignment','right');
    h.listWaveletType = uicontrol(h.panelFilter,'Style','popupmenu',...
        'String',{'db','sym','coif'},'Value',def_wavelet,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.37 .6 .27 .1],'Visible','off',...
        'Callback', @listWaveletType_Callback);    
    h.listWaveletType2 = uicontrol(h.panelFilter,'Style','popupmenu',...
        'String',{'2','3','4','5','6','7','8','9','10'},'Value',def_wavelet2, ...
        'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.65 .6 .2 .1],'Visible','off',...
        'Callback', @filtEcgChange_Callback);        
    h.lblWaveletLevel=uicontrol(h.panelFilter,'Style','text', 'String','Level :',...
        'Units', 'normalized', 'Position',[.37 .35 .3 .15],'Visible','off',...
        'HorizontalAlignment','right');       
    h.txtWaveletLevel=uicontrol(h.panelFilter,'Style','edit', 'String',def_wavLevel,...
        'Units', 'normalized', 'Position',[.7 .35 .15 .15],'Visible','off',...
        'HorizontalAlignment','center','BackgroundColor','white',...
        'Callback', @filtEcgChange_Callback);
    h.lblWaveletRemove=uicontrol(h.panelFilter,'Style','text', ...
        'String','Remove Sub-band :',...
        'Units', 'normalized', 'Position',[.06 .2 .6 .15],'Visible','off',...
        'HorizontalAlignment','right');       
    h.txtWaveletRemove=uicontrol(h.panelFilter,'Style','edit', 'String',def_wavRemove,...
        'Units', 'normalized', 'Position',[.7 .2 .15 .15],'Visible','off',...
        'HorizontalAlignment','center','BackgroundColor','white',...
        'Callback', @filtEcgChange_Callback);
    %Smoothing Options
    h.lblSmoothLevel=uicontrol(h.panelFilter,'Style','text', 'String','Type/Lev :',...
        'Units', 'normalized', 'Position',[.05 .6 .25 .1],'Visible','off',...
        'HorizontalAlignment','right');
    h.listSmoothLevel = uicontrol(h.panelFilter,'Style','popupmenu',...
        'String',{'Rectangular (1x)', 'Triangular (2x)', 'Pseudo-Gaussian (3x)'},...
        'Value',def_smoothLevel, ...
        'BackgroundColor','white', 'Units', 'normalized', ...
        'Position',[.35 .6 .5 .1],'Visible','off',...
        'Callback', @filtEcgChange_Callback);        
    h.lblSmoothLP=uicontrol(h.panelFilter,'Style','text', 'String','LPF Span :',...
        'Units', 'normalized', 'Position',[.15 .35 .4 .15],'Visible','off',...
        'HorizontalAlignment','right');
    h.txtSmoothLP=uicontrol(h.panelFilter,'Style','edit', 'String',def_smoothLP,...
        'Units', 'normalized', 'Position',[.58 .35 .27 .15],'Visible','off',...
        'HorizontalAlignment','center','BackgroundColor','white',...
        'Callback', @filtEcgChange_Callback);
    h.lblSmoothHP=uicontrol(h.panelFilter,'Style','text', 'String','HPF Span :',...
        'Units', 'normalized', 'Position',[.15 .2 .4 .15],'Visible','off',...
        'HorizontalAlignment','right');
    h.txtSmoothHP=uicontrol(h.panelFilter,'Style','edit', 'String',def_smoothHP,...
        'Units', 'normalized', 'Position',[.58 .2 .27 .15],'Visible','off',...
        'HorizontalAlignment','center','BackgroundColor','white',...
        'Callback', @filtEcgChange_Callback);
    
    %% Create Beat Detection Controls
    h.panelRwave = uipanel('Parent',h.panelTools,'title','Detect Beats',...
        'Units', 'normalized', 'Position',[.2 0 .2 1]);
    h.lblRwaveMethod=uicontrol(h.panelRwave,'Style','text', 'String','Method :',...
        'Units', 'normalized', 'Position',[.05 .8 .25 .1],...
        'HorizontalAlignment','right');
    h.listRwaveMethod = uicontrol(h.panelRwave,'Style','popupmenu',...
        'String',{'None','Template Matching','Self Template'},'Value',2,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.35 .8 .6 .1],...
        'Callback', @listRwaveMethod_Callback);    
    h.txtRwaveTemplate=uicontrol(h.panelRwave,'Style','edit','String',def_template,...
        'Units', 'normalized', 'Position',[.05 .55 .9 .15],'Visible','on',...
        'BackgroundColor','white','Callback', @rwaveChange_Callback);
    h.btnRwaveTemplate=uicontrol(h.panelRwave,'Style','pushbutton', ...
        'String','Select Template ...', ...
        'Units', 'normalized', 'Position',[.45 .4 .5 .15], 'Visible','on', ...
        'Callback', @btnRwaveTemplate_Callback);
    h.lblRwaveUT=uicontrol(h.panelRwave,'Style','text','String','Upper Thresh:',...
        'Units', 'normalized', 'Position',[.35 .25 .4 .12],'Visible','on');
    h.txtRwaveUT=uicontrol(h.panelRwave,'Style','edit','String',def_tempUT,...
        'Units', 'normalized', 'Position',[.8 .25 .15 .12],'Visible','on',...
        'BackgroundColor','white',...
        'Callback', @rwaveChange_Callback);
    h.lblRwaveLT=uicontrol(h.panelRwave,'Style','text','String','Lower Thresh:',...
        'Units', 'normalized', 'Position',[.35 .1 .4 .12],'Visible','on');
    h.txtRwaveLT=uicontrol(h.panelRwave,'Style','edit','String',def_tempLT,...
        'Units', 'normalized', 'Position',[.8 .1 .15 .12],'Visible','on',...
        'BackgroundColor','white',...
        'Callback', @rwaveChange_Callback);
    
    %% Create IBI Filter Controls
    h.panelOutliers = uipanel('Parent',h.panelTools,'title','Filter IBI',...
        'Units', 'normalized', 'Position',[.4 0 .2 1]);
        
    h.chkIbiFiltP = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','percent','Value',def_P,...
        'Units', 'normalized', 'Position',[.45 .8 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    h.chkIbiFiltSD = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','sd','Value',def_SD,...
        'Units', 'normalized', 'Position',[.45 .7 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    h.chkIbiFiltM = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','median','Value',def_M,...
        'Units', 'normalized', 'Position',[.45 .6 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    h.chkIbiFiltAT = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','above thresh','Value',def_AT,...
        'Units', 'normalized', 'Position',[.45 .5 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    h.chkIbiFiltBT = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','below thresh','Value',def_BT,...
        'Units', 'normalized', 'Position',[.45 .4 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    h.chkIbiFiltC = uicontrol(h.panelOutliers,'Style','checkbox',...
        'String','custom','Value',def_C,...
        'Units', 'normalized', 'Position',[.45 .05 .5 .12],...
        'Callback',@filtIbiChange_Callback);
    align([h.chkIbiFiltP h.chkIbiFiltSD h.chkIbiFiltM h.chkIbiFiltAT ...
        h.chkIbiFiltBT h.chkIbiFiltC],'Left','Distribute');
    h.txtIbiFiltP = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_Pval,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .8 .15 .12],...
        'Callback',@filtIbiChange_Callback);
    h.txtIbiFiltSD = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_SDval,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .7 .15 .12],...
        'Callback',@filtIbiChange_Callback);
    h.txtIbiFiltM2 = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_Mval2,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .6 .15 .12],...
        'Callback',@filtIbiChange_Callback);
    h.txtIbiFiltAT = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_ATval,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .5 .15 .12],...
        'Callback',@filtIbiChange_Callback);
    h.txtIbiFiltBT = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_BTval,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .4 .15 .12],...
        'Callback',@filtIbiChange_Callback);    
    h.txtIbiFiltC2 = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_Cval2,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.25 .05 .15 .12],...
        'Callback',@filtIbiChange_Callback);
    align([h.txtIbiFiltP h.txtIbiFiltSD h.txtIbiFiltM2 h.txtIbiFiltAT ...
        h.txtIbiFiltBT h.txtIbiFiltC2],'Left','Distribute');
    
    p=get(h.txtIbiFiltM2,'position');
    h.txtIbiFiltM1 = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_Mval1,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.1 p(2) .15 p(4)],...
        'Callback',@filtIbiChange_Callback);    
    p=get(h.txtIbiFiltC2,'position');
    h.txtIbiFiltC1 = uicontrol(h.panelOutliers,'Style','edit',...
        'String',def_Cval1,'BackgroundColor','white',...
        'Units', 'normalized', 'Position',[.1 p(2) .15 p(4)],...
        'Callback',@filtIbiChange_Callback);    
   %% Create Results
    h.panelResults = uipanel('Parent',h.panelTools,'title','Summary', ...
        'Units', 'normalized','Position',[.8 0 .2 1]); 
    h.axesResultsTbl = axes('parent', h.panelResults,'Position',[0 0 1 1],...
        'YColor','white','YTickLabel',{},'ylim',[0 1],...
        'XColor','white','XTickLabel',{},'xlim',[0 1]);    
    h.text.results = createResultsTbl(); %create Table for Results and return
                         %handles of text objects
    
    %% Create Export Controls   
    h.panelExport = uipanel('Parent',h.panelTools,'title','Export', ...
        'Units', 'normalized','Position',[.6 0 .2 1]); 
    h.btnExport=uicontrol(h.panelExport,'Style','pushbutton',...
        'String','Export ECG','Units', 'normalized', ...
        'Position',[.1 .7 .8 .2],'Callback', @btnExport_Callback);    
    h.btnExportIBI=uicontrol(h.panelExport,'Style','pushbutton',...
        'String','Export IBI','Units', 'normalized', ...
        'Position',[.1 .45 .8 .2],'Callback', @btnExportIBI_Callback);
    h.chkSelectedOnly=uicontrol(h.panelExport,'Style','checkbox',...
        'String','Export current window only', 'value',0,...
        'Units', 'normalized', 'Position',[.1 .2 .8 .2]);

    %% Create Progress Display
    p=get(h.axesECG,'position'); 
    width=.2; height=.1;
    left=p(1)+p(3)/2-width/2;
    bot=p(2)+p(4)/2-height/2;
    
    h.lblProgress=uicontrol(h.panelPreviewECG,'Style','edit', 'String','<< Loading >>',...
        'Units', 'normalized', 'Position', [left bot width height],...
        'BackgroundColor','white', 'FontSize',12, 'ForegroundColor', 'red',...
        'HorizontalAlignment','center', 'enable','off', 'visible','off');
    
    %%  Initialization tasks

    %load any saved data from last time   
    loadParameters();
    
    path1=get(h.txtDir,'string');
    populateFiles(path1);    

        %check to see if user wants to use parrellel processing
        try
            poolSize=matlabpool('size');
            if poolSize<2
                button = questdlg( ...
                    {'Do you want to use mulit cores for detecting beats?', ...
                    'matlabpool(2)'},'Multi-Core','Yes','No','Yes');
                if ~isempty(button) && strcmp(button,'Yes')            
                    matlabpool(2);
                    flagMultiCore=true;
                end
            else
                flagMultiCore=false;
            end
        catch e
            flagMultiCore=false;
        end
    
%%  Callbacks

    function hSlider_Callback(hObject, eventdata)
    % Callback function run when the slider is moved
        set(h.slider,'value',ceil(get(h.slider,'value')))
        updatePreview();
    end

    function txtWinCurrent_Callback(hObject, eventdata)
    %Callback function run if txtCurrentWindow changes
    
        %get desired pos from user
        pos=floor(str2double(get(hObject,'string'))*rate);
        if (pos>1 && pos<(nx-dx))
            set(h.slider,'value',pos);
            updatePreview();
        end
    end

    function btnWinSizeUp_Callback(hObject, eventdata)
    % Callback function run when the window size button is pressed
        s=str2double(get(h.txtWinSize,'String'));
        if s < 99
            set(h.txtWinSize,'String',num2str(s+1))
        end
        txtWinSize_Callback();
    end

    function btnWinSizeDown_Callback(hObject, eventdata)
        s=str2double(get(h.txtWinSize,'String'));
        if s > 1
            set(h.txtWinSize,'String',num2str(s-1))
        end
        txtWinSize_Callback();
    end

    function txtWinSize_Callback(hObject, eventdata)
        % dx is the width of the axis 'window'
        sldStep = str2double(get(h.txtWinSize,'String'))/100;
        dx = floor(sldStep*nx);

        %change slider steps
        set(h.slider,'SliderStep',[sldStep 0.1]);
        updatePreview();
    end

    function txtYlimit1_Callback(hObject, eventdata)
    % Callback function run when the lower ylimit
    % textbox is changed
        updatePreview();
    end

    function txtYlimit2_Callback(hObject, eventdata)
    % Callback function run when the upper ylimit
    % textbox is changed
        updatePreview();
    end

    function chkYlimitAuto_Callback(hObject, eventdata)
    % Callback function run when the auto ylimit
    % btn is pressed
        %autoscale plot if checkbox is checked
        if get(h.chkYlimitAuto,'value')==1
            %make y-axis limit textboxes look disabled
            set(h.txtYlimit1,'Enable','inactive','BackgroundColor',[.95 .95 .95]);
            set(h.txtYlimit2,'Enable','inactive','BackgroundColor',[.95 .95 .95]);
            x1=get(h.txtWinMin,'Value');
            x2=get(h.txtWinMax,'Value');
            y1=min(ecgf(x1:x2)); %min y value in window
            y2=max(ecgf(x1:x2)); %max y value in window
            set(h.txtYlimit1,'String',num2str(y1));
            set(h.txtYlimit2,'String',num2str(y2));
            drawnow %force matlab to redraw it now
            updatePreview();
        else
            %make y-axis limit textboxes look enabled
            set(h.txtYlimit1,'Enable','on','BackgroundColor','white');
            set(h.txtYlimit2,'Enable','on','BackgroundColor','white');
        end
    end

    function txtDir_Callback(hObject, eventdata)        
    % Callback function run btnBrowse is pressed        
        
        path1=get(h.txtDir,'string');
        if exist(path1,'dir')
            populateFiles(path1);
        else
            disp([path1 ' contains no .mat files.'])
        end        
                
    end

    function btnOpen_Callback(hObject, eventdata)
    % Callback function run btnBrowse is pressed
        
        %get directory path
        if exist(get(h.txtDir,'string'),'dir')
            path1=get(h.txtDir,'string');
        else
            path1=what;
            path1=path1.path;
        end
        
        path1 = uigetdir(path1,'Select directory containg subject files to export:');
        
        if path1~=0
            if exist(path1,'dir')
                set(h.txtDir,'string',path1)
                populateFiles(path1);
            else
                disp([path1 ' not a valth directory.'])
            end        
        end
                
    end

    function btnPrevFile_Callback(hObject, eventdata)
        f=get(h.listFiles,'string');
        i=get(h.listFiles,'value');
        if (~isempty(f) && i>1)
            set(h.listFiles,'value',i-1);
            btnPreview_Callback();
        end
    end

    function btnNextFile_Callback(hObject, eventdata)
        f=get(h.listFiles,'string');
        i=get(h.listFiles,'value');
        m=length(fileList);
        if (~isempty(f) && i<m)
            set(h.listFiles,'value',i+1);
            btnPreview_Callback();
        end
    end
    
    function lstAnnClk_Callback(hObject, eventdata)
        s=get(h.MainFigure,'SelectionType'); %type of mouse click        
        switch s
            case 'open' % case double click
                i=get(h.listAnn,'value');
                if ~isempty(i)
                    str={['Annotation:  ' Ann{i,6}], ...
                         ['RelTime:  ' num2str(Ann{i,5}) ' s'],...
                         ['Notes:  ' Ann{i,7}],...
                         ['ID:  ' num2str(Ann{i,1})],...
                         ['CreatedDate:  ' Ann{i,2}],...
                         ['RecordDate:  ' Ann{i,3}],...
                         ['FileName:  ' Ann{i,4}]};
                    msgbox(str)
                end
        end
    end

    function lstFilesClk_Callback(hObject, eventdata)
        f=get(h.listFiles,'string');
        i=get(h.listFiles,'value');
        f=removeHTML(f{i});
        
         % DATABASE Stuff
                  
         conn = database(dataSource,'','');  %db connection
         cursorA = exec(conn, ...            %query db
            ['SELECT ALL ID,CreatedDate,RecordDate,FileName,RelTime,Annotation,' ...
            'Notes FROM tblAnn WHERE FileName = ''' f '''']);
         cursorA = fetch(cursorA);           %fecth records
         Ann=cursorA.data;                     %only need data
         close(conn);                   
         
        if ~(size(Ann,2)<=1) && ~isempty(Ann)
            nAnn=size(Ann,1);
            str=cell(nAnn,1);
            for i=1:nAnn
                tmp=sprintf('%0.1f s',str2double(Ann{i,5}));
                str{i}= [Ann{i,6} ' - ' tmp];
            end
            set(h.listAnn,'value',1) % this is to make Matlab not throw a warning/error
            set(h.listAnn,'string', str)
        else
            set(h.listAnn,'string', '')
            Ann=[];
        end
    end
    
    function btnPreview_Callback(hObject, eventdata)
    % Callback function run when the Preview btn is pressed
        
        if ~isempty(get(h.listFiles,'string')) %make sure a file is selected                      
%             try
                %Update progress
                showProgress('<< Loading >>');

                %check user inputs
                if (checkFiltInputs()<0) && (checkRwaveInputs()<0) && ...
                        (checkIbiFiltInputs()<0)
                   showProgress('');
                    return;
                end

                %name of input file
                fname=get(h.listFiles,'string');
                fname=fname{get(h.listFiles,'value')};
                %remove any html code
                fname=removeHTML(fname);
                
                %read ecg file
                data = load(fullfile(path1,fname)); %read ecg                                               
                x=double(data.ecg(:,1)); %assign time values to x and make sure thay are double precision
                ecg1=double(data.ecg(:,2)); %assign amplitude values to ecg1 and make sure thay are double precision
                data=[];                                                                
                
                %determine what part of ecg file to use
                start=get(h.txtCustomStart,'string'); %get starting point
                len=get(h.txtCustomLen,'string'); %get length                
                if ~isempty(start) && ~isempty(len) && ~(strcmp('00:00:00',len))
                    if isempty(strfind(start,':')) %make sure in correct format
                        error('Incorrect custom "Start Time" format.')
                        return
                    else
                        %add (hours*3600) + (minutes*60) + seconds
                        nSeconds = str2double(datestr(start,'HH'))*3600 ...
                            + str2double(datestr(start,'MM'))*60 ...
                            + str2double(datestr(start,'SS')); 
                        x1=nSeconds*rate+1;
                    end                    
                    if isempty(strfind(len,':')) %make sure in correct format
                        error('Incorrect custom "length" format.')
                        return
                    else
                        %add (hours*3600) + (minutes*60) + seconds
                        nSeconds = str2double(datestr(len,'HH'))*3600 ...
                            + str2double(datestr(len,'MM'))*60 ...
                            + str2double(datestr(len,'SS')); 
                        x2=nSeconds*rate+x1;
                        if x2>length(ecg1)
                            x2=length(ecg1);
                        end                        
                    end
                    %get custom segment of ecg
                    ecg1=ecg1(x1:x2);
                    x=x(x1:x2);                    
                end                                
                
                %convert to double so that older versions of Matlab can do
                %arithmatic operations on the ecg data
                ecg1=double(ecg1);
                x=double(x);
                
                %set flag to tell functions that data has been loaded at least once
                flagReady=true;
                
                %try all ecg processing steps
                processEcg(3);                
                
                
                showProgress('<< Adjusting >>')
                %set controls
                nx=length(x);
                sldStep = str2double(get(h.txtWinSize,'string'))/100;
                dx=floor(sldStep*nx);
                set(h.slider,'Max',nx,'Min',1,'Value',1,'SliderStep',[sldStep 0.2]);
                set(h.txtWinMin,'String',min(x),'Value',1);
                set(h.txtWinMax,'String',max(x),'Value',dx);
                set(h.txtWinCurrent,'String',x(1));                
                title(h.axesECG,strrep(fname,'_','-'),'fontsize',8)
                %set axes limits
                set(h.axesECG,'xlim',[x(1) x(dx)],'ButtonDownFcn',@clickEvent)
                set(h.axesIBI,'xlim',[x(1) x(dx)])
                
                chkYlimitAuto_Callback();
                 %Update progress
                showProgress('');
                                 
%             catch ME
%                 set(h.btnPreview,'string','Preview');
%                 error(['Error previewing: ' ME.message'])
%             end
        end
               
    end

    function listWaveletType_Callback(hObject, eventdata)    
        i=get(h.listWaveletType,'Value');
        selection=get(h.listWaveletType,'String');
        selection=selection{i};
        switch selection
            case 'db'
                s={'2','3','4','5','6','7','8','9','10'};
                set(h.listWaveletType2,'string',s)
            case 'sym'
                s={'2','3','4','5','6','7','8'};
                set(h.listWaveletType2,'string',s)
            case 'coif'
                s={'1','2','3','4','5'};
                set(h.listWaveletType2,'string',s)
        end
        
        filtEcgChange_Callback();
    end

    function listFilter_Callback(hObject, eventdata)
        i=get(h.listFilter,'Value');
        selection=get(h.listFilter,'String');
        selection=selection{i};
        switch selection
            case 'Wavelet'
                wavVis='on';
                smoothVis='off';
            case 'Fast Smooth'
                wavVis='off';
                smoothVis='on';
            otherwise
                wavVis='off';
                smoothVis='off';                
        end
        
        %wavelet inputs
        set(h.lblWaveletType,'Visible',wavVis)
        set(h.listWaveletType,'Visible',wavVis)
        set(h.listWaveletType2,'Visible',wavVis)
        set(h.lblWaveletLevel,'Visible',wavVis)
        set(h.txtWaveletLevel,'Visible',wavVis)
        set(h.lblWaveletRemove,'Visible',wavVis)
        set(h.txtWaveletRemove,'Visible',wavVis)
        %Fast Smooth inputs
        set(h.lblSmoothLevel,'Visible',smoothVis)
        set(h.listSmoothLevel,'Visible',smoothVis)
        set(h.lblSmoothLP,'Visible',smoothVis)
        set(h.txtSmoothLP,'Visible',smoothVis)
        set(h.lblSmoothHP,'Visible',smoothVis)
        set(h.txtSmoothHP,'Visible',smoothVis)        
        drawnow update; %force matlab to redraw gui
        
        filtEcgChange_Callback();
    end   

    function listRwaveMethod_Callback(hObject, eventdata)
        i=get(h.listRwaveMethod,'Value');
        selection=get(h.listRwaveMethod,'String');
        selection=selection{i};
        switch selection
            case 'Template Matching'
                tmatchVis ='on';
            otherwise
                tmatchVis='off';
        end
        set(h.txtRwaveTemplate,'Visible',tmatchVis)
        set(h.btnRwaveTemplate,'Visible',tmatchVis)
        set(h.lblRwaveLT,'Visible',tmatchVis)
        set(h.txtRwaveLT,'Visible',tmatchVis)
        set(h.lblRwaveUT,'Visible',tmatchVis)
        set(h.txtRwaveUT,'Visible',tmatchVis)
        
        rwaveChange_Callback();
    end

    function btnRwaveTemplate_Callback(hObject, eventdata)
        %get directory path        
        [f,p] = uigetfile('*.mat','Select template file.');
        if p~=0
            set(h.txtRwaveTemplate,'String',fullfile(p,f))
        end
    end

    function filtEcgChange_Callback(hObject, eventdata)
    % Callback function run when ecg filter options change
        
        %try all ecg processing steps
        processEcg(3);

    end

    function rwaveChange_Callback(hObject, eventdata)
    % Callback function run when r-wave options options change                
        
        %try detecging rwaves and filtering ibi
        processEcg(2);

    end

    function filtIbiChange_Callback(hObject, eventdata)
    % Callback function run when IBI filter options change
                
        %try filtering ibi
        processEcg(1);        
    end

    function btnExportIBI_Callback(hObject, eventdata)
    %function called when the export IBI button is pressed    
        
%         try

            [p, name, extn] = fileparts(fullfile(path1,fname));

            %get filename and path to export
            [fName, fPath] = uiputfile( ...
                {'*.ibi','Text (*.ibi)';...             
                 '*.mat','Matlab Binary (*.mat) [smallest]';...
                 '*.xls','Excel (*.xls)'},...
                 'Export As',...
                fullfile(p,[name '.ibi']));

            %if user selected a filename and path
            if ~isequal(fName,0) || ~isequal(fPath,0)
                %update progress
                showProgress('<< Exporting IBI >>');                

                [p, name, extn] = fileparts(fName);

                %prepare ibi by determining if data is in rows or cols
                [r,c]=size(ibi);
                if r==1 %if in cols then transpose
                    ibi=ibi';
                end

                %export all or window only?
                flagWinOnly=get(h.chkSelectedOnly,'value');
                if flagWinOnly
                    x=get(h.axesIBI,'xlim');
                    x1=x(1);
                    x2=x(2);
                    i=find(ibi(:,1)>=x1 & ibi(:,1)<=x2);
                    x1=i(1); x2=i(end); %get corresponding ibi sample number
                else
                    x1=1; x2=size(ibi,1);
                end

                %Export ibi according to extension
                switch extn
                    case '.ibi' %Text
                        tmp=ibi(x1:x2,:);                                              
                        dlmwrite(fullfile(fPath,fName), tmp, 'delimiter', ',','precision', '%.4f')
                        clear tmp
                    case '.mat' %Matlab Binary
                        tmp=ibi;
                        ibi=ibi(x1:x2,:);
                        save(fullfile(fPath,fName),'ibi','-v7')
                        ibi=tmp;
                        clear tmp;
                    case '.xls' %Excel                    
                        [status, message] = ...
                            xlswrite(fullfile(fPath,fName),ibi(x1:x2,:));
                        %make sure there was no error
                        if ~status 
                            error(message.message)
                        end
                    otherwise
                        error('Choose a valid file extension.')
                end
                %Update progress
                showProgress('')               
            end
        
%         catch ME
%             %Update Progress
%             showProgress('')
%             error(['Error exporting IBI: ' ME.message])
%         end
    end

    function btnExport_Callback(hObject, eventdata)
    %function called when the export button is pressed    
        
%         try    
            [p, name, extn] = fileparts(fullfile(path1,fname));

            %get filename and path to export
            [fName, fPath] = uiputfile( ...
                {'*.mat','Matlab Binary (*.mat) [smallest]';...
                '*.dat','Binary int16 (*.dat) [fastest]';...
                 '*.txt','Text (*.txt)';...             
                 '*.xls','Excel (*.xls)'},...
                 'Export As',...
                fullfile(p,[name '_2.mat']));

            %if user selected a filename and path
            if ~isequal(fName,0) || ~isequal(fPath,0)
                %update progress
                showProgress('<< Exporting ECG >>');

                [p, name, extn] = fileparts(fName);

                %prepare ecg by determining if data is in rows or cols
                [r,c]=size(ecgf);
                if r==1 %if in cols then transpose
                    ecgf=ecgf';
                end

                %export all or window only?
                flagWinOnly=get(h.chkSelectedOnly,'value');
                if flagWinOnly
                    x1=get(h.txtWinMin,'Value');
                    x2=get(h.txtWinMax,'Value');
                else
                    x1=1; x2=size(ecgf,1);
                end

                %Export ecg according to extension
                switch extn
                    case '.dat' %int16 Binary
                        fidOUT=fopen(fullfile(fPath,fName),'wb');
                        if fidOUT > 0 %check if file was created                        
                            fwrite(fidOUT,ecgf(x1:x2),'int16');
                        else
                            error(['Could not save ' fullfile(fPath,fName) '. Permission denied.'])
                        end
                        fclose(fidOUT);
                    case '.txt' %Text                    
                        ecg=ecgf(x1:x2);                    
                        save(fullfile(fPath,fName),'ecg','-ASCII','-tabs')                    
                        clear ecg
                    case '.mat' %Matlab Binary
                        ecg=ecgf(x1:x2);
                        save(fullfile(fPath,fName),'ecg','-v7')
                    case '.xls' %Excel                        
                        [status, message] = xlswrite(fullfile(fPath,fName),ecgf(x1:x2));
                        %make sure there was no error
                        if ~status 
                            error(message.message)
                        end
                    otherwise
                        error('Choose a valid file extension.')
                end
                %update progress
                showProgress('')
            end
%         catch ME        
%             %update progress
%             showProgress('')
%             error(['Error exporting ECG: ' ME.message])
%         end
    end

    function closeGUI(src,evnt)
        saveParameters;
        fclose('all');
        delete(h.MainFigure)
    end

%%  Utility/Helper functions

    function updatePreview(xval)
    %helper function that updates gui plots       
                    
        %check plot
        if isempty(get(h.axesECG,'Children'))            
            return;
        end
    
        if exist('xval','var')
            if ~isempty(xval)
                sv=xval;
            else
                sv=ceil(get(h.slider,'value')); %get slider value
            end
        else
            sv=ceil(get(h.slider,'value')); %get slider value
        end                
        
        %determine plot x-axes limits
        if sv > (nx-dx)
            lim=[nx-dx nx];
        else
            lim=sv+[0 dx];
        end

        limX=[x(lim(1)) x(lim(2))];        
        %set x axes limits
        set(h.axesECG,'xlim',limX,'ButtonDownFcn',@clickEvent);
        set(h.axesIBI,'xlim',limX);
        %show current position
        set(h.txtWinCurrent,'String',num2str(x(sv)))
        %set min and max values, but not strings
        set(h.txtWinMax,'Value',lim(2));
        set(h.txtWinMin,'Value',lim(1));
        
        %get user's y Limit values if auto is unchecked
        if ~get(h.chkYlimitAuto,'value')
            y2=str2double(get(h.txtYlimit2,'String')); 
            y1=str2double(get(h.txtYlimit1,'String'));            
        else %else set txt values and ylim equal to auto y-limits
            ymax=max(ecgf(lim(1):lim(2)));
            ymin=min(ecgf(lim(1):lim(2)));
            dy=(ymax-ymin);
            y1=ymin-(dy)*0.05;
            y2=ymax+(dy)*0.05;
            set(h.txtYlimit1,'String',num2str(y1));
            set(h.txtYlimit2,'String',num2str(y2));
        end
        %verify y limits
        if (y2>y1) && ~isnan(y2) && ~isnan(y1)
            set(h.axesECG,'ylim',[y1 y2],'ButtonDownFcn',@clickEvent);
        else
            error('Invalid y-limits')
        end        
    end     

    function processEcg(opt)
    %processEcg: processes the selected ecg data by filtering, detecting
    %rwaves and locating IBI outliers. It then plots the filterd ECG, rwave
    %locations and IBI outliers
    %
    %<Inputs>
    %
    %   opt: decides what process to perfom on the ecg. Valid values are 1-3.
    %   opt=3 performs all, opt=2 performs rwave detect and ibi filt, 
    %   opt=1 only performs ibi filt                        
        
        %Make sure data has been loaded at least once. This will eliminate
        %errors thrown because there is no ecg data loaded and functions
        %assume that ecg data is loaded
        if ~flagReady || isempty(flagReady)
            return
        end
    
        %%% Filter ECG %%%
        if opt == 3
%             try
                %update progress
                showProgress('<< Filtering ECG >>');

                ecgf=filterEcg(ecg1); %filter ecg                                
                cla(h.axesECG)
                hold(h.axesECG,'on')
                plot(h.axesECG,x,ecgf)%,fixplot1('%6.3f'); %plot ecg
                
                hold(h.axesECG,'off')
                set(h.axesECG,'ButtonDownFcn',@clickEvent)
                hBeats=[]; hOut1=[]; hOut2=[];
%             catch ME
%                 %update progress
%                 showProgress('')
%                 error(['Error filtering ECG: ' ME.message])
%                 return
%             end
        end
        
        %%% Detect beats/rwaves %%%        
        if opt >= 2
%              try                                            
                 flag=checkRwaveInputs();                 
                 if flag==1
                 
                    %Update Progress
                    showProgress('<< Detecting Beats >>');                    

                    %detect beats
                    [indexR,ibi]=detectBeats(ecgf);
                    
                    %Leslie's custom ibi filter
                     if get(h.chkIbiFiltC,'value')
                        thr=str2double(get(h.txtIbiFiltC1,'string'));
                        hWin=str2double(get(h.txtIbiFiltC2,'string'));
                        artRemove=leslie_IBIfilt(ecgf,ibi,thr,hWin);                                                
                        ibi=ibi(~artRemove,:);
                        indexR=indexR(~artRemove);
                     end
                     
                    %delete beats and outliers from gui
                    hplots=findobj(h.axesECG,'Type','line'); %get handle list of line plots
                    if length(hplots)>1                        
                        delete(hplots(1:end-1));
                    end                                        

                    %plot beat locations
                    hold(h.axesECG,'on')
                    plot(h.axesECG,x(indexR),ecgf(indexR),'go');        
                    hold(h.axesECG,'off')
                    set(h.axesECG,'ButtonDownFcn',@clickEvent)

                    %plot ibi
                    cla(h.axesIBI)
                    hold(h.axesIBI,'on')
                    plot(h.axesIBI,ibi(:,1),ibi(:,2).*1000,'.-k')%,fixplot1('%6.3f')
                    hold(h.axesIBI,'off')
                    
                 elseif flag==0 %if detect beats is set to None                    
                    ibi=[]; index=[];
                    %clear ibi plot
                    cla(h.axesIBI);                    
                    %delete beats and outliers from gui
                    hplots=findobj(h.axesECG,'Type','line'); %get handle list of line plots
                    if length(hplots)>1                        
                        delete(hplots(1:end-1));
                    end   
                 end
%              catch ME
%                 indexR=[]; ibi=[];
%                 %update progress
%                 showProgress('')               
%                 error(['Error detecting beats: ' ME.message])                 
%                 return
%              end
        end
        
        %%% Filter IBI %%%
        if opt >=1
%             try
                flag=checkIbiFiltInputs();
                if flag==1 && ~isempty(ibi) && ~isempty(indexR)
                    %Update Progress
                    showProgress('<< Filtering IBI >>');                                       
                                        
                    art=filterIBI(indexR,ibi,ecgf); %locate outliers

                    %delete outliers from gui, ecg plot
                    hplots=findobj(h.axesECG,'Type','line'); %get handle list of line plots
                    if length(hplots)>2
                        delete(hplots(1));
                    end   

                    %plot outlier locations in ECG
                    hold(h.axesECG,'on');
                    plot(h.axesECG,x(indexR(art)),ecgf(indexR(art)),'ro','MarkerFaceColor','r');            
                    hold(h.axesECG,'off');
                    set(h.axesECG,'ButtonDownFcn',@clickEvent)
                    
                    %delete outliers from gui, IBI plot
                    hplots=findobj(h.axesIBI,'Type','line'); %get handle list of line plots
                    if length(hplots)>1                        
                        delete(hplots(1:end-1));
                    end   
                    
                    %plot outliers in IBI plot
                    hold(h.axesIBI,'on')
                    plot(h.axesIBI,ibi(art,1),ibi(art,2).*1000,'.r');
                    hold(h.axesIBI,'off')                                                                                
                elseif flag==0
                    %delete outliers from gui
                    hplots=findobj(h.axesECG,'Type','line'); %get handle list of line plots
                    if length(hplots)>2
                        delete(hplots(1));
                    end
                    hplots=findobj(h.axesIBI,'Type','line'); %get handle list of line plots
                    if length(hplots)>1                        
                        delete(hplots(1:end-1));
                    end
                end            
%             catch ME
%                 art=[];
%                 %update progress
%                 showProgress('')
%                 error(['Error filtering IBI: ' ME.message])
%                 return
%             end          
        end                
        
        %display results of IBI
        displayResults(ibi,art);
        
        %hide progress
        showProgress('');
    end

    function [ecgout]=filterEcg(ecgin)
        i=get(h.listFilter,'value');
        s=get(h.listFilter,'string');
        optFilt=s{i};                
        
        %replace nan with zeros
        if get(h.chkReplaceNAN,'value')
            inan=isnan(ecgin); %find nan values
            ecgin(inan)=0;  %replace nan w/ zero
        end
        
        if strcmp(optFilt,'Fast Smooth')
            %Remove low freq trend (high pass filter)            
            win1=str2double(get(h.txtSmoothHP,'string'));            
            lev=get(h.listSmoothLevel,'value');
            if win1>0                
                ecgin=ecgin-fastsmooth(ecgin,win1,lev,0);
            end
            %Remove high freq jitter(low pass filter)
            win2=str2double(get(h.txtSmoothLP,'string'));
            if win2>0
                ecgout=fastsmooth(ecgin,win2,lev,0);
            else
                ecgout=ecgin;
            end
        elseif strcmp(optFilt,'Wavelet')
            %filter using wavelets
            i=get(h.listWaveletType,'value');
            s=get(h.listWaveletType,'string');                        
            i2=get(h.listWaveletType2,'value');
            s2=get(h.listWaveletType2,'string');
            waveType=[s{i} s2{i2}]; %construct name of wavelet to use            
            lev=str2double(get(h.txtWaveletLevel,'string')); %level of decomposition
            remove=get(h.txtWaveletRemove,'string'); %get sub-bands to remove            
            remove=str2double(regexp(remove,',','split')); %convert to array of nums
            [c,l]=wavedec(ecgin,lev,waveType); %decompose signal
            c = wthcoef('d',c,l,remove); %force to zero detail coef d1,d2,d8
            c = wthcoef('a',c,l); %force to zero the approx coefficient (low freq trend)
            ecgout=waverec(c,l,waveType); %recompose signal
        else
            ecgout=ecgin;
        end                        
    end

    function [iR,ibi]=detectBeats(ecgin)
               
        % Load template: Global template option       
        templateFile=get(h.txtRwaveTemplate,'string');
        if ~exist(templateFile,'file')
            error(['Template file does not exist: ' templateFile])
            return
        end
        fInfo=whos('-file', templateFile); %get list of variables in .mat file
        template=load(templateFile); %load template
        template=template.(fInfo.name);
                        
        %make self template if chosen
        if get(h.listRwaveMethod,'value')==3            
            % detect r-peaks                               
            tmp=ecgin(1:60000);
            i=matchTemplate(tmp,template,0.40,0.35,1,4);                                        

            % create template from detected peaks
            L=161; %length of template
            b1=i>((L-1)/2);
            b2=i<(length(tmp)-((L-1)/2));
            i=i(b1&b2);
            template=makeTemplate(tmp,i,L);
        end 

        % Detect beats
        ut=str2double(get(h.txtRwaveUT,'string'));
        lt=str2double(get(h.txtRwaveLT,'string'));
        warning off;
        if flagMultiCore
            [iR,rxy2]=matchTemplate(ecgin,template,ut,lt,1,4);
        else
            [iR,rxy2]=matchTemplate(ecgin,template,ut,lt,1,2);
        end
        warning on;                

        if length(iR)>2 %if more than one beat was detected
            % Calc IBI
            ibi(:,1)=x(iR(1:end-1));
            ibi(:,2)=diff(iR./rate); %calc ibi (seconds)
        else
            ibi=[];
        end
        
    end
    
    function [art]=filterIBI(iR,ibi,ecgin)    
                
        if ~isempty(ibi) %if more than one beat was detected 
            
        art=false(size(ibi,1),1); %preallocate/initialize outlier locations
        art1=art; art2=art; art3=art; art4=art; art5=art; art6=art;
        
        % percent
        if get(h.chkIbiFiltP,'value')
            opt1=str2double(get(h.txtIbiFiltP,'string'))/100;
            art1=locateOutliers(ibi(:,1),ibi(:,2),'percent',opt1);
        end
        %sd
        if get(h.chkIbiFiltSD,'value')
            opt1=str2double(get(h.txtIbiFiltSD,'string'));
            art2=locateOutliers(ibi(:,1),ibi(:,2),'sd',opt1);
        end
        %median
        if get(h.chkIbiFiltM,'value')
            opt1=str2double(get(h.txtIbiFiltM1,'string'));
            opt2=str2double(get(h.txtIbiFiltM2,'string'));
            art3=locateOutliers(ibi(:,1),ibi(:,2),'median',opt1,opt2);
        end
        %above thresh
        if get(h.chkIbiFiltAT,'value')
            opt1=str2double(get(h.txtIbiFiltAT,'string'));            
            art4=locateOutliers(ibi(:,1),ibi(:,2),'thresh','above',opt1);
        end
        %below thresh
        if get(h.chkIbiFiltBT,'value')
            opt1=str2double(get(h.txtIbiFiltBT,'string'));
            art5=locateOutliers(ibi(:,1),ibi(:,2),'thresh','below',opt1);
        end       
        
        art=(art | art1 | art2 | art3 | art4 | art5); %combine outlier locations                                
            
        else
            art=[];
        end
    end

    function displayResults(ibi1,art1)
        tH=h.text.results; %handles of text objects                
        
        %disp ibi results        
        if get(h.listRwaveMethod,'value')~=1            
            nibi=size(ibi1,1);
            iz=(ibi(:,2)==0);   %find ibi that = 0
            ibi1=ibi(~iz,2);    %remove any ibi that = 0
            hr=60./ibi1;        %calcuate HR
            ibi1=ibi1.*1000;    %convert to ms
            set(tH(1,3),'string',round(mean(hr)*10)/10)
            set(tH(2,3),'string',round(median(hr)*10)/10)
            set(tH(3,3),'string',round(min(hr)*10)/10)
            set(tH(4,3),'string',round(max(hr)*10)/10)
            set(tH(5,3),'string',round(std(hr)*10)/10)

            set(tH(1,2),'string',round(mean(ibi1)))
            set(tH(2,2),'string',round(median(ibi1)))
            set(tH(3,2),'string',round(min(ibi1)))
            set(tH(4,2),'string',round(max(ibi1)))
            set(tH(5,2),'string',round(std(ibi1)*10)/10)
            
            %total ibi
            nart=sum(art1);
            rart=round(nart/nibi*1000)/10;
            set(tH(6,2),'string',nibi)
            
            %outliers
            flag=checkIbiFiltInputs();
            if flag==1
                set(tH(7,2),'string',nart)
                set(tH(7,3),'string',[num2str(rart) '%'])
            else
                set(tH(7,2),'string','0')
                set(tH(7,3),'string','0.0%')
            end
        else %clear results
            %HR
            set(tH(1,3),'string','0.0')
            set(tH(2,3),'string','0.0')
            set(tH(3,3),'string','0.0')
            set(tH(4,3),'string','0.0')
            set(tH(5,3),'string','0.0')
            %IBI
            set(tH(1,2),'string','0')
            set(tH(2,2),'string','0')
            set(tH(3,2),'string','0')
            set(tH(4,2),'string','0')
            set(tH(5,2),'string','0.0')
            %
            set(tH(6,2),'string','0')
            set(tH(7,2),'string','0')
            set(tH(7,3),'string','0.0%')
        end
               
    end

    function tH = createResultsTbl()
        tH=0;
        aH=h.axesResultsTbl;
        fntSize=8;
        x1=0.1; x2=.6; x3=.9; %relative x position of cols
        %Horizontal Lines
        line([0.05 .95],[.85 .85],'Parent',aH,'Color','black')        
        line([0.05 .95],[.27 .27],'Parent',aH,'Color','black')
        %Col Headers
        %text(x1-.02,.9,'Variable','Parent',aH,'Units','normalized')
        text(x2,.93,'IBI (ms)','Parent',aH,'Units','normalized','HorizontalAlignment','right','FontSize',8)
        text(x3,.93,'HR (bpm)','Parent',aH,'Units','normalized','HorizontalAlignment','right','FontSize',8)
        %Column 1
        tH(1,1)=text(x1,.75,'Mean','Parent',aH,'Units','normalized','FontSize',8);
        tH(2,1)=text(x1,.65,'Med','Parent',aH,'Units','normalized','FontSize',8);
        tH(3,1)=text(x1,.55,'Min','Parent',aH,'Units','normalized','FontSize',8);
        tH(4,1)=text(x1,.45,'Max','Parent',aH,'Units','normalized','FontSize',8);
        tH(5,1)=text(x1,.35,'SD','Parent',aH,'Units','normalized','FontSize',8);
        tH(6,1)=text(x1,.2,'Total','Parent',aH,'Units','normalized','FontSize',8);
        tH(7,1)=text(x1,.1,'Outliers','Parent',aH,'Units','normalized','FontSize',8);
        %Column 2
        tH(1,2)=text(x2,.75,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(2,2)=text(x2,.65,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(3,2)=text(x2,.55,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(4,2)=text(x2,.45,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(5,2)=text(x2,.35,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(6,2)=text(x2,.2,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(7,2)=text(x2,.1,'0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        %Column 3
        tH(1,3)=text(x3,.75,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(2,3)=text(x3,.65,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(3,3)=text(x3,.55,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(4,3)=text(x3,.45,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(5,3)=text(x3,.35,'0.0','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
        tH(7,3)=text(x3,.1,'0.0%','Parent',aH,'Units','normalized','FontSize',8,'HorizontalAlignment','right');
    end
    
    function keyPress(src,evnt)
        %keyPressFcn automatically takes in two inputs
        %src is the object that was active when the keypress occurred
        %evnt stores the data for the key pressed

        %brings in the handles structure in to the function
        handles = guidata(src);

        k= evnt.Key; %k is the key that is pressed
        
        w=round(dx/4);  %num of samples to ignore before looking for next outlier
                        %(DO NOT make larger than dx/2)
        
        switch k
            case 'uparrow'
                 if checkIbiFiltInputs()==1 && sum(art)>0
                     s=get(h.slider,'value');   %get current slider position
                     i=indexR(art);             %get sample #'s for outliers 
                     if (s+dx/2)<i(end)         %if current pos it not beyond last outlier
                        a=find(i>round(s+dx/2+w));%find outliers that are to the rigt of current position
                        if ~isempty(a)
                            sv=round(i(a(1))-dx/2); %determine pos to make next outlier visible
                            %determine plot x-axes limits
                            if sv > (nx-dx)         %if calculated pos not greater than limits
                                sv=nx-dx;           %if true, then only go to axes limit             
                            end                         
                            updatePreview(sv)       %update plot
                            set(h.slider,'value',sv)%set slider value
                        end
                     end
                 end
            case 'downarrow'
                if checkIbiFiltInputs()==1 && sum(art)>0
                     s=get(h.slider,'value');                 
                     i=indexR(art);
                     if (s+dx/2)>i(1)
                        a=find(i<round(s+dx/2-w));
                        if ~isempty(a)
                            sv=round(i(a(end))-dx/2);
                            %determine plot x-axes limits
                            if sv <= 0
                                sv=1;                        
                            end
                            updatePreview(sv)
                            set(h.slider,'value',sv)
                        end
                     end
                 end
            %case 'leftarrow'
            %case 'rightarrow'
            %otherwise
        end
%         if strcmp(k,'return') %if enter was pressed
%             %pause(0.01) %allows time to update
% 
%             %define hObject as the object of the callback that we are going to use
%             %in this case, we are mapping the enter key to the add_pushbutton
%             %therefore, we define hObject as the add pushbutton
%             %this is done mostly as an error precaution
%             %hObject = handles.add_pushbutton; 
% 
%             %call the add pushbutton callback.  
%             %the middle argument is not used for this callback
%             %add_pushbutton_Callback(hObject, [], handles);
%             k;
%         end
    end

    function flag=checkFiltInputs()
    %check inputs for beat/rwave detection options
    %
    %<Outputs>
    %   0=do nothing
    %   1=all ok
    %   -1=input error
    
    	flag=1; %default
        if get(h.listFilter,'value')~=1
            if isempty(get(h.txtWaveletLevel,'string'))           
                flag=-1;
                error('invalid input for wavelet filter level')
                return
            end
            if isempty(get(h.txtWaveletLevel,'string'))
                flag=-1;
                error('invalid input for wavelet filter')
                return
            end
            if isempty(get(h.txtWaveletRemove,'string'))
                flag=-1;
                error('invalid input for wavelet filter')
                return
            end
                
            if isempty(get(h.txtSmoothLP,'string'))
                flag=-1;
                error('invalid input for Fast Smooth filter')
                return
            end
            if isempty(get(h.txtSmoothHP,'string'))
                flag=-1;
                error('invalid input for Fast Smooth filter')
                return
            end
        else
            flag=0;
        end
    end

    function flag=checkRwaveInputs()
    %check inputs for beat/rwave detection options                                
    %
    %<Outputs>
    %   0=do nothing
    %   1=all ok
    %   -1=input error    
        
        flag=1;
        if get(h.listRwaveMethod,'value')~=1
            if isempty(get(h.txtRwaveTemplate,'string'))           
                flag=-1;
                error('invalid input for template file')
                return
            end
            if isempty(get(h.txtRwaveUT,'string'))
                flag=-1;
                error('invalid input for template matching thresh')
                return
            end
            if isempty(get(h.txtRwaveLT,'string'))
                flag=-1;
                error('invalid input for template matching thresh')
                return
            end
        else
            flag=0;
        end
    end

    function flag=checkIbiFiltInputs()
    %check inputs for beat/rwave detection options    
    %
    %<Outputs>
    %   0=do nothing
    %   1=all ok
    %   -1=input error
        
        flag=0;       
        if get(h.chkIbiFiltP,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltP,'string'))           
                flag=-1;
                error('invalid input for ibi percent filter')
                return
            end                    
        end
        
        if get(h.chkIbiFiltSD,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltSD,'string'))
                flag=-1;
                error('invalid input for ibi sd filter')
                return
            end        
        end
        
        if get(h.chkIbiFiltM,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltM1,'string'))
                flag=-1;
                error('invalid input for ibi median filter')
                return
            end
            if isempty(get(h.txtIbiFiltM2,'string'))
                flag=-1;
                error('invalid input for ibi median filter')
                return
            end
        end        
        
        if get(h.chkIbiFiltAT,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltAT,'string'))           
                flag=-1;
                error('invalid input for ibi thresh filter')
                return
            end
        end
        
        if get(h.chkIbiFiltBT,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltBT,'string'))           
                flag=-1;
                error('invalid input for ibi thresh filter')
                return
            end
        end
        
        if get(h.chkIbiFiltC,'value')
            flag=1;
            if isempty(get(h.txtIbiFiltC1,'string'))           
                flag=-1;
                error('invalid input for ibi custom filter')
                return
            end
            if isempty(get(h.txtIbiFiltC2,'string'))           
                flag=-1;
                error('invalid input for ibi custom filter')
                return
            end
        end
                
    end

    function populateFiles(p)
        if (all(p~=0)) && ~isempty(p) && exist(p,'dir')
            fileList = dir(fullfile(p,'*.mat')); %get list of .mat files
            fileList(any([fileList.isdir],1))=[]; %remove any folder/dir from the list
            names = {fileList.name}; %get file names from fileList structure
            [names, ext] = strtok(names, '.'); %seperate names and extensions
            
            nfiles=size(fileList,1); %number of files 
            strList=cell(nfiles,1);  %initilize cell array of strings for listbox.
                      
            % DATABASE Stuff
            conn = database(dataSource,'','');  %db connection
            cursorA = exec(conn, ...            %query db
                'SELECT ALL FileName,Complete FROM tblCompletedFiles WHERE Complete = 1');
            cursorA = fetch(cursorA);           %fecth records
            d=cursorA.data;                     %only need data
            close(conn);                        %close connection
                                                            
            for f=1:nfiles %loop to see if file is marked completed in DB                                             
                %find filename in data returned from db
                flagFound=any(strcmp(fileList(f).name,d(:,1))); 
                
                if  flagFound %if found change set color
                    strList{f}= ['<html><font color=red>' fileList(f).name ...
                        '</font></html>'];
                else
                    strList{f}=fileList(f).name;
                end
             
             end
            
            set(h.listFiles,'String',strList); %add names to list
           
            set(h.listAnn,'String',''); %clear Ann list
            Ann=[];
        else         
            return
        end
    end

    function loadParameters
    %function to load any saved parameter data
        
        try
        f='ecgPreview.mat'; %parameter file
        if exist(f,'file')
            para=load(f);
            para=para.para;
                        
            if isfield(para,'dir')
                if ~isempty(para.dir)
                    set(h.txtDir,'string',para.dir);
                end 
            end
            if isfield(para,'template')
                if ~isempty(para.template)
                    set(h.txtRwaveTemplate,'string',para.template);
                end 
            end                        
        end
        catch ME 
            %do nothing
        end
    end

    function saveParameters
    %function to save any parameter data
        try
        f='ecgPreview.mat'; %parameter file
        flag=false;
        
        tmp=get(h.txtDir,'string');
        if ~isempty(tmp)
                para.dir=tmp; flag=true;            
        end
        tmp=get(h.txtRwaveTemplate,'string');
        if ~isempty(tmp)
                para.template=tmp; flag=true;            
        end
    
        if flag
            save(f,'para');
        end
        catch ME 
            %do nothing
        end
    end

    function showProgress(str)
    %Displays the contents of str as message on the gui. This function is
    %designed to give the user progress updates.
    
        if ~isempty(str)
            set(h.lblProgress,'string',str,'visible','on')
        else
            set(h.lblProgress,'string','','visible','off')
        end
        drawnow; %force matlab to draw it now
    end

    function clickEvent(gcbo,eventdata,handles)
    %Handles click event to allow user to either add annotion for current
    %file or mark current file as being "complete".
    
        s=get(h.MainFigure,'SelectionType'); %type of mouse click        
        switch s
            case 'open' %if double click     
            %h.MainFigure
            pos=get(h.axesECG,'CurrentPoint');
            xpos=pos(1,1);
            ypos=pos(1,2);
                   
            %insert time
            createdTime=datestr(now); %time record was inserted
            
            %filename
            
            %subject ID
	        %subID=tmpStr(1);
	        %date
	        tmpStr = regexp(fname, '_', 'split'); %split file name
            date1=tmpStr(2);
            date1 = strrep(date1, '.', '/'); %replace strings            
            date1=date1{1}; %convert to string
            
            %relative time
            relTime=xpos; %datestr(datenum(num2str(x),'SS'),'HH:MM:SS')
            
            %absolute time
            absTime= strcat(date1,{' '}, ...
                datestr(datenum(num2str(xpos),'SS'),'HH:MM:SS'));
            absTime=absTime{1}; %convert to string
            
            %mean HR
            
            meanHR=get(h.text.results(1,3),'string');            
            
            %Template Thresholds
            thr1=get( h.txtRwaveLT,'string');
            thr2=get( h.txtRwaveUT,'string');
            tempThr=strcat(thr1,{'-'},thr2);
            tempThr=tempThr{1}; %convert to string
            
            %Outlier Thresh
            thr1=get(h.txtIbiFiltBT,'string');
            thr2=get(h.txtIbiFiltAT,'string');
            outThr=strcat(thr1,{'-'},thr2);
            outThr=outThr{1}; %convert to string
            
            %create annotation input dialog
                dlg_title = 'ANN';
            prompt = {'Annotation','Notes','FileName', ...
                'RelTime','RecordDate','MeanHR','TemplateThr', ...
                'OutlierThr','CreatedDate'};
            recData = {'','',fname, ...
                num2str(relTime),date1,meanHR,tempThr, ...
                outThr,createdTime};
            answer = inputdlg(prompt,dlg_title,1,recData);
            if ~isempty(answer)
                %disp(answer)
                addAnnotation(answer')
            end
            
            case 'alt' %case alt click or right click
                
                %Time record created
                createdTime=datestr(now); %time record was inserted

                %filename                               
                
                %date
                tmpStr = regexp(fname, '_', 'split'); %split file name
                date1=tmpStr(2);
                date1 = strrep(date1, '.', '/'); %replace strings            
                date1=date1{1}; %convert to string
                
                button = questdlg( ...
                    'Do you want to mark this FileName as completed?' ...
                    ,'Mark As Completed','Yes');                                
                if strcmp(button,'Yes')
                    recData={fname,date1,true,createdTime};
                    addCompletedFile(recData)
                end

        end
    end
    
    function addAnnotation(recData)
    %Inserts recData as an annotation into the user specified database.
    %recDat must be a cell array

  %  try 
        recData{6}=single(str2num(recData{6})); %convert meanHR to a single
        colnames = {'Annotation','Notes','FileName', ...
            'RelTime','RecordDate','MeanHR','TemplateThr', ...
            'OutlierThr','CreatedDate'};
        conn = database(dataSource,'','');
        fastinsert(conn, 'tblAnn', colnames, recData)
        close(conn)
  %  catch me
  %  error(me)
   % end

    end

    function addCompletedFile(recData)
    %Inserts recData to specify whether the current file has been completed
    %into the user specified database. recDat must be a cell array

    %  try             
        colnames = {'FileName','RecordDate','Complete','CreatedDate'};
        conn = database(dataSource,'','');
        fastinsert(conn, 'tblCompletedFiles', colnames, recData)
        close(conn)

        %repopulate list
        if exist(path1,'dir')
            set(h.txtDir,'string',path1)
            populateFiles(path1);
        end

    %  catch me
    %  error(me)
    % end
    end  

    function output=removeHTML(str)
    % removeHTML: removes html from str
        if nargin < 1;
            output='';
            return; 
        end
    
        if ~isempty(findstr('html',str))
            l=findstr('<',str);
            r=findstr('>',str);
            output=str(r(2)+1:l(3)-1);
        else
            output=str;
        end
  
    end    
end