# OFGEM Energy Price Cap — Power Query Pipeline

Two Power Query M-code scripts built to extract, model, and analyse live UK energy pricing data from the OFGEM website — no manual downloads, no copy-paste.

---

## Files

| File | Description |
|---|---|
| `OFGEM_crawler_LinkedIn.m` | Fact table pipeline — scrapes live pricing data, builds a star schema, joins payment method and cost category dimensions |
| `RollingCalendar.m` | Date dimension — dynamic rolling 2-year calendar with ISO 8601 weeks, calendar quarters, and fiscal quarters (April start) |

---

## How to use

Both scripts are Power Query M-code and can be loaded into Excel or Power BI via **Advanced Editor**.

Two variables at the top of `OFGEM_crawler_LinkedIn.m` control the entire pipeline:

```
CurrentWWW         → OFGEM page URL
firstTBLStartIndex → HTML table index where pricing data begins (currently 17)
```

Update these if OFGEM restructures their page. Nothing else needs changing.

> `Web.BrowserContents` requires Excel desktop — OFGEM tables are JavaScript-rendered and won't load via a standard HTTP request.

> **Verifying table indices:** If the query stops returning data, open the OFGEM page in a browser, press F12 (Developer Tools) → Inspector, and count the `DIV.table-container.simplebar-container.border-color-theme` elements before the pricing tables. Update `firstTBLStartIndex` to match.

---

## Stack

Power Query M · `Web.BrowserContents` · `Html.Table` · CSS selectors · star schema · ISO 8601

---

*Built during a career break, 2024–2025. Part of a wider portfolio of data pipeline and automation projects.*
