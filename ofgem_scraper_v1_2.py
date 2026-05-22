"""
OFGEM Energy Price Cap — Regional Rates Scraper
================================================
Version: 1.2
Changes from v1.1:
    - Fixed sleep replaced with selector-based wait + minimal buffer (Issue 2)
    - Region deduplication uses regex instead of midpoint split (Issue 3)
    - Unit detection warns loudly on failure instead of silent empty string (Issue 5)
    - Output path anchored to script location via pathlib (Issue 6)

Requirements:
    pip install playwright pandas
    playwright install chromium

Output:
    ofgem_EnergyPriceCap.csv — combined fact table with all payment methods and regions

MAINTENANCE:
    Two variables control the entire pipeline:
        URL       → OFGEM page URL — update if page moves
        TABLE_MAP → table index to label mapping — update if OFGEM adds/removes payment methods

    Column headers and period labels are read dynamically from the page.
    Units are detected from cell values and appended to headers automatically.
    No hardcoded dates, periods, or units anywhere in this script.

    KNOWN LIMITATION (Issue 1 — v1.3):
        TABLE_MAP still hardcodes table index to payment method/energy type mapping.
        If OFGEM reorders or adds tables, labels will silently misalign.
        Fix planned: scrape payment method and energy type labels from page headings.
"""

from playwright.async_api import async_playwright
from io import StringIO
from pathlib import Path
import pandas as pd
import re

# -------------------------------------------------------------------------
# CONFIGURATION — update here only
# -------------------------------------------------------------------------
URL = "https://www.ofgem.gov.uk/information-consumers/energy-advice-households/energy-price-cap-unit-rates-and-standing-charges"

# Output path anchored to script location — works regardless of working directory
# Issue 6 fix: previously saved to wherever the script was called from
SAVE_PATH = Path(__file__).parent / "ofgem_EnergyPriceCap.csv"

# Maps table index to (PaymentMethod, EnergyType)
# Table 0 is the summary table and is skipped
# Issue 1 (outstanding — v1.3): this mapping is still hardcoded
TABLE_MAP = {
    1: ("Direct Debit", "Electricity"),
    2: ("Direct Debit", "Gas"),
    3: ("Direct Debit", "Economy 7"),
    4: ("Standard Credit", "Electricity"),
    5: ("Standard Credit", "Gas"),
    6: ("Standard Credit", "Economy 7"),
    7: ("Prepayment Meter", "Electricity"),
    8: ("Prepayment Meter", "Gas"),
    9: ("Prepayment Meter", "Economy 7"),
}

# -------------------------------------------------------------------------
# CLEANING FUNCTIONS
# -------------------------------------------------------------------------
def clean_region(value):
    """Strip 'Region' prefix and deduplicated region name.
    Raw format: 'RegionNorth WestNorth West' → 'North West'

    Issue 3 fix: previously used midpoint character split which could fail
    on odd-length strings (e.g. 'Great Britain average').
    Now uses regex back-reference to find the repeated pattern reliably.
    """
    if not isinstance(value, str):
        return value
    value = re.sub(r'^Region', '', value)
    match = re.match(r'^(.+)\1$', value)
    return match.group(1) if match else value

def extract_number(value):
    """Extract the last numeric value from a cell — units stripped entirely.
    Raw format: '...202652.22 pence per day52.22 pence per day' → 52.22
    Returns float for immediate analytical use.
    """
    if not isinstance(value, str):
        return value
    matches = re.findall(r'\d+\.\d+', value)
    return float(matches[-1]) if matches else value

def detect_unit(value, col_name=""):
    """Detect the unit from a raw cell value.
    Returns a clean unit string to append to the column header.

    Issue 5 fix: previously returned empty string silently on no match.
    Now logs a warning so failures are visible rather than silent.
    """
    if not isinstance(value, str):
        return ""
    if re.search(r'pence per day', value, re.IGNORECASE):
        return "pence/day"
    if re.search(r'pence per kwh', value, re.IGNORECASE):
        return "pence/kWh"
    # Warn loudly — silent empty string would produce headers without units
    print(f"WARNING: Could not detect unit for column '{col_name}' — header will have no unit suffix. Raw value: {value[:80]}")
    return ""

