% =============================================================================
% bpc_matlab.m — Blood Pressure Signal Processing and Calculation
% =============================================================================
% Receives pressure and oscillometric signal data streamed from the Arduino
% over serial at 115200 baud, processes the signals to extract systolic
% pressure (SBP), diastolic pressure (DBP), mean arterial pressure (MAP),
% and heart rate (HR), and displays annotated plots of the results.
%
% Signal Processing Pipeline:
%   1. Collect 100 Hz sampled data from Arduino over serial into a 3-column
%      array: time (ms), pressure signal (mmHg), oscillometric signal
%   2. Smooth pressure signal with a 4th-order Butterworth low-pass at 2 Hz
%   3. Bandpass filter oscillometric signal (4th-order Butterworth, 0.8–4 Hz)
%      then high-pass at 1 Hz to remove DC offset
%   4. Apply Hilbert transform to extract instantaneous amplitude envelope,
%      smoothed with a 2nd-order Butterworth low-pass at 0.5 Hz
%   5. Identify MAP at point of maximum oscillometric amplitude (MAO)
%   6. Determine SBP and DBP using oscillometric ratio constants with
%      adaptive pressure offsets and physiological range validation
%   7. Calculate heart rate from peak detection on a separate 0.8–3 Hz
%      bandpass filtered signal using median RR interval
%
% Outputs:
%   - Figure 1: Live pressure vs time plot during data collection
%   - Figure 2: Filtered oscillometric signal with Hilbert envelope
%   - Figure 3: Annotated pressure plot with MAP, SBP, DBP markers
%   - Command window: MAP, SBP, DBP, HR numerical results
%   - pressure_data.csv: Raw collected data saved to disk
% =============================================================================

clear; close all;

% =============================================================================
% Serial Port Configuration
% =============================================================================
port = "COM4";      % Serial port — update to match your system (e.g. /dev/ttyUSB0 on Linux)
baud = 115200;      % Must match Arduino sketch baud rate
duration = 25;      % Data collection duration in seconds
frequency = 100;    % Expected sampling frequency in Hz

% =============================================================================
% Serial Connection and Data Buffer Initialization
% =============================================================================
clear s;                        % Release port if held from a previous run
s = serialport(port, baud);     % Open serial connection to Arduino
flush(s);                       % Clear any existing data in the buffer

numSamples = duration * frequency;
data = zeros(numSamples, 3);    % Preallocate: [time(ms), pressure(mmHg), oscillometric(mmHg)]
disp("Collecting data...");

% =============================================================================
% Live Data Collection and Real-Time Plot
% Reads CSV-formatted lines from Arduino: "time,pressure,oscillometric"
% Plots both signals in real time as data arrives
% =============================================================================
figure(1);
h1 = animatedline('Color', 'b'); % Pressure signal (blue)
h2 = animatedline('Color', 'r'); % Oscillometric signal (red)
xlabel("Time (s)");
ylabel("Pressure (mmHg)");
title("Pressure vs Time");
grid on;

i = 1;
while i <= numSamples
    try
        line = readline(s);
        values = str2double(split(line, ","));
        if numel(values) == 3 && all(~isnan(values))
            data(i,:) = values';
            addpoints(h1, values(1)/1e3, values(2)); % Convert ms to s for x-axis
            addpoints(h2, values(1)/1e3, values(3));
            drawnow limitrate;
            i = i + 1;
        end
    catch
        continue % Skip malformed lines without stopping collection
    end
end

disp("Done collecting data.");

% Save raw data to CSV for offline reprocessing
fileName = "pressure_data.csv";
writematrix(data, fileName);

% =============================================================================
% Signal Extraction
% =============================================================================
p_raw   = data(:, 2); % Raw pressure signal in mmHg
osc_raw = data(:, 3); % Raw oscillometric signal in mmHg

% Compute actual sampling frequency from timestamps (accounts for serial jitter)
actual_fs = 1 / median(diff(data(:,1)/1e3));
fs = actual_fs;

% =============================================================================
% Filtering
% =============================================================================

% Bandpass filter oscillometric signal to isolate heartbeat frequency band
% (0.8–4 Hz corresponds to 48–240 BPM, covering the full physiological range)
[b_bp, a_bp] = butter(4, [0.8 4]/(fs/2), 'bandpass');
osc_bp = filtfilt(b_bp, a_bp, osc_raw);

% Low-pass filter pressure signal to smooth out oscillometric ripples
% while preserving the slow deflation curve (cutoff: 2 Hz)
[b_lp, a_lp] = butter(4, 2/(fs/2), 'low');
p_smooth = filtfilt(b_lp, a_lp, p_raw);

