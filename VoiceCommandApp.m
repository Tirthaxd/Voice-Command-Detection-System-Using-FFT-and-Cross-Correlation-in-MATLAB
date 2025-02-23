classdef VoiceCommandApp < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        RecordMainButton            matlab.ui.control.Button
        RecordSubButton             matlab.ui.control.Button
        Num1EditFieldLabel          matlab.ui.control.Label
        Num1EditField               matlab.ui.control.EditField
        Num2EditFieldLabel          matlab.ui.control.Label
        Num2EditField               matlab.ui.control.EditField
        MainCommandLabel            matlab.ui.control.Label
        SubCommandLabel             matlab.ui.control.Label
        ResultLabel                 matlab.ui.control.Label
        AudioAxesRaw                matlab.ui.control.UIAxes
        AudioAxesProcessed          matlab.ui.control.UIAxes
        InfoTextArea                matlab.ui.control.TextArea
        CorrAxes                    matlab.ui.control.UIAxes   % For Cross-Correlation
        FFTAxes                     matlab.ui.control.UIAxes   % For FFT Plot
        % New music control buttons
        PlayButton                  matlab.ui.control.Button
        PauseButton                 matlab.ui.control.Button
        ResumeButton                matlab.ui.control.Button
    end

    properties (Access = private)
        fs = 44100;            % Sampling frequency
        rawAudio;              % Recorded raw audio data
        procAudio;             % Processed audio data

        %% Command Definitions & Reference Audio File Paths
        % Main options
        mainOptions = {'calculator', 'music', 'shopping'};
        refMainOptions = ["G:\202216009\FINAL\CALCULATOR.wav", ...
                          "G:\202216009\FINAL\MUSIC.wav", ...
                          "G:\202216009\FINAL\FOODPANDA.wav"];

        % Calculator operations
        calcOps = {'addition', 'subtraction', 'multiplication', 'division'};
        refCalcOps = ["G:\202216009\FINAL\ADDITION.wav", ...
                      "G:\202216009\FINAL\SUBTRACTION.wav", ...
                      "G:\202216009\FINAL\MULTIPLY.wav", ...
                      "G:\202216009\FINAL\division.unknown"];

        % Music language options (for recognition)
        musicLangs = {'bangla', 'english', 'hindi'};
        refMusicLangs = ["G:\202216009\FINAL\BANGLA.mp3", ...
                         "G:\202216009\FINAL\ENGLISH.mp3", ...
                         "G:\202216009\FINAL\HINDI.mp3"];

        % Shopping items
        shoppingItems = {'pizza', 'burger', 'coke'};
        refShoppingItems = ["G:\202216009\FINAL\pizza.mp3", ...
                            "G:\202216009\FINAL\BURGER.mp3", ...
                            "G:\202216009\FINAL\COKE.mp3"];

        % For plotting cross-correlation and FFT
        bestCorrData = [];      % Cross-correlation data of the best match
        bestCorrLag  = [];      % Lag for cross-correlation
        inputFFT     = [];      % FFT of input signal for best match
        refFFT       = [];      % FFT of reference signal for best match
        
        %% Music Player Properties
        musicPlayer;          % audioplayer object for music playback
        currentMusicFile;     % String path for current music file
    end

    methods (Access = private)

        %% Audio Recording and Preprocessing
        function recordAudio(app)
            recObj = audiorecorder(app.fs, 16, 1);
            app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Recording audio... Please speak.'];
            recordblocking(recObj, 2);
            app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Recording stopped.'];
            app.rawAudio = getaudiodata(recObj);

            % Plot Raw Audio
            plot(app.AudioAxesRaw, app.rawAudio);
            title(app.AudioAxesRaw, 'Raw Audio');
            xlabel(app.AudioAxesRaw, 'Samples'); ylabel(app.AudioAxesRaw, 'Amplitude');

            % Process audio: Remove silence, apply highpass filter and normalize
            temp = app.removeSilence(app.rawAudio);
            temp = highpass(temp, 50, app.fs);
            if max(abs(temp)) == 0
                app.procAudio = temp;
            else
                temp = temp / max(abs(temp));
                app.procAudio = temp;
            end

            % Plot Processed Audio
            plot(app.AudioAxesProcessed, app.procAudio);
            title(app.AudioAxesProcessed, 'Processed Audio');
            xlabel(app.AudioAxesProcessed, 'Samples'); ylabel(app.AudioAxesProcessed, 'Amplitude');
        end

        %% Voice Command Recognition using Cross-Correlation & FFT
        function [recognized, bestCorr, bestLag, inputFFT, refFFT] = recognizeCommand(app, signal, options, refPaths)
            bestMatch = '';
            bestScore = -Inf;
            bestCorr = [];
            bestLag = [];

            % Normalize input
            signal = app.normalizeLength(signal);
            if max(abs(signal)) ~= 0
                signal = signal / max(abs(signal));
            end

            % Compute FFT of input signal
            inputFFT = abs(fft(signal));

            for i = 1:length(options)
                [refSig, fsRef] = audioread(refPaths(i));
                refSig = highpass(refSig, 50, fsRef);
                refSig = app.removeSilence(refSig);
                refSig = app.normalizeLength(refSig);
                if max(abs(refSig)) ~= 0
                    refSig = refSig / max(abs(refSig));
                end

                % Cross-correlation
                [xcorrRes, lag] = xcorr(signal, refSig);
                maxCorr = max(abs(xcorrRes));

                % FFT magnitude difference
                refSigFFT = abs(fft(refSig));
                fftDiff = sum(abs(inputFFT - refSigFFT));

                % Combine scores (weights can be tuned)
                score = maxCorr - 0.5 * fftDiff;
                if score > bestScore
                    bestScore = score;
                    bestMatch = options{i};
                    bestCorr = xcorrRes;
                    bestLag = lag;
                    refFFT = refSigFFT;  
                end
            end
            recognized = bestMatch;
        end

        %% Helper Functions: Silence Removal and Normalization
        function out = removeSilence(app, x)
            threshold = 0.02;
            indices = find(abs(x) > threshold);
            if isempty(indices)
                out = x;
            else
                out = x(indices(1):indices(end));
            end
        end

        function normSig = normalizeLength(app, x)
            targetLen = 22050; % about 0.5 sec at 44.1 kHz
            if length(x) > targetLen
                normSig = x(1:targetLen);
            else
                normSig = [x; zeros(targetLen - length(x),1)];
            end
        end

        %% Plot Cross-Correlation and FFT
        function plotCorrAndFFT(app)
            % Plot cross-correlation
            if ~isempty(app.bestCorrData) && ~isempty(app.bestCorrLag)
                plot(app.CorrAxes, app.bestCorrLag, app.bestCorrData);
                title(app.CorrAxes, 'Cross-Correlation (Best Match)');
                xlabel(app.CorrAxes, 'Lag');
                ylabel(app.CorrAxes, 'Amplitude');
            else
                cla(app.CorrAxes, 'reset'); % Clear if no data
                title(app.CorrAxes, 'Cross-Correlation');
            end

            % Plot FFT magnitude
            if ~isempty(app.inputFFT) && ~isempty(app.refFFT)
                hold(app.FFTAxes, 'off');
                plot(app.FFTAxes, app.inputFFT, 'b');
                hold(app.FFTAxes, 'on');
                plot(app.FFTAxes, app.refFFT, 'r');
                legend(app.FFTAxes, {'Input FFT','Reference FFT'}, 'Location','best');
                title(app.FFTAxes, 'FFT Magnitude Comparison');
                xlabel(app.FFTAxes, 'Frequency Bin');
                ylabel(app.FFTAxes, 'Magnitude');
                hold(app.FFTAxes, 'off');
            else
                cla(app.FFTAxes, 'reset');
                title(app.FFTAxes, 'FFT Magnitude Comparison');
            end
        end

        %% Main Command Processing
        function processMainCommand(app)
            % Record main command voice
            app.recordAudio();

            [mainCmd, cData, cLag, inFFT, rFFT] = app.recognizeCommand(app.procAudio, app.mainOptions, app.refMainOptions);

            app.MainCommandLabel.Text = "Main Command: " + mainCmd;
            app.InfoTextArea.Value = [app.InfoTextArea.Value; ['You selected: ' mainCmd]];

            % Store cross-correlation data and FFT data for plotting
            app.bestCorrData = cData;
            app.bestCorrLag  = cLag;
            app.inputFFT     = inFFT;
            app.refFFT       = rFFT;

            % Plot cross-correlation and FFT
            app.plotCorrAndFFT();

            % Enable or disable UI fields based on selection
            switch mainCmd
                case 'calculator'
                    app.Num1EditField.Enable = 'on';
                    app.Num2EditField.Enable = 'on';
                    app.RecordSubButton.Enable = 'on';
                    app.InfoTextArea.Value = [app.InfoTextArea.Value; ...
                        'Please enter two numbers and then press Record Sub-Command for operation.'];
                case 'music'
                    app.Num1EditField.Enable = 'off';
                    app.Num2EditField.Enable = 'off';
                    app.RecordSubButton.Enable = 'on';
                    app.InfoTextArea.Value = [app.InfoTextArea.Value; ...
                        'Say Bangla, English, or Hindi for the song language.'];
                case 'shopping'
                    app.Num1EditField.Enable = 'off';
                    app.Num2EditField.Enable = 'off';
                    app.RecordSubButton.Enable = 'on';
                    app.InfoTextArea.Value = [app.InfoTextArea.Value; ...
                        'Say Pizza, Burger, or Coke for your order.'];
                otherwise
                    app.InfoTextArea.Value = [app.InfoTextArea.Value; ...
                        'Command not recognized. Try again.'];
            end
        end

        %% Sub Command Processing (Based on Main Command)
        function processSubCommand(app)
            % Record a second voice command for sub-options
            app.recordAudio();
            mainCmd = lower(erase(app.MainCommandLabel.Text,"Main Command: "));

            switch mainCmd
                case 'calculator'
                    [op, cData, cLag, inFFT, rFFT] = app.recognizeCommand(app.procAudio, app.calcOps, app.refCalcOps);
                    app.SubCommandLabel.Text = "Operation: " + op;
                    % Store cross-correlation and FFT data
                    app.bestCorrData = cData;
                    app.bestCorrLag  = cLag;
                    app.inputFFT     = inFFT;
                    app.refFFT       = rFFT;
                    % Plot them
                    app.plotCorrAndFFT();

                    % Get numbers from UI fields
                    num1 = str2double(app.Num1EditField.Value);
                    num2 = str2double(app.Num2EditField.Value);
                    if isnan(num1) || isnan(num2)
                        app.ResultLabel.Text = "Invalid numeric inputs.";
                        return;
                    end
                    switch op
                        case 'addition'
                            res = num1 + num2;
                        case 'subtraction'
                            res = num1 - num2;
                        case 'multiplication'
                            res = num1 * num2;
                        case 'division'
                            if num2 ~= 0
                                res = num1 / num2;
                            else
                                app.ResultLabel.Text = "Error: Division by zero!";
                                return;
                            end
                        otherwise
                            app.ResultLabel.Text = "Operation not recognized.";
                            return;
                    end
                    app.ResultLabel.Text = "Result: " + res;

                case 'music'
                    [lang, cData, cLag, inFFT, rFFT] = app.recognizeCommand(app.procAudio, app.musicLangs, app.refMusicLangs);
                    app.SubCommandLabel.Text = "Song Language: " + lang;
                    % Store cross-correlation and FFT data
                    app.bestCorrData = cData;
                    app.bestCorrLag  = cLag;
                    app.inputFFT     = inFFT;
                    app.refFFT       = rFFT;
                    % Plot them
                    app.plotCorrAndFFT();

                    % Set the current music file path based on recognized language
                    switch lower(lang)
                        case 'bangla'
                            app.currentMusicFile = "G:\202216009\Songs\sona_ro_palonko.mp3";  % Update to your file path
                        case 'english'
                            app.currentMusicFile = "G:\202216009\Songs\night_changes.mp3"; % Update to your file path
                        case 'hindi'
                            app.currentMusicFile = "G:\202216009\Songs\Tere Bin X Sajni Re.mp3";   % Update to your file path
                        otherwise
                            app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Unrecognized music language.'];
                            return;
                    end
                    app.ResultLabel.Text = "Playing " + lang + " song...";
                    % Automatically start music playback
                    app.playMusic();

                case 'shopping'
                    [item, cData, cLag, inFFT, rFFT] = app.recognizeCommand(app.procAudio, app.shoppingItems, app.refShoppingItems);
                    app.SubCommandLabel.Text = "Item: " + item;
                    % Store cross-correlation and FFT data
                    app.bestCorrData = cData;
                    app.bestCorrLag  = cLag;
                    app.inputFFT     = inFFT;
                    app.refFFT       = rFFT;
                    % Plot them
                    app.plotCorrAndFFT();

                    app.ResultLabel.Text = item + " order has been placed!";

                otherwise
                    app.ResultLabel.Text = "Sub-command not processed.";
            end
        end

        %% Music Playback Methods
        function playMusic(app)
            % Stop any existing music if playing
            if ~isempty(app.musicPlayer) && isplaying(app.musicPlayer)
                stop(app.musicPlayer);
            end
            % Check that a current music file has been set
            if isempty(app.currentMusicFile)
                app.InfoTextArea.Value = [app.InfoTextArea.Value; 'No music file specified.'];
                return;
            end
            % Read the music file
            [y, fsMusic] = audioread(app.currentMusicFile);
            % Create the audioplayer object and play
            app.musicPlayer = audioplayer(y, fsMusic);
            play(app.musicPlayer);
            app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Music playing...'];
        end

        function pauseMusic(app)
            if ~isempty(app.musicPlayer) && isplaying(app.musicPlayer)
                pause(app.musicPlayer);
                app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Music paused.'];
            end
        end

        function resumeMusic(app)
            if ~isempty(app.musicPlayer)
                resume(app.musicPlayer);
                app.InfoTextArea.Value = [app.InfoTextArea.Value; 'Music resumed.'];
            end
        end

    end

    %% Callbacks for Component Events
    methods (Access = private)

        % Callback for Record Main Command button
        function RecordMainButtonPushed(app, event)
            app.processMainCommand();
        end

        % Callback for Record Sub-Command button
        function RecordSubButtonPushed(app, event)
            app.processSubCommand();
        end

        % Callback for Play button
        function PlayButtonPushed(app, event)
            app.playMusic();
        end

        % Callback for Pause button
        function PauseButtonPushed(app, event)
            app.pauseMusic();
        end

        % Callback for Resume button
        function ResumeButtonPushed(app, event)
            app.resumeMusic();
        end
    end

    %% Component Initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            % Create main figure
            app.UIFigure = uifigure('Position',[100 100 1200 650]);
            app.UIFigure.Name = 'Voice Command DSP App';

            % Record Main Command Button
            app.RecordMainButton = uibutton(app.UIFigure, 'push',...
                'Position',[50 600 180 30],...
                'Text','Record Main Command',...
                'ButtonPushedFcn', @(btn,event) app.RecordMainButtonPushed(event));

            % Record Sub Command Button
            app.RecordSubButton = uibutton(app.UIFigure, 'push',...
                'Position',[250 600 180 30],...
                'Text','Record Sub-Command',...
                'Enable','off',...
                'ButtonPushedFcn', @(btn,event) app.RecordSubButtonPushed(event));

            % Numeric Input for Calculator Option
            app.Num1EditFieldLabel = uilabel(app.UIFigure,...
                'Position',[50 540 100 22],...
                'Text','Number 1:');
            app.Num1EditField = uieditfield(app.UIFigure, 'text',...
                'Position',[150 540 100 22], 'Enable','off');

            app.Num2EditFieldLabel = uilabel(app.UIFigure,...
                'Position',[50 500 100 22],...
                'Text','Number 2:');
            app.Num2EditField = uieditfield(app.UIFigure, 'text',...
                'Position',[150 500 100 22], 'Enable','off');

            % Label to display recognized main command
            app.MainCommandLabel = uilabel(app.UIFigure,...
                'Position',[450 600 400 30],...
                'Text','Main Command: ');
            app.MainCommandLabel.FontSize = 14;

            % Label to display sub command (operation, language, item)
            app.SubCommandLabel = uilabel(app.UIFigure,...
                'Position',[450 560 400 30],...
                'Text','Sub Command: ');
            app.SubCommandLabel.FontSize = 14;

            % Label to display result/output
            app.ResultLabel = uilabel(app.UIFigure,...
                'Position',[450 520 400 30],...
                'Text','Result: ');
            app.ResultLabel.FontSize = 14;

            % Axes for Raw Audio Plot
            app.AudioAxesRaw = uiaxes(app.UIFigure,...
                'Position',[50 340 350 150]);
            title(app.AudioAxesRaw, 'Raw Audio');

            % Axes for Processed Audio Plot
            app.AudioAxesProcessed = uiaxes(app.UIFigure,...
                'Position',[450 340 350 150]);
            title(app.AudioAxesProcessed, 'Processed Audio');

            % Axes for Cross-Correlation
            app.CorrAxes = uiaxes(app.UIFigure,...
                'Position',[50 150 350 150]);
            title(app.CorrAxes, 'Cross-Correlation');

            % Axes for FFT
            app.FFTAxes = uiaxes(app.UIFigure,...
                'Position',[450 150 350 150]);
            title(app.FFTAxes, 'FFT Magnitude Comparison');

            % Text Area for Info/Instructions
            app.InfoTextArea = uitextarea(app.UIFigure,...
                'Position',[850 150 300 330]);
            app.InfoTextArea.Value = { ...
                'Welcome to the Voice Command DSP App.', ...
                'Press "Record Main Command" and speak one of the following: calculator, music, or shopping.'};

            % Music Control Buttons
            app.PlayButton = uibutton(app.UIFigure, 'push',...
                'Position',[850 100 90 30],...
                'Text','Play',...
                'ButtonPushedFcn', @(btn,event) app.PlayButtonPushed(event));
            app.PauseButton = uibutton(app.UIFigure, 'push',...
                'Position',[950 100 90 30],...
                'Text','Pause',...
                'ButtonPushedFcn', @(btn,event) app.PauseButtonPushed(event));
            app.ResumeButton = uibutton(app.UIFigure, 'push',...
                'Position',[1050 100 90 30],...
                'Text','Resume',...
                'ButtonPushedFcn', @(btn,event) app.ResumeButtonPushed(event));
        end
    end

    %% App Creation and Deletion
    methods (Access = public)

        % Construct app
        function app = VoiceCommandApp
            createComponents(app);
            registerApp(app, app.UIFigure);
        end

        % Code that executes before app deletion
        function delete(app)
            delete(app.UIFigure)
        end
    end
end
