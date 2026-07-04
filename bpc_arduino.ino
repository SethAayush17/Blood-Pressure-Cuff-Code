// =============================================================================
// bpc_arduino.ino — Blood Pressure Cuff Inflation and Data Acquisition
// =============================================================================
// Controls the automatic blood pressure cuff inflation/deflation sequence
// and streams pressure and oscillometric signal data to MATLAB over serial.
//
// Hardware connections:
//   Pin 3 (INPUT_PULLUP): Pushbutton — reads LOW when pressed to start inflation
//   Pin 8 (OUTPUT):       NPN transistor base — HIGH turns on pump and valve
//   A0:                   INA126P output — overall cuff pressure signal (1–4V = 0–200 mmHg)
//   A1:                   Oscillometric signal output after bandpass filter and amplifier
//
// Sequence:
//   1. Button press (pin 3 LOW) sets started flag and turns on transistor (pin 8 HIGH)
//      activating the air pump and valve to inflate the cuff
//   2. When A0 voltage exceeds 3.8V (~180 mmHg), inflation stops — transistor turned off
//   3. A 5-second delay allows initial pressure transients to settle before sampling begins
//   4. During deflation, both signals are sampled at ~100 Hz (10ms delay per loop)
//      and streamed to MATLAB via serial in CSV format: "elapsed,pressure,oscillometric"
//   5. When A0 voltage drops to ~1.1V (~0 mmHg), deflation is complete and sending stops
//
// Voltage to pressure conversion:
//   INA126P output is calibrated so 1V = 0 mmHg and 4V = 200 mmHg
//   P (mmHg) = 66.67 * (V - 1)
//
// Serial output format (115200 baud, CSV):
//   elapsed_ms, pressure_mmHg, oscillometric_mmHg
// =============================================================================

// =============================================================================
// State Variables
// =============================================================================
bool          started           = false; // True after button press — keeps pump on after button released
unsigned long startTime         = 0;     // Timestamp when deflation began (ms)
bool          deflationStarted  = false; // True once target inflation pressure is reached
bool          sending           = false; // True once 5-second settling delay has passed
unsigned long deflationStartTime = 0;    // Reserved for future use

void setup() {
    Serial.begin(115200); // Must match MATLAB baud rate

    // Pin 3: pushbutton input with internal pull-up — reads HIGH at rest, LOW when pressed
    pinMode(3, INPUT_PULLUP);

    // Pin 8: output to NPN transistor base — controls pump and valve via LM317 regulated 3V supply
    pinMode(8, OUTPUT);
    digitalWrite(8, LOW); // Ensure pump and valve are off at startup
}

void loop() {
    // -------------------------------------------------------------------------
    // Read Pressure Signal from A0
    // INA126P output: 1V = 0 mmHg, 4V = 200 mmHg
    // ADC range: 0–1023 maps to 0–5V
    // -------------------------------------------------------------------------
    int raw = analogRead(A0);
    float voltage = raw * (5.0 / 1023.0); // Convert 10-bit ADC value to voltage (0–5V)

    // -------------------------------------------------------------------------
    // Button Detection — Start Inflation
    // INPUT_PULLUP means pin 3 reads LOW when button is pressed.
    // "started" flag latches true so the pump stays on after the button is released.
    // -------------------------------------------------------------------------
    int state = digitalRead(3);
    if (state == LOW) {
        started = true;
    }

    // -------------------------------------------------------------------------
    // Inflation Stop — Target Pressure Reached
    // When A0 voltage exceeds 3.8V (~180 mmHg), inflation is complete.
    // Transistor is turned off, stopping both pump and valve simultaneously.
    // A 5-second settling delay begins before data streaming starts.
    // -------------------------------------------------------------------------
    if (voltage > 3.8 && !deflationStarted) {
        digitalWrite(8, LOW);   // Turn off transistor — stops pump and opens valve
        started = false;        // Clear inflation latch
        startTime = millis();   // Record deflation start time for elapsed calculation
        deflationStarted = true;
        sending = false;
    } else if (started) {
        digitalWrite(8, HIGH);  // Keep transistor on to continue inflating
    }

    // -------------------------------------------------------------------------
    // 5-Second Settling Delay
    // Wait 5 seconds after reaching target pressure before streaming data.
    // Allows initial pressure transients from the pump stopping to settle
    // so the first samples are clean deflation data.
    // -------------------------------------------------------------------------
    if (deflationStarted && !sending) {
        if (millis() - startTime >= 5000) {
            sending = true;
        }
    }

    // -------------------------------------------------------------------------
    // Data Streaming During Deflation
    // Samples both signals at ~100 Hz (10ms loop delay) and sends CSV over serial.
    // Pressure signal from A0 gives overall cuff pressure.
    // Oscillometric signal from A1 gives filtered arterial pulse signal.
    // Both converted from ADC counts to mmHg using P = 66.67 * (V - 1).
    // Streaming stops when A0 drops to ~1.1V (cuff fully deflated, ~0 mmHg).
    // -------------------------------------------------------------------------
    if (sending) {
        float elapsed = millis() - startTime; // Time since deflation started (ms)

        // Read oscillometric signal from A1 (bandpass filtered + amplified)
        int adcVal_osc = analogRead(A1);

        float voltage_pres = voltage;                          // Pressure signal voltage (from A0)
        float voltage_osc  = adcVal_osc * (5.0 / 1023.0);    // Oscillometric signal voltage (from A1)

        // Convert voltages to pressure in mmHg using linear calibration
        // INA126P calibrated: 1V = 0 mmHg, 4V = 200 mmHg → P = 66.67 * (V - 1)
        float pressure_pres = 66.67 * (voltage_pres - 1);
        float pressure_osc  = 66.67 * (voltage_osc  - 1);

        // Stream CSV line to MATLAB: elapsed_ms, pressure_mmHg, oscillometric_mmHg
        Serial.print(elapsed);
        Serial.print(",");
        Serial.print(pressure_pres);
        Serial.print(",");
        Serial.println(pressure_osc);

        // -------------------------------------------------------------------------
        // Deflation Complete — Stop Streaming
        // When pressure drops to ~1.1V (~7 mmHg), cuff is fully deflated.
        // Reset state flags to allow a new measurement on next button press.
        // -------------------------------------------------------------------------
        if (voltage <= 1.1) {
            float totalTime = (millis() - startTime) / 1000.0; // Total deflation time (s) — for reference
            sending          = false;
            deflationStarted = false;
        }
    }

    delay(10); // 10ms delay between samples → ~100 Hz sampling rate
}