def build_column_name(raw_header, unit):
    """Build clean column header from OFGEM raw header + detected unit.
    Preserves semantic prefix (Standing Charge / Unit Rate).
    Reads period label directly from page — no hardcoded dates.

    Examples:
        'Daily standing charge January to March 2026' → 'Standing Charge January to March 2026 (pence/day)'
        'Unit rate April to June 2026'                → 'Unit Rate April to June 2026 (pence/kWh)'

    Fallback: if no prefix matches, raw header is title-cased and unit appended.
    """
    cleaned = raw_header.strip()

    # Map verbose OFGEM prefixes to clean semantic labels
    PREFIX_MAP = {
        "daily standing charge ": "Standing Charge ",
        "standing charge ":       "Standing Charge ",
        "unit rate ":             "Unit Rate ",
    }

    for prefix, replacement in PREFIX_MAP.items():
        if cleaned.lower().startswith(prefix):
            cleaned = replacement + cleaned[len(prefix):]
            break

    # Apply title case for consistent month capitalisation
    cleaned = cleaned.title()

    # Fix minor words incorrectly capitalised by title()
    for word in ["to", "and", "of", "the"]:
        cleaned = re.sub(rf'\b{word.title()}\b', word, cleaned)

    return f"{cleaned} ({unit})" if unit else cleaned

# -------------------------------------------------------------------------
# MAIN SCRAPER
# -------------------------------------------------------------------------
async def scrape_clean():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        print(f"Fetching: {URL}")
        await page.goto(URL, wait_until="domcontentloaded", timeout=60000)

        # Issue 2 fix: previously used fixed 8 second sleep — arbitrary and
        # fails silently on slow connections or heavier JS payloads.
        # Step 1: wait for summary table to confirm page is alive — fails loudly if broken
        await page.wait_for_selector("table td", timeout=30000)
        # Step 2: minimal buffer for JS to finish rendering regional tables
        await page.wait_for_timeout(5000)

        tables = await page.query_selector_all("table")
        print(f"Tables found: {len(tables)}")

        all_frames = []

        for i, table in enumerate(tables):
            if i not in TABLE_MAP:
                print(f"Table {i}: skipped (summary table)")
                continue

            html = await table.inner_html()
            df = pd.read_html(StringIO(f"<table>{html}</table>"))[0]

            # Detect units from first data row before cleaning
            # Column 0 is Region — start from column 1
            units = {}
            for col in df.columns[1:]:
                units[col] = detect_unit(str(df.iloc[0][col]), col_name=col)

            # Clean region column
            df.iloc[:, 0] = df.iloc[:, 0].apply(clean_region)

            # Extract numbers from value columns
            for col in df.columns[1:]:
                df[col] = df[col].apply(extract_number)

            # Build dynamic column names from page headers + detected units
            new_columns = ["Region"] + [
                build_column_name(col, units[col])
                for col in df.columns[1:]
            ]
            df.columns = new_columns

            # Add dimension columns
            payment, energy = TABLE_MAP[i]
            df["PaymentMethod"] = payment
            df["EnergyType"] = energy

            all_frames.append(df)
            print(f"Table {i}: {payment} — {energy} ✓")

        await browser.close()

        if all_frames:
            combined = pd.concat(all_frames, ignore_index=True)
            combined.to_csv(SAVE_PATH, index=False)
            print(f"\nSaved: {SAVE_PATH} — {combined.shape[0]} rows, {combined.shape[1]} columns")
            print(combined.head(10).to_string(index=False))
            return combined
        else:
            print("No data extracted.")
            return None

df = await scrape_clean()
