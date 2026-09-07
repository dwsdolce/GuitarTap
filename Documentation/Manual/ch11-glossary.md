# Chapter 11 — Glossary

<!-- STATUS: STUB — needs full definitions -->

**Air (Helmholtz) mode** — The resonance of the air cavity inside the instrument body, excited by the motion of air through the sound hole. Also called the Helmholtz resonance.

**Bandwidth (−3 dB)** — The width of a spectral peak measured at 3 dB below its maximum. Narrower bandwidth (higher Q) indicates lower damping.

**Cross/Long ratio** — The ratio of cross-grain Young's modulus to longitudinal Young's modulus (E_C / E_L). For spruce, typically 0.04–0.08.

**Decay time** — The time (in seconds) for a tap response to decay to 1/e of its peak amplitude. A measure of structural damping; higher values indicate lower damping.

**Diagonal (fLC) tap** — A third, optional tap measurement in Plate mode (the free-length-cross torsional mode) used to estimate the shear modulus G_LC, which feeds the Gore target thickness calculation. Enabled with **Measure Diagonal (fLC) Tap** in Settings; when omitted the Gore thickness is reported with the message "G_LC assumed 0" and carries an over-estimate of roughly 5–7% (§4.8).

**Dipole mode** — A bending mode of the guitar top plate where the upper and lower bouts move in opposite phase.

**E_C (Young's modulus, cross-grain)** — Stiffness of the wood measured perpendicular to the grain direction (radial or tangential). Expressed in GPa.

**E_L (Young's modulus, longitudinal)** — Stiffness of the wood measured along the grain direction. Expressed in GPa. The primary stiffness parameter for tonewood selection.

**FFT (Fast Fourier Transform)** — The algorithm used to convert the time-domain microphone signal into the frequency-domain spectrum displayed by the app.

**FLC** — see **Diagonal (fLC) tap**.

**Free-free beam** — A beam suspended at its bending-mode nodal points (22.4% from each end), leaving it free to vibrate without damping at the supports. The standard suspension assumption for Plate and Brace material measurements. In practice a single hold at one of the two nodal points is sufficient — see §4.4.

**Free-Length-Cross (fLC) mode** — The torsional mode excited by the Diagonal (fLC) tap; its frequency feeds the shear-modulus calculation. See Diagonal (fLC) tap.

**G_LC (shear modulus)** — The shear modulus of the plate, derived from the Diagonal (fLC) tap frequency. Required by the full Gore target thickness formula; substituted with zero when the diagonal tap is not measured.

**Gore target thickness** — The recommended final thickness for a guitar top or back plate, calculated from the plate dimensions, Young's moduli, and a stiffness target, following the method described by Trevor Gore.

**Q factor** — Quality factor; the ratio of a resonant peak's centre frequency to its −3 dB bandwidth. Q = f₀ / Δf. Higher Q indicates lower damping.

**Radiation ratio (R)** — A figure of merit for tonewood; R = c_L / √ρ = √(E_L/ρ³). Higher values indicate a lighter, stiffer wood that radiates sound more efficiently.

**Ring mode** — A symmetric bending mode of the guitar top plate involving the rim of the lower bout.

**Specific modulus (E/ρ)** — Young's modulus divided by density. Also written as c² (where c is the speed of sound in the material). A key predictor of tap tone quality.

**Speed of sound (c)** — The speed at which a longitudinal stress wave travels through the wood: c_L = √(E_L / ρ). Expressed in m/s.

**Tap Tone Ratio** — The ratio of the top mode frequency to the air mode frequency (f_top / f_air). Typical range for a well-voiced guitar: 1.8–2.4.

**Top / Back mode** — The fundamental bending mode of the guitar top plate or back plate, respectively; often the strongest peak in a guitar tap spectrum.

**Unknown mode** — A detected spectral peak that does not fall within any defined frequency window for the selected guitar subtype. Shown on the chart by default; can be hidden with **Settings → Advanced → Analysis Settings → Show Unknown Modes** (§3.1, §8.5). An Unknown peak can be re-identified by tapping its row in the Analysis Results panel and assigning a standard mode (Air, Top, Back, Dipole, Ring, Upper Modes) or a custom label (§3.7).

**Upper modes** — Resonant modes above the main top and back modes; their significance increases with frequency and build stage.
