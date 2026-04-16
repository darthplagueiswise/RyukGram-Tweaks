// Single source of truth for date-format hook entries.
// Format: X(name, selector_cstring, label, arity, pref_key)
// Entries sharing a pref_key are toggled together; label is shown in the
// picker for the first entry sharing a given pref_key (use "" for others).

#define SCI_DATE_FORMAT_ENTRIES(X) \
    X(mixed,      "formattedDateInMixedFormat",                  "Feed posts",              0, "date_fmt_mixed") \
    X(rel,        "formattedDateRelativeToNow",                  "Notes, comments, stories",0, "date_fmt_notes_comments_stories") \
    X(shortRel,   "shortenedFormattedDateRelativeToNow",         "",                        0, "date_fmt_notes_comments_stories") \
    X(shortRelHs, "shortenedFormattedDateRelativeToNowHideSeconds:", "DMs",                 1, "date_fmt_dms")

// Kept for future use — other NSDate relative formatters IG uses across
// surfaces. Enable by adding to SCI_DATE_FORMAT_ENTRIES above.
//
// X(partialRel,               "partiallyShortenedFormattedDateRelativeToNow",                                             "Partially shortened relative",             0, "date_fmt_partialRel")
// X(shortRelYears,            "shortenedFormattedDateRelativeToNowIncludeYears",                                          "Shortened relative (incl. years)",         0, "date_fmt_shortRelYears")
// X(shortRelOpts,             "shortenedFormattedDateRelativeToNowWithOptions:",                                          "Shortened relative (options)",             1, "date_fmt_shortRelOpts")
// X(shortRelFloor,            "shortenedFormattedDateRelativeToNowWithFloorDaysWeeks:",                                   "Shortened rel. (floor days/weeks)",        1, "date_fmt_shortRelFloor")
// X(mixedShortRelMDY,         "formattedDateInMixedShortenedRelativeAndMonthDayYearFormatWithThreshold:",                 "Mixed shortened + M/D/Y",                  1, "date_fmt_mixedShortRelMDY")
// X(relHs,                    "formattedDateRelativeToNowHideSeconds:",                                                   "Relative (hide seconds)",                  1, "date_fmt_relHs")
// X(relYearsHs,               "formattedDateRelativeToNowIncludingYearsHideSeconds:",                                     "Rel. incl. years (hide seconds)",          1, "date_fmt_relYearsHs")
// X(partialRelHsOpts,         "partiallyShortenedFormattedDateRelativeToNowHideSeconds:options:",                         "Partial rel. (hide secs, opts)",           2, "date_fmt_partialRelHsOpts")
// X(relHsFloor,               "formattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:",                              "Relative (hide secs, floor)",              2, "date_fmt_relHsFloor")
// X(shortRelHsFloor,          "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:",                     "Shortened rel. (hide secs, floor)",        2, "date_fmt_shortRelHsFloor")
// X(shortRelHsFloorOpts,      "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:options:",             "Shortened rel. (hide secs, floor, opts)",  3, "date_fmt_shortRelHsFloorOpts")
// X(shortRelHsFloorYearsOpts, "shortenedFormattedDateRelativeToNowHideSeconds:shouldFloorDaysWeeks:includeYears:options:","Shortened rel. (full signature)",          4, "date_fmt_shortRelHsFloorYearsOpts")
