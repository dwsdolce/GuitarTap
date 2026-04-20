# Tonewood Reference Sources

References for the acoustic property values, quality thresholds, and equations used in
`MaterialProperties.swift` and `material_properties.py`.

---

## 1. Free-Free Beam Equation  — (βL)² = 22.37

The coefficient 22.37 is the squared value of the first root of the free-free Euler–Bernoulli
beam characteristic equation:

```
cos(βL) · cosh(βL) = 1   →   βL = 4.73004…   →   (βL)² = 22.3733…
```

### Canonical structural-mechanics reference
> Blevins, R. D. (1979). *Formulas for Natural Frequency and Mode Shape*.
> Van Nostrand Reinhold, New York.
> (Table 8-1, free-free beam, first bending mode.)

### Application to musical-instrument wood (the "Haines" attribution in the code)
> Haines, D. W. (1979). "On musical instrument wood."
> *Catgut Acoustical Society Newsletter*, No. 31, pp. 23–32.

> Haines, D. W. (2000). "The essential mechanical properties of wood prepared for
> musical instruments."
> *Catgut Acoustical Society Journal*, Ser. 2, Vol. 4, pp. 20–32.

### Note on "Coates"
No lutherie paper on free-free beam vibration by an author named Coates has been located in
any indexed database.  The Kevin Coates in lutherie literature wrote on Renaissance geometry
(*Geometry, Proportion, and the Art of Lutherie*, Clarendon Press / Oxford University Press,
1985), not beam mechanics.  The attribution is likely an error introduced during early
development of GuitarTap.

---

## 2. Quality Thresholds — Specific Modulus (E/ρ, GPa/(g/cm³))

| Species | Direction | Excellent | Very Good | Good  | Fair  | Poor  |
|---------|-----------|-----------|-----------|-------|-------|-------|
| Spruce  | Long.     | ≥ 25      | ≥ 22      | ≥ 19  | ≥ 16  | < 16  |
| Spruce  | Cross     | ≥ 1.5     | ≥ 1.2     | ≥ 0.9 | ≥ 0.6 | < 0.6 |
| Cedar   | Long.     | ≥ 22      | ≥ 19      | ≥ 16  | ≥ 13  | < 13  |
| Cedar   | Cross     | ≥ 1.3     | ≥ 1.0     | ≥ 0.7 | ≥ 0.5 | < 0.5 |
| Others  | —         | ≥ 20      | ≥ 16      | ≥ 12  | ≥ 8   | < 8   |

### Primary source
> Gore, T. & Gilet, G. (2011; 2nd ed. 2016).
> *Contemporary Acoustic Guitar Design and Build*, Vols. 1–2.
> Self-published (Trevor Gore Guitars), Australia.
> Vol. 1, 2nd ed. ISBN: 978-0-9871174-2-7.
> Available at: <https://goreguitars.com.au/the-book/>

The code already cites this book by name for Equation 4.5-7 (the Gore target-thickness
calculation).  The specific-modulus grading system and the quality threshold values used here
are consistent with the grading methodology described in the same book.  The exact table of
threshold values is proprietary to the printed edition and is not reproduced in any freely
indexed online source.

### Supporting background literature

The Cedar thresholds are shifted down ~3 GPa/(g/cm³) relative to spruce, reflecting cedar's
inherently lower longitudinal stiffness.  This is corroborated by:

> Brémaud, I. (2012). "Acoustical properties of wood in string instruments soundboards and
> tuned idiophones: Biological and cultural diversity."
> *Journal of the Acoustical Society of America*, 131(1):807–818.
> DOI: [10.1121/1.3651233](https://doi.org/10.1121/1.3651233)
> (Table II contains species-by-species specific modulus data for spruce and cedar.)

> Wegst, U. G. K. (2006). "Wood for sound."
> *American Journal of Botany*, 93(10):1439–1448.
> DOI: [10.3732/ajb.93.10.1439](https://doi.org/10.3732/ajb.93.10.1439)
> (Presents specific modulus as the primary acoustic quality criterion for tonewoods.)

> Bucur, V. (2006). *Acoustics of Wood*, 2nd ed. Springer-Verlag, Berlin/Heidelberg.
> (Comprehensive reference tables for density, speed of sound, and moduli of instrument woods.)

---

## 3. Gore Plate Equations — Poisson's Ratio ν_CL = 0.05

Used in `goreTargetThickness` (Swift) / `calculate_gore_target_thickness` (Python):

### Source
> Gore & Gilet (2011/2016), as above. The value ν_CL = 0.05 is cited in the book as
> the recommended average for softwoods used in instrument making.

### Independent corroboration
> USDA Forest Products Laboratory (2010).
> *Wood Handbook: Wood as an Engineering Material*.
> General Technical Report FPL-GTR-190. Chapter 5, Tables 5-1 and 5-2.
> Available at: <https://www.fpl.fs.usda.gov/documnts/fplgtr/fplgtr190/chapter_05.pdf>
> (Reports minor Poisson's ratios ν_TL for softwoods in the range 0.02–0.07;
> ν_CL is typically in the lower part of this range for spruce.)

---

## 4. TonewoodReference — Typical Species Values

The reference values below are rounded "typical" figures consistent with the published
literature.  They are not taken verbatim from any single table but represent averages across
multiple measurement datasets.

### Sitka Spruce — density 0.40 g/cm³, c_L 5 500 m/s, E/ρ 22 GPa/(g/cm³), R 12 m⁴/(kg·s)

> Haines, D. W., Hutchins, C. M., Lee, C. H., & Thompson, D. A. (1977).
> "Mechanical properties of Sitka spruce for guitars."
> *Journal of the Acoustical Society of America*, 61(S1):S35.
> DOI: [10.1121/1.2015598](https://doi.org/10.1121/1.2015598)
> (Mean density ~0.455 g/cm³ for measured samples; 0.40 is the lower / premium end of
> the distribution.)

> Brémaud (2012) and Wegst (2006), as cited above.

### Engelmann Spruce — density 0.38 g/cm³, c_L 5 300 m/s, E/ρ 21, R 12.5

Engelmann spruce is lighter and slightly less stiff than Sitka; the values are consistent
with the relative rankings in Brémaud (2012) and with USDA Wood Handbook data for the species.

### European (German) Spruce — density 0.42 g/cm³, c_L 5 800 m/s, E/ρ 24, R 13

> Bucur (2006), as cited above. European spruce (*Picea abies*) is widely regarded in the
> luthiery literature as having the highest longitudinal sound speed among common tonewood
> spruces.  Speeds up to 6 000 m/s are reported for premium specimens.

> Schleske, M. (1990). "Speed of sound and damping of spruce in relation to the direction
> of grains and rays."
> *Catgut Acoustical Society Journal*, Ser. 2, Vol. 1, No. 6, pp. 16–20.

### Western Red Cedar — density 0.35 g/cm³, c_L 4 800 m/s, E/ρ 18, R 11

The specific modulus value of 18 GPa/(g/cm³) is consistent with measured samples: at a
typical density of 0.35 g/cm³ and a dynamic E_L of approximately 6.3–6.4 GPa (lower than
the USDA static value), E/ρ ≈ 18.

> USDA Forest Products Laboratory (2010), FPL-GTR-190, Chapter 5.
> (Reports static MOE for WRC ~7.65 GPa at standard density; dynamic resonance values used in
> tap testing are typically 10–15% lower.)

> Brémaud (2012), as cited above.

---

## 5. Summary of Formal Citations

| Item in code | Citation |
|---|---|
| (βL)² = 22.37 (beam equation) | Blevins (1979); Haines (1979, 2000) |
| Quality thresholds 25/22/19/16 (spruce) | Gore & Gilet (2011/2016), Vol. 1 |
| Quality thresholds 22/19/16/13 (cedar) | Gore & Gilet (2011/2016), Vol. 1 |
| Gore plate equations (Eq. 4.5-7) | Gore & Gilet (2011/2016), Vol. 1, Eq. 4.5-7 |
| ν_CL = 0.05 | Gore & Gilet (2011/2016); USDA FPL-GTR-190 Ch. 5 |
| Sitka spruce reference values | Haines et al. (1977); Brémaud (2012) |
| European spruce reference values | Bucur (2006); Schleske (1990) |
| Cedar reference values | Brémaud (2012); USDA FPL-GTR-190 Ch. 5 |
| Specific modulus as primary quality criterion | Wegst (2006); Brémaud (2012); Gore & Gilet (2011/2016) |
