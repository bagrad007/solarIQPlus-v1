/** Canonical sensor/API values are Celsius; UI is Fahrenheit-first. */
export function fahrenheitFromCelsius(tempC) {
  if (tempC == null || Number.isNaN(Number(tempC))) return null;
  const f = (Number(tempC) * 9) / 5 + 32;
  return Math.round(f * 10) / 10;
}
