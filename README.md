# Find Eurostat dataset(s)

## You can use the app at https://shiny-r.dev/find_estat/

A small **[R](https://www.r-project.org/)/[Shiny](https://CRAN.R-project.org/package=shiny)** app for quickly finding relevant Eurostat datasets and tables by searching the Eurostat catalogue, the Eurostat data-group hierarchy, dataset/table names, and dataset/table codes.

The app is meant for users who know roughly what they want to study, but do not yet know the exact Eurostat dataset code. It returns matching codes, qualitative size classes, update metadata, direct Eurostat Data Browser links, and one-click `explain` links that open a ChatGPT prompt for the selected code.

## What it does

- Searches Eurostat's Catalogue API table of contents.
- Reconstructs Eurostat's hierarchical data-group tree, so each result keeps its topic context.
- Supports three app-level search fields:
  - **Whole catalogue search**: logical AND across the data-group tree, dataset/table names, and codes.
  - **Dataset/table code search**: logical OR across dataset/table codes only.
  - **Exclude search**: logical OR across the data-group tree, dataset/table names, and codes.
- Combines non-empty search fields with logical AND.
- Ignores upper/lower case differences.
- Treats space-separated search words as literal terms, not regular expressions.
- Opens matching datasets/tables in the Eurostat Data Browser.
- Adds a static `Size` column based on the Eurostat TOC `values` field, classified into quintile-based qualitative classes.
- Adds an `Explain` column whose link text is lower-case `explain` and whose URL opens a ChatGPT prompt for the dataset/table code.
- Downloads the current search result as an XLSX file with hyperlink columns preserved.

## Data source

The app reads the Eurostat catalogue from:

```text
https://ec.europa.eu/eurostat/api/dissemination/catalogue/toc/txt?lang=EN
```

Eurostat documents the Catalogue API as a source for the current listing of disseminated data products. Its table of contents, or TOC, is a text or XML representation of the Eurostat navigation tree and includes information on available datasets and tables.

Useful official documentation:

- [Eurostat API introduction](https://ec.europa.eu/eurostat/web/user-guides/data-browser/api-data-access/api-introduction)
- [Getting started with the Catalogue API](https://ec.europa.eu/eurostat/web/user-guides/data-browser/api-data-access/api-getting-started/catalogue-api)
- [Catalogue API TOC guidelines](https://ec.europa.eu/eurostat/web/user-guides/data-browser/api-data-access/api-detailed-guidelines/catalogue-api/toc)
- [Eurostat API Swagger UI](https://ec.europa.eu/eurostat/api/dissemination/swagger-ui)

The app does not download the actual statistical observations from Eurostat. It searches the catalogue of available datasets and tables.

## User interface behavior

When the app first opens, it does **not** display the full Eurostat catalogue. Rendering the full table is slow and usually not useful. Instead, the user sees a short prompt asking them to enter filtering text and click **Update View**.

After a search is submitted, the table shows the matching rows. The DataTables entry count, for example `Showing 1 to 70 of 70 entries`, is displayed above the table.

The DataTables built-in search boxes are disabled on purpose. The intended workflow is to use the three app-level search fields and then click **Update View**.

## Performance notes

This app is designed to avoid repeated expensive work during one user session.

- The Eurostat TOC download/preparation is started asynchronously with `mirai` daemons as soon as a user session opens.
- The download/preparation is started only once per Shiny session and the parsed catalogue, including the static quintile-based `Size` classification, is cached in a session-local `reactiveVal()`.
- The catalogue is stored and filtered with `data.table`.
- Display and download tables are made from defensive `copy()` calls before mutating columns, because `data.table` updates columns by reference when using `:=`.
- The hierarchy fill intentionally uses `eurodata:::myRecursFill`, because the native R alternative was too slow for the old app's workload.
- `mirai` daemons are pre-launched at app startup, which avoids the per-search worker start-up cost of launching fresh background R processes.
- The default daemon count is bounded at four local daemons and can be overridden with the `FIND_ESTAT_MIRAI_DAEMONS` environment variable.
- The result table uses DataTables server-side rendering and deferred rendering.

If the user searches before the asynchronous preparation has finished, the submitted search is queued and runs automatically as soon as the session-local catalogue cache is ready. Later searches in the same user session reuse the cached catalogue.

## Requirements

Install R and the packages used by the app:

```r
install.packages(c(
  "shiny",
  "data.table",
  "DT",
  "htmltools",
  "openxlsx",
  "eurodata",
  "promises",
  "mirai"
))
```

Notes:

- `openxlsx` is needed for Excel export.
- `eurodata` is needed because `server.R` intentionally calls the non-exported helper `eurodata:::myRecursFill`.
- `promises` and `mirai` are needed for the asynchronous, non-blocking Eurostat catalogue preparation.
- Because `myRecursFill` is accessed with `:::`, it is not part of a guaranteed public API. For stable deployments, pin package versions with `renv` or another reproducibility tool.
- On Windows, source installs of packages with compiled code may require Rtools. CRAN binaries usually avoid this for common R versions.

## Running locally

From the project directory:

```r
shiny::runApp()
```

Or from another working directory:

```r
shiny::runApp("path/to/find_estat")
```

The machine running the app needs internet access so it can start downloading and preparing the Eurostat TOC when each session opens.

## Repository layout

```text
.
├── README.md
├── server.R
└── ui.R
```

## Main files

`ui.R` defines the page layout, the three search boxes, the original submit-style **Update View** button, the download button, and the results area.

`server.R` starts local `mirai` daemons at app startup, launches the Eurostat TOC download/parsing asynchronously when a session opens, builds the hierarchical catalogue, calculates the static `Size` class from the Eurostat TOC `values` field, caches the result per session, applies the search criteria, formats links, renders the table, and writes XLSX downloads.

## Search semantics

| Search field | Scope | Terms inside the field |
|---|---|---|
| Whole catalogue search | Data-group tree, dataset/table names, and codes | Logical AND |
| Dataset/table code search | Dataset/table codes only | Logical OR |
| Exclude search | Data-group tree, dataset/table names, and codes | Logical OR exclusion |

If several search fields are non-empty, they are combined with logical AND.

## Search examples

| Goal | Field values |
|---|---|
| Find population migration datasets | Whole catalogue search: `population migration` |
| Search known code fragments | Dataset/table code search: `demo migr` |
| Search labour-market datasets but exclude wages/earnings | Whole catalogue search: `labour employment`; Exclude search: `wage earnings salary` |
| Search national accounts GDP-like codes | Dataset/table code search: `nama gdp` |

The search is case-insensitive and literal. It does not use regular expressions.

## Output columns

Typical result columns include:

- `No`: result row number after filtering and sorting.
- `Data subgroup, level 1`, `Data subgroup, level 2`, and deeper levels where present: hierarchical Eurostat topic context.
- `Dataset name`: dataset or table title.
- `Code`: Eurostat dataset/table code.
- `Size`: qualitative class based on the Eurostat TOC `values` field. The classes are `very small`, `small`, `medium`, `large`, and `very large`, using the 20th, 40th, 60th, and 80th percentiles of dataset/table `values` as thresholds.
- `Last update of data`: latest data update date, formatted as `YYYY.MM.DD`.
- `Last table structure change`: latest structural update date, formatted as `YYYY.MM.DD`.
- `Data start` and `Data end`: available data range from the TOC.
- `Link`: opens the dataset/table in the Eurostat Data Browser, shown as `link` in the table.
- `Explain`: opens a ChatGPT prompt for the dataset/table code, shown as `explain` in the table.
- `Duplicated?`: flags repeated codes in the filtered result.

Empty hierarchy columns are dropped from the rendered and downloaded result to keep the output readable.

Results are sorted by most recent data update first, then by dataset/table code.

## XLSX downloads

Click **Download** to export the current search result. The generated workbook preserves `Link` and `Explain` as spreadsheet hyperlinks when `openxlsx` is installed.

If no search has been submitted, the download contains the same guidance message shown on the initial page.

## Deployment notes

For Shiny Server, copy the directory containing `ui.R`, `server.R`, and this `README.md` into the Shiny app directory.

For managed deployments such as Posit Connect or shinyapps.io, make sure all package dependencies are available, especially `eurodata`.

For reproducible deployment, consider adding an `renv.lock` file after testing the exact package versions used in production:

```r
install.packages("renv")
renv::init()
renv::snapshot()
```

Commit `renv.lock` with the app.

## Troubleshooting

### The first search says the catalogue is still loading

This can happen if the user submits a search before the background Eurostat TOC download/preparation has finished. The submitted search is kept and runs automatically when the prepared catalogue is cached for that session.

### The app starts but shows no table

This is expected on first load. Enter at least one search condition and click **Update View**.

### `there is no package called 'eurodata'`

Install or deploy the `eurodata` package:

```r
install.packages("eurodata")
```

### `there is no package called 'mirai'`

Install or deploy the `mirai` package:

```r
install.packages("mirai")
```

### `object 'myRecursFill' not found` or a similar error

Check that the installed `eurodata` package version still contains the internal function `myRecursFill`. Since this function is accessed with `:::`, it is not part of a guaranteed public API.

### XLSX download fails

Install `openxlsx` on the server running the app:

```r
install.packages("openxlsx")
```

### Eurostat catalogue cannot be downloaded

Check that the machine running the app has internet access and that your network or proxy allows access to `ec.europa.eu`.

### Eurostat TOC format changed

The app checks for required TOC columns. If Eurostat changes the TXT schema, update `REQUIRED_TOC_COLUMNS` and the parsing logic in `server.R`.

## Privacy notes

The app sends a request to Eurostat when each Shiny session opens, so the catalogue can be prepared in a `mirai` background daemon before the first search. The `Explain` link does not send anything from the Shiny server to ChatGPT; it is only a hyperlink containing the selected Eurostat dataset/table code. When clicked, it opens ChatGPT in the user's browser.

## Maintenance checklist

Before publishing a new release:

- Open the app and confirm that the initial page shows the guidance message rather than the full catalogue.
- Run a broad search and confirm that results appear after one click on **Update View**.
- Confirm that the `Size` column is present and contains only `very small`, `small`, `medium`, `large`, or `very large` for rows with a usable Eurostat TOC `values` entry.
- Confirm that the `Link` column opens Eurostat Data Browser pages.
- Confirm that the `Explain` column displays `explain` and opens the expected prompt URL.
- Download an XLSX file and verify that the hyperlink columns work.
- Test the deployed environment with the intended `eurodata` version.

## License

No license file is included in this refactor. Add a `LICENSE` file before publishing the repository if you want others to know how they may use, modify, or redistribute the code.
