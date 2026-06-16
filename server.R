if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()

library(shiny)
library(data.table)
library(DT)

TOC_URL <- "https://ec.europa.eu/eurostat/api/dissemination/catalogue/toc/txt?lang=EN"
REQUIRED_TOC_COLUMNS <- c(
  "title", "code", "type", "last.update.of.data",
  "last.table.structure.change", "data.start", "data.end"
)
INTERNAL_COLUMNS <- c("LastUpdateDate", "LastStructDate", "SearchTextLower", "CodeLower")
SEARCH_PROMPT <- HTML("<h5>Enter filtering condition(s)/text in the search field(s), then click the Update View button or press Enter in a search field.</h5>")

myRecursFill <- eurodata:::myRecursFill

trim_text <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  trimws(x)
}

clean_title <- function(x) {
  x <- gsub("[\r\n]+", " ", as.character(x), perl = TRUE)
  sub("^\\s+", "", x, perl = TRUE)
}

toc_level <- function(title) {
  pos <- regexpr("[^[:space:]]", as.character(title), perl = TRUE)
  pos[pos < 1L | is.na(pos)] <- 1L
  as.integer((pos - 1L) %/% 4L)
}

parse_toc_date <- function(x) {
  suppressWarnings(as.IDate(trim_text(x), format = "%d.%m.%Y"))
}

format_toc_date <- function(x) {
  y <- format(x, "%Y.%m.%d")
  y[is.na(x)] <- ""
  y
}

normalise_toc_names <- function(dt) {
  setnames(dt, make.names(tolower(names(dt)), unique = TRUE))
  dt
}

has_toc_columns <- function(dt) {
  !is.null(dt) && all(REQUIRED_TOC_COLUMNS %chin% names(dt))
}

parse_toc_candidate <- function(text, method) {
  switch(
    method,
    fread_tab = fread(
      text = text,
      sep = "\t",
      header = TRUE,
      quote = "\"",
      encoding = "UTF-8",
      fill = TRUE,
      showProgress = FALSE,
      check.names = TRUE
    ),
    fread_space = fread(
      text = text,
      sep = " ",
      header = TRUE,
      quote = "\"",
      encoding = "UTF-8",
      fill = TRUE,
      showProgress = FALSE,
      check.names = TRUE
    ),
    fread_auto = fread(
      text = text,
      sep = "auto",
      header = TRUE,
      quote = "\"",
      encoding = "UTF-8",
      fill = TRUE,
      showProgress = FALSE,
      check.names = TRUE
    ),
    read_table = as.data.table(utils::read.table(
      text = text,
      header = TRUE,
      sep = "",
      quote = "\"",
      stringsAsFactors = FALSE,
      check.names = TRUE,
      comment.char = "",
      fill = TRUE,
      blank.lines.skip = FALSE
    ))
  )
}

read_toc <- function(url = TOC_URL) {
  raw <- readLines(url, encoding = "UTF-8", warn = FALSE)
  raw <- gsub(" \t \t", "\t", raw, fixed = TRUE)
  text <- paste(raw, collapse = "\n")

  errors <- character()
  for (method in c("fread_tab", "fread_space", "fread_auto", "read_table")) {
    parsed <- tryCatch(
      list(dt = parse_toc_candidate(text, method), error = NULL),
      error = function(e) list(dt = NULL, error = conditionMessage(e))
    )

    if (is.null(parsed$dt)) {
      errors <- c(errors, paste0(method, ": ", parsed$error))
      next
    }

    dt <- as.data.table(parsed$dt)
    normalise_toc_names(dt)
    if (has_toc_columns(dt)) return(dt[])

    errors <- c(
      errors,
      paste0(method, ": missing ", paste(setdiff(REQUIRED_TOC_COLUMNS, names(dt)), collapse = ", "))
    )
  }

  stop(
    "Eurostat TOC could not be parsed. Parse attempts: ",
    paste(errors, collapse = " | "),
    call. = FALSE
  )
}

