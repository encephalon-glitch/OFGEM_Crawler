// Rolling Calendar — Date Dimension Table
// Version: 1.9
// Last reviewed: 27/10/2024
//
// Generates a dynamic date table covering a rolling 2-year window from today.
// Refreshes automatically — no hardcoded date ranges.
//
// OUTPUT COLUMNS:
//   Date                  → Calendar date
//   DayOfWeek             → Full day name (e.g. "Monday")
//   CalendarQuarter       → Q1–Q4 (January start)
//   FiscalQuarter         → Q1–Q4 (April start, UK fiscal year convention)
//   RollingCalendarDays   → Days remaining in the calendar year from this date
//   RollingFiscalDays     → Days remaining in the fiscal year from this date
//   RollingCalendarWeeks  → ISO 8601 week number

shared RollingCalendar = let

    // -------------------------------------------------------------------------
    // INNER FUNCTION: AddQuartersColumn
    // Takes a single date and returns a record containing all calculated fields.
    // Called row-by-row via Table.AddColumn below.
    // -------------------------------------------------------------------------
    AddQuartersColumn = (DateColumn as date) =>
        let
            // --- Calendar and Fiscal Quarters ---
            CalendarQuarter = "Q" & Text.From(Date.QuarterOfYear(DateColumn)),
            // Fiscal year starts April — Q1 calendar = Q4 fiscal
            FiscalQuarter   = "Q" & Text.From(
                if Date.QuarterOfYear(DateColumn) = 1
                then 4
                else Date.QuarterOfYear(DateColumn) - 1
            ),

            // --- Rolling Calendar Days ---
            // Days remaining in the calendar year, inclusive of current date
            DaysInYear          = Date.DayOfYear(Date.EndOfYear(DateColumn)),
            RollingCalendarDays = DaysInYear - Date.DayOfYear(DateColumn) + 1,

            // --- Rolling Fiscal Days ---
            // Fiscal year: April 1 to March 31
            StartOfFiscalYear  = if Date.Month(DateColumn) >= 4
                                 then #date(Date.Year(DateColumn), 4, 1)
                                 else #date(Date.Year(DateColumn) - 1, 4, 1),
            EndOfFiscalYear    = Date.AddYears(StartOfFiscalYear, 1) - #duration(1, 0, 0, 0),
            DaysInFiscalYear   = Duration.Days(EndOfFiscalYear - StartOfFiscalYear),
            RollingFiscalDays  = DaysInFiscalYear - Duration.Days(DateColumn - StartOfFiscalYear) + 1,

            // --- ISO 8601 Week Number ---
            // ISO week 1 = week containing the first Thursday of the year.
            // Weeks start on Monday. Week 53 rolls back to week 52 if calculated as 0.
            FirstThursday     = Date.AddDays(
                                    #date(Date.Year(DateColumn), 1, 4),
                                    3 - Date.DayOfWeek(#date(Date.Year(DateColumn), 1, 4))
                                ),
            ISOStartOfYear    = Date.StartOfWeek(Date.AddDays(FirstThursday, -3), Day.Monday),
            RollingCalendarWeeks =
                // Edge case: date falls before ISO year start (last days of December)
                if Date.DayOfWeek(DateColumn) = Day.Monday and DateColumn < ISOStartOfYear
                then 1
                else if DateColumn < ISOStartOfYear
                then Number.RoundUp(
                    Duration.Days(
                        Date.AddYears(DateColumn, -1)
                        - Date.StartOfWeek(
                            Date.AddDays(
                                #date(Date.Year(Date.AddYears(DateColumn, -1)), 1, 4),
                                3 - Date.DayOfWeek(#date(Date.Year(Date.AddYears(DateColumn, -1)), 1, 4))
                            ),
                            Day.Monday
                        )
                        + #duration(0, 0, 0, 1)
                    ) / 7
                )
                else Number.RoundUp(
                    Duration.Days(DateColumn - ISOStartOfYear + #duration(0, 0, 0, 1)) / 7
                )
        in
            [
                CalendarQuarter      = CalendarQuarter,
                FiscalQuarter        = FiscalQuarter,
                RollingCalendarDays  = RollingCalendarDays,
                RollingFiscalDays    = RollingFiscalDays,
                RollingCalendarWeeks = if RollingCalendarWeeks = 0 then 52 else RollingCalendarWeeks
            ],

    // -------------------------------------------------------------------------
    // DATE RANGE GENERATION
    // Builds a list of daily dates from 2 years ago to today.
    // Window moves automatically on each refresh — no hardcoded start date.
    // -------------------------------------------------------------------------
    StartDate  = Date.AddYears(Date.From(DateTime.LocalNow()), -2),
    DatesList  = List.Dates(
                     StartDate,
                     Duration.Days(Date.From(DateTime.LocalNow()) - StartDate),
                     #duration(1, 0, 0, 0)
                 ),
    DatesTable = Table.FromColumns({DatesList}, {"Date"}),

    // -------------------------------------------------------------------------
    // COLUMN ADDITIONS
    // -------------------------------------------------------------------------
    // Add full day name
    AddedDayOfWeek = Table.AddColumn(DatesTable, "DayOfWeek", each Date.DayOfWeekName([Date]), type text),

    // Apply AddQuartersColumn to each row, expand the returned record into columns
    AddQuarters = Table.ExpandRecordColumn(
        Table.AddColumn(AddedDayOfWeek, "Quarters", each AddQuartersColumn([Date])),
        "Quarters",
        {"CalendarQuarter", "FiscalQuarter", "RollingCalendarDays", "RollingFiscalDays", "RollingCalendarWeeks"}
    ),

    // Final column order
    ReorderedColumns = Table.ReorderColumns(
        AddQuarters,
        {"Date", "DayOfWeek", "CalendarQuarter", "FiscalQuarter", "RollingCalendarDays", "RollingFiscalDays", "RollingCalendarWeeks"}
    )

in
    ReorderedColumns
