ensure_r_tempdir <- function() {
  td <- tempdir(check = TRUE)

  if (!dir.exists(td)) {
    dir.create(td, recursive = TRUE, showWarnings = FALSE)
  }

  if (!dir.exists(td)) {
    stop(
      "R temporary directory does not exist and could not be recreated: ",
      td,
      ". Restart R or set TMPDIR/TMP/TEMP to a writable directory before starting R.",
      call. = FALSE
    )
  }

  if (file.access(td, 2L) != 0L) {
    stop("R temporary directory is not writable: ", td, call. = FALSE)
  }

  invisible(td)
}

ensure_r_tempdir()