paste_columns <- function(dt, cols) {
  cols <- cols[cols %chin% names(dt)]
  if (!length(cols)) return(rep("", nrow(dt)))
  do.call(paste, c(lapply(cols, function(col) dt[[col]]), sep = " "))
}

encode_url_piece <- function(x) {
  vapply(trim_text(x), utils::URLencode, character(1L), reserved = TRUE, USE.NAMES = FALSE)
}

make_browser_url <- function(code) {
  paste0("https://ec.europa.eu/eurostat/databrowser/view/", encode_url_piece(code), "/default/table?lang=en")
}

make_explain_url <- function(code) {
  paste0(
    "https://chatgpt.com/?prompt=Explain+what+the+eurostat+dataset+%22",
    encode_url_piece(code),
    "%22+is+about+and+what+questions+I+can+use+it+for%2E"
  )
}

build_catalogue <- function(url = TOC_URL) {
  raw <- read_toc(url)
  if ("values" %chin% names(raw)) raw[, values := NULL]

  raw[, `:=`(
    id = .I,
    level = toc_level(title),
    title_clean = clean_title(title),
    type_clean = tolower(trim_text(type)),
    LastUpdateDate = parse_toc_date(last.update.of.data),
    LastStructDate = parse_toc_date(last.table.structure.change)
  )]

  hierarchy <- dcast(raw[, .(id, level, title_clean)], id ~ level, value.var = "title_clean", fill = "")
  setorder(hierarchy, id)
  level_cols <- setdiff(names(hierarchy), "id")
  level_cols <- level_cols[order(suppressWarnings(as.integer(level_cols)))]
  setcolorder(hierarchy, c("id", level_cols))

  if (length(level_cols)) {
    m <- as.matrix(hierarchy[, ..level_cols])
    storage.mode(m) <- "character"
    m[is.na(m)] <- ""
    filled <- as.data.table(myRecursFill(m))
    setnames(filled, level_cols)
    hierarchy[, (level_cols) := filled]
  }

  keep <- raw$type_clean %chin% c("dataset", "table")
  hierarchy <- hierarchy[raw[keep, .(id)], on = "id"]
  hierarchy[, id := NULL]

  if (length(level_cols)) {
    group_cols <- head(level_cols, -1L)
    if (length(group_cols)) setnames(hierarchy, group_cols, sprintf("Data subgroup, level %d", seq_along(group_cols)))
    setnames(hierarchy, tail(level_cols, 1L), "Dataset name")
  } else {
    hierarchy[, `Dataset name` := raw[keep, title_clean]]
  }

  meta <- raw[keep, .(
    Code = trim_text(code),
    `Last update of data` = format_toc_date(LastUpdateDate),
    `Last table structure change` = format_toc_date(LastStructDate),
    `Data start` = trim_text(data.start),
    `Data end` = trim_text(data.end),
    LastUpdateDate,
    LastStructDate
  )]

  out <- as.data.table(cbind(hierarchy, meta))
  out[, `:=`(
    Link = make_browser_url(Code),
    Explain = make_explain_url(Code),
    SearchTextLower = tolower(paste_columns(out, c(names(hierarchy), "Code"))),
    CodeLower = tolower(Code)
  )]
  setcolorder(out, c(
    names(hierarchy), "Code", "Last update of data", "Last table structure change",
    "Data start", "Data end", "Link", "Explain", INTERNAL_COLUMNS
  ))
  out[]
}

split_terms <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1L]])) return(character())
  x <- trimws(x[[1L]])
  if (!nzchar(x)) return(character())
  terms <- unlist(strsplit(x, "\\s+", perl = TRUE), use.names = FALSE)
  tolower(terms[nzchar(terms)])
}

has_all_terms <- function(text, terms) {
  if (!length(terms)) return(rep(TRUE, length(text)))
  Reduce(`&`, lapply(terms, function(term) grepl(term, text, fixed = TRUE)))
}

has_any_term <- function(text, terms) {
  if (!length(terms)) return(rep(FALSE, length(text)))
  Reduce(`|`, lapply(terms, function(term) grepl(term, text, fixed = TRUE)))
}