% =============================================================================
% Hilbert Envelope Extraction
% Removes DC offset from bandpass-filtered oscillometric signal, then applies
% the Hilbert transform to compute the instantaneous amplitude envelope.
% The envelope connects the peaks of the oscillometric pulses and is used
% to identify the point of maximum oscillation amplitude (MAO) for MAP detection.
% =============================================================================

% High-pass at 1 Hz to remove any remaining DC offset and center signal at zero
[b_dc, a_dc] = butter(2, 1.0/(fs/2), 'high');
osc_centered = filtfilt(b_dc, a_dc, osc_bp);

% Hilbert transform: produces analytic signal; magnitude = instantaneous amplitude
analytic   = hilbert(osc_centered);
env_inst   = abs(analytic);

% Smooth raw envelope with low-pass filter at 0.5 Hz to produce a clean curve
[b_env, a_env] = butter(2, 0.5/(fs/2), 'low');
env_smooth = filtfilt(b_env, a_env, env_inst);

% =============================================================================
% Plot Oscillometric Signal with Hilbert Envelope
% =============================================================================
figure(2);
plot(data(:,1)/1e3, osc_centered, 'r'); hold on
plot(data(:,1)/1e3, env_smooth, 'g');    % Upper envelope
plot(data(:,1)/1e3, -env_smooth, 'm');   % Lower envelope (mirror)
plot(data(:,1)/1e3, zeros(size(data,1),1), 'k--'); % Zero reference
xlabel("Time (s)"); ylabel("Amplitude (mmHg)");
title("Oscillometric Signal with Hilbert Envelope");
grid on;
legend('Oscillometric Signal (filtered)', 'Upper Envelope', 'Lower Envelope');

% =============================================================================
% MAP Detection
% MAP corresponds to the cuff pressure at the point of maximum oscillometric
% amplitude (MAO). A fixed 15 mmHg pressure offset compensates for the
% propagation delay introduced by the filters.
% =============================================================================
amplitude = env_smooth;
[maxAmp, MAO] = max(amplitude); % MAO = sample index of maximum amplitude

% Compute deflation rate in mmHg/s from smoothed pressure curve
deflation_rate = (p_smooth(1) - p_smooth(end)) / (data(end,1) - data(1,1)) * 1e3;

% Convert 15 mmHg MAP offset to sample delay using deflation rate and fs
pressure_offset_MAP = 15; % mmHg
sample_offset_MAP = round(pressure_offset_MAP / deflation_rate * fs);

% Read MAP from pressure curve at the offset-corrected sample index
if MAO > sample_offset_MAP
    MAP = p_smooth(MAO - sample_offset_MAP);
else
    MAP = p_smooth(MAO);
end

% =============================================================================
% SBP and DBP Pressure Offsets
% SBP uses an adaptive offset that scales linearly with MAP (clamped 15–40 mmHg)
% DBP uses a fixed 7 mmHg offset
% Both offsets converted to sample delays for alignment with envelope
% =============================================================================
pressure_offset_SBP = 15 + (MAP - 70) * 1.2;
pressure_offset_SBP = max(15, min(40, pressure_offset_SBP)); % Clamp to [15, 40]

pressure_offset_DBP = 7; % mmHg — fixed offset

sample_offset_SBP = round(pressure_offset_SBP / deflation_rate * fs);
sample_offset_DBP = round(pressure_offset_DBP / deflation_rate * fs);

% =============================================================================
% SBP and DBP Detection Using Oscillometric Ratio Method
% SBP occurs before MAO where envelope amplitude = K_SBP * maxAmp (50%)
% DBP occurs after MAO where envelope amplitude = K_DBP * maxAmp (80%)
% The sample with the smallest error relative to the target amplitude is selected.
% Physiological range checks discard implausible readings.
% =============================================================================
K_SBP = 0.50; % SBP ratio constant — envelope at SBP = 50% of peak
K_DBP = 0.80; % DBP ratio constant — envelope at DBP = 80% of peak
target_SBP_amp = K_SBP * maxAmp;
target_DBP_amp = K_DBP * maxAmp;

SBP = NaN; DBP_ratio = NaN;
minErrSBP = inf; minErrDBP = inf;

% Search for SBP in samples before MAO
for i = 1:MAO
    if i > sample_offset_SBP
        p_check = p_smooth(i - sample_offset_SBP);
    else
        p_check = p_smooth(i);
    end
    if ~(p_check > 60 && p_check < 250) % Discard physiologically implausible values
        continue;
    end
    err = abs(amplitude(i) - target_SBP_amp);
    if err < minErrSBP
        minErrSBP = err;
        SBP = p_check;
    end
end

