# OFGEM Energy Price Cap — Data Pipeline

Two pipelines built to extract, model, and analyse live UK energy pricing data from the OFGEM website — no manual downloads, no copy-paste.

The Python scraper (`ofgem_scraper_v1_2.py`) supersedes the original Power Query approach (`OFGEM_crawler_LinkedIn.m`) following an OFGEM page restructure in 2026 which moved from static HTML tables to JavaScript-rendered content. Both are kept here as they tell different parts of the same story.

---

## Files

| File | Version | Description |
|---|---|---|
| `ofgem_scraper_v1_2.py` | v1.2 | Python scraper — Playwright, BeautifulSoup, Pandas. Current approach. |
| `OFGEM_crawler_LinkedIn.m` | v1.0 | Power Query M-code scraper — CSS selectors, star schema, fact/dimension model. Pre-2026 page structure. |
| `RollingCalendar.m` | v1.9 | Power Query date dimension — dynamic rolling 2-year calendar, ISO 8601 weeks, fiscal quarters (April start). |
| `ofgem_EnergyPriceCap.csv` | — | Sample output from most recent scraper run. |

---

## Python Scraper — `ofgem_scraper_v1_2.py`

### Requirements
```bash
pip install playwright pandas
playwright install chromium
```

### Usage
Run as a script:
```bash
python3 ofgem_scraper_v1_2.py
```

Or in Jupyter (async environment):
```python
df = await scrape_clean()
```

### Output
`ofgem_EnergyPriceCap.csv` — 135 rows, 7 columns:

| Column | Description |
|---|---|
| `Region` | 14 UK regions + Great Britain average |
| `Standing Charge [period] (pence/day)` | Daily standing charge — period label read from page |
| `Unit Rate [period] (pence/kWh)` | Unit rate — period label read from page |
| `PaymentMethod` | Direct Debit / Standard Credit / Prepayment Meter |
| `EnergyType` | Electricity / Gas / Economy 7 |

### What to update if OFGEM restructures their page
Two variables at the top of the script control everything:

```python
URL       → OFGEM page URL
TABLE_MAP → maps table index to (PaymentMethod, EnergyType)
```

Period labels and units are read dynamically from the page — no hardcoded dates anywhere.

> **Known limitation (v1.3):** `TABLE_MAP` still hardcodes table order. If OFGEM adds or reorders payment method tables, labels will misalign. Fix planned: scrape labels from page headings automatically.

---

## Power Query M-code — `OFGEM_crawler_LinkedIn.m`

Built against the pre-2026 OFGEM page structure. Demonstrates:

- Dynamic CSS selector generation via `List.Transform`
- Multi-table loop using `List.Numbers` — one variable controls all four tables
- Fact table construction with surrogate keys
- Dimension relationships managed in the Excel data model (Power Pivot)

Two variables at the top control the entire pipeline:

```
CurrentWWW         → OFGEM page URL
firstTBLStartIndex → HTML table index where pricing data begins
```

> **Note:** The pre-2026 page used JavaScript-rendered HTML tables requiring `Web.BrowserContents` (Excel desktop only). The 2026 restructure moved to client-side CSV generation, making this approach obsolete for current data — but the architecture remains valid for any similarly structured source.

> **Verifying table indices:** If adapting this to another source, open the page in a browser, press F12 → Inspector, and search for the target CSS class to count element positions. Update `firstTBLStartIndex` to match.

---

## Rolling Calendar — `RollingCalendar.m`

Dynamic date dimension for Power Query / Power BI. Generates a rolling 2-year window from today — no hardcoded date ranges.

| Column | Description |
|---|---|
| `Date` | Calendar date |
| `DayOfWeek` | Full day name |
| `CalendarQuarter` | Q1–Q4 (January start) |
| `FiscalQuarter` | Q1–Q4 (April start — UK fiscal year) |
| `RollingCalendarDays` | Days remaining in calendar year |
| `RollingFiscalDays` | Days remaining in fiscal year |
| `RollingCalendarWeeks` | ISO 8601 week number |

Load via **Advanced Editor** in Power Query or Power BI.

---

## Stack

**Python:** Playwright · Pandas · BeautifulSoup · `pathlib` · `re`

**Power Query:** M-code · `Web.BrowserContents` · `Html.Table` · CSS selectors · star schema · ISO 8601

---

*Built during a career break, 2024–2026. Part of a wider portfolio of data pipeline and automation projects.*
