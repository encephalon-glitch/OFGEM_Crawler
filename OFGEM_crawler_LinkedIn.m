// OFGEM Energy Price Cap — Fact Table Pipeline
// Last updated: 30/09/2025
// Author: Martin Sefelin
//
// MAINTENANCE NOTES:
// Two variables control the entire pipeline — update these if OFGEM restructures their page:
//   CurrentWWW        → URL of the OFGEM energy price cap page
//   firstTBLStartIndex → HTML table index where pricing data begins (currently 17)
//
// Dimension relationships (payment method, cost category) are managed in the
// Excel data model (Power Pivot) rather than in M, allowing flexible slicing
// without query-level dependencies.

let
    // -------------------------------------------------------------------------
    // CONFIGURATION — update here only
    // -------------------------------------------------------------------------
    CurrentWWW = "https://www.ofgem.gov.uk/information-consumers/energy-advice-households/energy-price-cap-explained", // Update if OFGEM moves the page
    firstTBLStartIndex = 17, // Update if OFGEM restructures HTML table order

    // -------------------------------------------------------------------------
    // DATA SOURCE
    // -------------------------------------------------------------------------
    // Web.BrowserContents required — OFGEM tables are JavaScript-rendered
    Source = Web.BrowserContents(CurrentWWW),

    // -------------------------------------------------------------------------
    // COLUMN SELECTOR GENERATOR
    // Builds CSS selector pairs dynamically from a table index and column list.
    // Avoids hardcoding selectors for each column — add a column by updating ColumnIndices only.
    // -------------------------------------------------------------------------
    GenerateColumnSelectors = (TableNumber as number, ColumnIndices as list) as list =>
        List.Transform(
            ColumnIndices,
            each {
                "Column" & Number.ToText(_),
                "DIV.table-container.simplebar-container.border-color-theme:nth-child("
                    & Number.ToText(TableNumber)
                    & ") > TABLE > * > TR > :nth-child("
                    & Number.ToText(_)
                    & ")"
            }
        ),

    // Columns 2-4 contain the pricing data; column 1 (cost label) comes from the dimension table
    ColumnIndices = {2..4},

    // -------------------------------------------------------------------------
    // TABLE EXTRACTION FUNCTION
    // For a given HTML table index:
    //   1. Generates CSS selectors
    //   2. Scrapes and promotes headers
    //   3. Casts pricing columns to Currency type
    //   4. Adds a surrogate row index (PricingIndex) for dimension join
    //   5. Stamps the table index as a column (TableIndex) for payment method join
    // -------------------------------------------------------------------------
    ExtractTable = (TableNumber as number) as table =>
        let
            ColumnSelectors = GenerateColumnSelectors(TableNumber, ColumnIndices),
            TableContent = Table.PromoteHeaders(
                Html.Table(
                    Source,
                    ColumnSelectors,
                    [RowSelector = "DIV.table-container.simplebar-container.border-color-theme:nth-child("
                        & Number.ToText(TableNumber)
                        & ") > TABLE > * > TR"]
                ),
                [PromoteAllScalars = true]
            ),
            Headers = Table.ColumnNames(TableContent),
            TypedTable = Table.TransformColumnTypes(
                TableContent,
                {
                    {Headers{0}, Currency.Type},
                    {Headers{1}, Currency.Type},
                    {Headers{2}, Currency.Type}
                }
            ),
            IndexedTable = Table.AddIndexColumn(TypedTable, "PricingIndex", 1, 1, type number)
        in
            Table.AddColumn(IndexedTable, "TableIndex", each TableNumber, type number),

    // -------------------------------------------------------------------------
    // TABLE INDEX LIST
    // Generates {17, 19, 21, 23} — four tables, spaced 2 apart, from firstTBLStartIndex.
    // Controlled entirely by the config variable above.
    // -------------------------------------------------------------------------
    WebTableIndices = List.Sort(List.Numbers(firstTBLStartIndex, 4, 2), Order.Ascending),

    // -------------------------------------------------------------------------
    // FACT TABLE ASSEMBLY
    // Applies ExtractTable to each index, then stacks all four into one fact table.
    // -------------------------------------------------------------------------
    CombinedFactTable = Table.Combine(List.Transform(WebTableIndices, each ExtractTable(_))),

    // -------------------------------------------------------------------------
    // DIMENSION TABLES
    // DimensionTable1: Payment method lookup — keyed on TableIndex
    // DimensionTable2: Cost category labels — scraped live, keyed on PricingIndex
    // -------------------------------------------------------------------------
    DimensionTable1 = #table(
        {"TableIndex", "PaymentMethod"},
        {
            {WebTableIndices{0}, "Direct Debit"},
            {WebTableIndices{1}, "Prepayment Meter"},
            {WebTableIndices{2}, "Standard Credit"},
            {WebTableIndices{3}, "Economy 7 (E7) Meter"}
        }
    ),

    DimensionTable2 = Table.AddIndexColumn(
        Table.PromoteHeaders(
            Html.Table(
                Source,
                {{"Column1", "DIV.table-container.simplebar-container.border-color-theme:nth-child("
                    & Number.ToText(firstTBLStartIndex)
                    & ") > TABLE > * > TR > :nth-child(1)"}},
                [RowSelector = "DIV.table-container.simplebar-container.border-color-theme:nth-child("
                    & Number.ToText(firstTBLStartIndex)
                    & ") > TABLE > * > TR"]
            )
        ),
        "PricingIndex", 1, 1, type number
    ),

    // -------------------------------------------------------------------------
    // JOINS
    // Inner join fact table to both dimension tables, then drop surrogate keys.
    // -------------------------------------------------------------------------
    JoinedWithDimTable1 = Table.Join(CombinedFactTable, "TableIndex", DimensionTable1, "TableIndex", JoinKind.Inner),
    FinalResult = Table.Join(JoinedWithDimTable1, "PricingIndex", DimensionTable2, "PricingIndex", JoinKind.Inner)

in
    Table.RemoveColumns(FinalResult, {"PricingIndex", "TableIndex"})