% Search for DBP in samples after MAO
for i = MAO:size(data,1)
    if i > sample_offset_DBP
        p_check = p_smooth(i - sample_offset_DBP);
    else
        p_check = p_smooth(i);
    end
    if ~(p_check > 30 && p_check < 150 && p_check < MAP) % Must be below MAP
        continue;
    end
    err = abs(amplitude(i) - target_DBP_amp);
    if err < minErrDBP
        minErrDBP = err;
        DBP_ratio = p_check;
    end
end

% Formula-based crosscheck values (for comparison only — ratio method is primary)
DBP_formula = ((3 * MAP) - SBP) / 2;
SBP_formula = 3 * (MAP - DBP_ratio) + DBP_ratio;

% =============================================================================
% Heart Rate Calculation
% Uses a separate bandpass filter (0.8–3 Hz) on the raw oscillometric signal,
% detects peaks with minimum height/distance/prominence thresholds,
% gates RR intervals to physiologically plausible range (0.33–1.5 s = 40–180 BPM),
% and uses the median interval for robustness against detection errors.
% =============================================================================
[b_hr, a_hr] = butter(4, [0.8 3]/(fs/2), 'bandpass');
osc_hr = filtfilt(b_hr, a_hr, osc_raw);

hr_thresh  = 0.25 * max(osc_hr);       % Minimum peak height = 25% of max
min_peak_d = round(0.40 * fs);         % Minimum peak distance = 0.4s (150 BPM max)

[~, locs_hr] = findpeaks(osc_hr, ...
    'MinPeakHeight',     hr_thresh, ...
    'MinPeakDistance',   min_peak_d, ...
    'MinPeakProminence', 0.5 * hr_thresh);

if length(locs_hr) >= 2
    peak_times = data(locs_hr, 1) / 1e3;       % Convert peak sample indices to seconds
    intervals  = diff(peak_times);              % RR intervals in seconds
    intervals  = intervals(intervals >= 0.33 & intervals <= 1.50); % Gate to 40–180 BPM
    if ~isempty(intervals)
        HR = 60 / median(intervals);            % BPM from median RR interval
    else
        HR = NaN;
        disp("Warning: No valid intervals after gating.");
    end
else
    HR = NaN;
    disp("Warning: Not enough peaks found for HR calculation.");
end

% =============================================================================
% Annotated Pressure Plot — MAP, SBP, DBP Markers
% =============================================================================
figure(3);
plot(data(:,1)/1e3, p_smooth); hold on
plot(data(:,1)/1e3, osc_raw);
xlabel("Time (s)"); ylabel("Pressure (mmHg)");
title("Pressure vs Time"); grid on;

% MAP marker
plot(data(MAO,1)/1e3, MAP, 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 6);
text(data(MAO,1)/1e3, MAP+10, 'MAP', 'FontWeight', 'bold');

% SBP marker — find closest point on smoothed pressure curve
if ~isnan(SBP)
    [~, idxSBP] = min(abs(p_smooth - SBP));
    plot(data(idxSBP,1)/1e3, SBP, 'bo', 'MarkerFaceColor', 'b', 'MarkerSize', 6);
    text(data(idxSBP,1)/1e3, SBP+10, 'SBP', 'FontWeight', 'bold');
end

% DBP marker — find closest point on smoothed pressure curve
if ~isnan(DBP_ratio)
    [~, idxDBP] = min(abs(p_smooth - DBP_ratio));
    plot(data(idxDBP,1)/1e3, DBP_ratio, 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 6);
    text(data(idxDBP,1)/1e3, DBP_ratio+10, 'DBP', 'FontWeight', 'bold');
end

legend('Pressure Signal', 'Oscillometric Signal', 'MAP', 'SBP', 'DBP (ratio)');

% =============================================================================
% Print Results to Command Window
% =============================================================================
fprintf('Actual fs           = %.1f Hz\n', actual_fs);
fprintf('Deflation rate      = %.2f mmHg/s\n', deflation_rate);
fprintf('Sample offset MAP   = %d samples\n', sample_offset_MAP);
fprintf('Pressure offset SBP = %.1f mmHg\n', pressure_offset_SBP);
fprintf('Sample offset SBP   = %d samples\n', sample_offset_SBP);
fprintf('Sample offset DBP   = %d samples\n', sample_offset_DBP);
fprintf('MAP                 = %.2f mmHg\n', MAP);
fprintf('SBP (ratio)         = %.2f mmHg\n', SBP);
fprintf('SBP (formula)       = %.2f mmHg\n', SBP_formula);
fprintf('DBP (ratio)         = %.2f mmHg\n', DBP_ratio);
fprintf('DBP (formula)       = %.2f mmHg\n', DBP_formula);
if ~isnan(HR)
    fprintf('HR                  = %.2f BPM\n', HR);
else
    fprintf('HR                  = Could not be calculated\n');
end
disp("End of program.");
