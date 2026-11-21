async function exchangeRates(req, res) {
  try {
    const response = await fetch("https://open.er-api.com/v6/latest/IDR");
    if (!response.ok) {
      return res.status(502).json({ error: "Exchange-rate provider unavailable" });
    }
    const data = await response.json();
    res.json({
      base: "IDR",
      rates: {
        IDR: 1,
        USD: data.rates.USD,
        EUR: data.rates.EUR,
      },
    });
  } catch (err) {
    res.status(502).json({ error: "Could not retrieve exchange rates" });
  }
}

module.exports = { exchangeRates };
