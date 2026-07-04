**Automatic Digital Blood Pressure Monitor — Arduino + MATLAB**

An automatic oscillometric blood pressure monitor built from scratch that measures systolic pressure, diastolic pressure, mean arterial pressure, and heart rate. Validated within 5% error against a commercial monitor across 5 test subjects.
How It Works

A pushbutton triggers the Arduino to inflate an arm cuff to ~160 mmHg, occluding blood flow in the brachial artery. The cuff then slowly deflates over ~30 seconds through a C-clamp restricted valve. As it deflates, arterial pulsations create tiny oscillometric pressure ripples on the deflation curve. The Arduino samples both signals at 100 Hz and streams 3,000 data points over serial at 115200 baud to MATLAB for processing.

**Hardware & Analog Signal Chain**

Piezoresistive pressure transducer in a Wheatstone bridge providing common-mode rejection and linear pressure response
INA126P instrumentation amplifier (G=68.7) scales the millivolt-level bridge output to 1–4V across 0–200 mmHg, giving 0.326 mmHg per ADC step
2N3904 NPN transistor switches the pump and valve, driven through an 86Ω base resistor from Arduino pin 8
LM317 voltage regulator provides stable 3V to the pump and valve
2nd-order Chebyshev low-pass filter at 4 Hz attenuates 60 Hz power line interference by 47 dB
3rd-order Chebyshev high-pass filter at 0.695 Hz removes the slow deflation trend while passing the full oscillometric band (0.58–2.0 Hz)
Inverting amplifier (G≈−83.3) re-inverts the Chebyshev phase-shifted signal and brings the oscillometric amplitude into the Arduino's ADC range

**Signal Processing (MATLAB)**

Pressure signal smoothed with a 4th-order Butterworth low-pass filter at 2 Hz
Oscillometric signal bandpass filtered (4th-order Butterworth, 0.8–4 Hz) and high-pass filtered at 1 Hz to remove DC offset
Hilbert transform extracts the instantaneous amplitude envelope, smoothed with a 2nd-order Butterworth low-pass at 0.5 Hz
MAP identified at the point of maximum oscillometric amplitude with a 15 mmHg pressure offset for filter propagation delay
SBP and DBP determined using oscillometric ratio constants (K_SBP, K_DBP) with adaptive pressure offsets and physiological range validation
Heart rate calculated from peak detection on a separate 0.8–3 Hz bandpass filtered signal, with RR interval gating between 0.33–1.5 seconds and median interval averaging