criteria_from_values <- function(keyword = "", keyword2 = "", keyword3 = "") {
  list(
    whole = keyword,
    code = keyword2,
    exclude = keyword3
  )
}


criteria_from_payload <- function(payload) {
  val <- function(id) {
    x <- payload[[id]]
    if (is.null(x) || !length(x) || is.na(x[[1L]])) "" else x[[1L]]
  }
  criteria_from_values(val("keyword"), val("keyword2"), val("keyword3"))
}

criteria_has_terms <- function(criteria) {
  any(nzchar(trimws(unlist(criteria, use.names = FALSE))))
}

filter_catalogue <- function(dt, criteria) {
  keep <- !is.na(dt$Code) & nzchar(dt$Code)

  whole_terms <- split_terms(criteria$whole)
  code_terms <- split_terms(criteria$code)
  exclude_terms <- split_terms(criteria$exclude)

  if (length(whole_terms)) keep <- keep & has_all_terms(dt$SearchTextLower, whole_terms)
  if (length(code_terms)) keep <- keep & has_any_term(dt$CodeLower, code_terms)
  if (length(exclude_terms)) keep <- keep & !has_any_term(dt$SearchTextLower, exclude_terms)

  ans <- copy(dt[keep])
  if (nrow(ans)) {
    setorderv(ans, c("LastUpdateDate", "Code"), order = c(-1L, 1L), na.last = TRUE)
    ans[, No := .I]
    ans[, `Duplicated?` := duplicated(Code)]
    setcolorder(ans, c("No", setdiff(names(ans), "No")))
  }
  ans[]
}

drop_internal_columns <- function(dt) {
  cols <- intersect(INTERNAL_COLUMNS, names(dt))
  if (length(cols)) dt[, (cols) := NULL]
  invisible(dt)
}

drop_empty_columns <- function(dt) {
  keep <- vapply(dt, function(x) {
    if (is.numeric(x) || is.logical(x) || inherits(x, "Date")) return(TRUE)
    any(nzchar(trim_text(x)))
  }, logical(1L))
  dt[, names(dt)[keep], with = FALSE]
}

make_anchor <- function(url, text) {
  url <- htmltools::htmlEscape(url, attribute = TRUE)
  text <- htmltools::htmlEscape(text)
  sprintf('<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>', url, text)
}

make_display <- function(dt) {
  if (identical(dt, SEARCH_PROMPT)) return(data.table(Message = SEARCH_PROMPT))
  if (identical(names(dt), "Message")) return(as.data.table(copy(dt)))
  if (!nrow(dt)) return(data.table(Message = "Nothing found"))

  out <- copy(dt)
  drop_internal_columns(out)
  out <- drop_empty_columns(out)

  if ("Dataset name" %chin% names(out)) {
    out[, `Dataset name` := paste0("<b>", htmltools::htmlEscape(`Dataset name`), "</b>")]
  }
  if ("Link" %chin% names(out)) out[, Link := make_anchor(Link, "link")]
  if ("Explain" %chin% names(out)) out[, Explain := make_anchor(Explain, "explain")]

  out[]
}

make_download <- function(dt) {
  if (identical(dt, SEARCH_PROMPT)) return(data.frame(Message = SEARCH_PROMPT))
  if (identical(names(dt), "Message")) return(as.data.frame(copy(dt)))
  if (!nrow(dt)) return(data.frame(Message = "Nothing found"))

  out <- copy(dt)
  drop_internal_columns(out)
  out <- drop_empty_columns(out)

  for (col in intersect(c("Link", "Explain"), names(out))) {
    class(out[[col]]) <- unique(c("hyperlink", class(out[[col]])))
  }
  as.data.frame(out)
}

safe_file_piece <- function(x) {
  x <- trimws(x)
  if (!nzchar(x)) x <- "ALL"
  x <- toupper(x)
  x <- gsub("[^[:alnum:] ._()-]+", "_", x, perl = TRUE)
  x <- gsub("\\s+", " ", x, perl = TRUE)
  substr(x, 1L, 160L)
}

