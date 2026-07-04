Automatic Digital Blood Pressure Monitor — Arduino + MATLAB
A fully functional automatic oscillometric blood pressure monitor built from scratch, measuring systolic pressure, diastolic pressure, mean arterial pressure, and heart rate. Validated within 5% error against a commercial monitor across 5 test subjects.
How It Works
A pushbutton triggers the Arduino to inflate an arm cuff to approximately 160 mmHg via an air pump, occluding blood flow in the brachial artery. The pump shuts off and an air valve opens, allowing the cuff to deflate slowly over ~30 seconds through a C-clamp restricted valve. As the cuff deflates, arterial pulsations create tiny oscillometric pressure ripples on the deflation curve. The Arduino samples both the overall pressure signal and the isolated oscillometric signal at 100 Hz, streaming 3,000 data points over serial at 115200 baud to MATLAB for processing — bypassing the Arduino's 2KB SRAM limit.
Hardware

Piezoresistive pressure transducer in a Wheatstone bridge configuration (three fixed 100kΩ resistors + piezoresistive element), providing common-mode rejection and linear pressure response
INA126P instrumentation amplifier (G = 68.7, input impedance >100MΩ) amplifies the millivolt-level bridge differential output to a 1–4V range spanning 0–200 mmHg across 614 of the Arduino's 1024 ADC steps (0.326 mmHg/step resolution)
LM317 linear voltage regulator (R1=1kΩ, R2=1.4kΩ) provides stable 3V to the air pump and valve, driven through a 2N3904 NPN transistor switched by Arduino pin 8 through an 86Ω base resistor
2nd-order Chebyshev low-pass filter at 4 Hz (−47 dB at 60 Hz) attenuates power line interference below 1% of oscillometric amplitude
3rd-order Chebyshev high-pass filter at 0.695 Hz removes the slow deflation trend (~0.033 Hz) while passing the full oscillometric band (0.58–2.0 Hz)
Inverting amplifier stage (Rf=100kΩ, Rin=1.2kΩ, G≈−83.3) re-inverts the Chebyshev phase-shifted signal and brings the oscillometric amplitude into the Arduino's ADC range
All LM358 op-amps DC biased at 2V with coupling capacitors to stay within non-rail-to-rail output limits on a 5V supply

Signal Processing (MATLAB)

Pressure signal smoothed with a 4th-order Butterworth low-pass filter at 2 Hz
Oscillometric signal bandpass filtered (4th-order Butterworth, 0.8–4 Hz) then high-pass filtered at 1 Hz to remove DC offset
Hilbert transform applied to the filtered oscillometric signal to extract instantaneous amplitude envelope; raw envelope smoothed with a 2nd-order Butterworth low-pass at 0.5 Hz
MAP identified at the point of maximum oscillometric amplitude (MAO) with a fixed 15 mmHg pressure offset to account for filter propagation delay
SBP determined using an adaptive ratio constant K_SBP (envelope amplitude = K_SBP × max amplitude) with an adaptive pressure offset scaling linearly with MAP between 15–40 mmHg; values outside 60–250 mmHg discarded
DBP determined using K_DBP = 0.80 with a fixed 7 mmHg offset; values outside 30–150 mmHg or above MAP discarded
Heart rate calculated from a separate 4th-order bandpass filter (0.8–3 Hz), peak detection with minimum height/distance/prominence thresholds, RR interval gating to 0.33–1.5 seconds (40–180 BPM), and median interval to reduce sensitivity to detection errors