make_filename <- function(criteria) {
  label <- trimws(paste(criteria$whole, criteria$code))
  if (!nzchar(label)) label <- "ALL"
  if (nzchar(trimws(criteria$exclude))) label <- paste(label, "excluding", criteria$exclude)
  paste0("The list of Eurostat datasets found for ", safe_file_piece(label), ".xlsx")
}

results_datatable <- function(dt) {
  if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()
  html_cols <- c("Dataset name", "Link", "Explain")
  escape_cols <- if (identical(names(dt), "Message")) TRUE else which(!names(dt) %chin% html_cols)

  datatable(
    dt,
    rownames = FALSE,
    escape = escape_cols,
    selection = "none",
    filter = "none",
    options = list(
      dom = '<"top"li>rt<"bottom"p><"clear">',
      pageLength = -1,
      lengthMenu = list(c(25, 100, 500, 1000, -1), c("25", "100", "500", "1000", "All")),
      deferRender = TRUE,
      scrollX = TRUE,
      searching = FALSE
    )
  )
}

shinyServer(function(input, output, session) {
  catalogue_cache <- reactiveVal(NULL)
  result_state <- reactiveVal(list(
    data = SEARCH_PROMPT,
    criteria = criteria_from_values(),
    show_table = FALSE,
    message = SEARCH_PROMPT,
    error = FALSE
  ))

  observe({
    invalidateLater(60000, session)
    if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()
  })

  set_spinner <- function(show) {
    session$sendCustomMessage("findEstatSpinner", list(show = isTRUE(show)))
  }

  get_catalogue <- function() {
    cached <- catalogue_cache()
    if (!is.null(cached)) return(cached)
    dt <- build_catalogue()
    catalogue_cache(dt)
    dt
  }

  set_prompt_state <- function(criteria) {
    result_state(list(
      data = SEARCH_PROMPT,
      criteria = criteria,
      show_table = FALSE,
      message = SEARCH_PROMPT,
      error = FALSE
    ))
  }

  run_search <- function(criteria) {
    if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()
    on.exit(set_spinner(FALSE), add = TRUE)

    if (!criteria_has_terms(criteria)) {
      set_prompt_state(criteria)
      return(invisible(NULL))
    }

    state <- tryCatch({
      dt <- get_catalogue()
      data <- filter_catalogue(dt, criteria)
      list(
        data = data,
        criteria = criteria,
        show_table = TRUE,
        message = NULL,
        error = FALSE
      )
    }, error = function(e) {
      msg <- paste("Search failed:", conditionMessage(e))
      list(
        data = data.table(Message = msg),
        criteria = criteria,
        show_table = FALSE,
        message = msg,
        error = TRUE
      )
    })

    result_state(state)
    invisible(NULL)
  }

  observeEvent(input$searchCriteria, {
    run_search(criteria_from_payload(input$searchCriteria))
  }, ignoreInit = TRUE)

  output$results <- renderUI({
    state <- result_state()
    if (isTRUE(state$show_table)) return(DTOutput("df"))

    if (isTRUE(state$error)) {
      return(tags$p(state$message, class = "text-danger"))
    }

    msg <- state$message
    if (is.null(msg) || !nzchar(msg)) msg <- SEARCH_PROMPT
    tags$p(msg)
  })

  output$df <- renderDT({
    state <- result_state()
    tryCatch(
      results_datatable(make_display(state$data)),
      error = function(e) results_datatable(data.table(Message = paste("Table rendering failed:", conditionMessage(e))))
    )
  }, server = FALSE)

  output$downloadData <- downloadHandler(
    filename = function() {
      make_filename(result_state()$criteria)
    },
    content = function(file) {
      if (exists("ensure_r_tempdir", mode = "function")) ensure_r_tempdir()
      if (!requireNamespace("openxlsx", quietly = TRUE)) {
        stop("The openxlsx package is required for XLSX downloads.")
      }
      openxlsx::write.xlsx(make_download(result_state()$data), file, overwrite = TRUE, asTable = TRUE)
    }
  )
})
